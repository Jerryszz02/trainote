import Foundation
import llama

protocol OnDeviceModelRuntime: Sendable {
    func generate(prompt: String, grammar: String, maximumTokens: Int) async throws -> String
}

enum OnDeviceRuntimeError: Error {
    case modelUnavailable, modelLoadFailed, contextCreationFailed, invalidGrammar
    case inputTooLong, tokenLimit, decodingFailed, timedOut, resourcePressure
}

/// One inference at a time. This actor never runs model work on MainActor and never uses the network.
actor BundledLlamaRuntime: OnDeviceModelRuntime {
    static let modelRevision = "c1899de289a04d12100db370d81485cdf75e47ca"
    static let quantization = "Q4_K_M"
    static let modelFilename = "qwen3-0.6b-q4_k_m"
    private static let backend: Void = { llama_backend_init() }()
    private let modelURL: URL?
    private let timeout: TimeInterval

    init(modelURL: URL? = Bundle.main.url(forResource: modelFilename, withExtension: "gguf"), timeout: TimeInterval = 90) {
        self.modelURL = modelURL
        self.timeout = max(0.01, min(timeout, 180))
    }

    func generate(prompt: String, grammar: String, maximumTokens: Int) async throws -> String {
        try Task.checkCancellation()
        let cancellation = InferenceCancellation(timeout: timeout)
        return try await withTaskCancellationHandler {
            try generateSynchronously(prompt: prompt, grammar: grammar, maximumTokens: maximumTokens, cancellation: cancellation)
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func generateSynchronously(prompt: String, grammar: String, maximumTokens: Int, cancellation: InferenceCancellation) throws -> String {
        #if os(iOS)
        guard ProcessInfo.processInfo.thermalState != .critical, ProcessInfo.processInfo.thermalState != .serious else { throw OnDeviceRuntimeError.resourcePressure }
        #endif
        guard let modelURL, FileManager.default.fileExists(atPath: modelURL.path) else { throw OnDeviceRuntimeError.modelUnavailable }
        guard maximumTokens > 0, maximumTokens <= 256, prompt.utf8.count <= 24_000, grammar.utf8.count <= 24_000 else { throw OnDeviceRuntimeError.inputTooLong }
        _ = Self.backend
        let callbackData = Unmanaged.passUnretained(cancellation).toOpaque()
        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #else
        modelParams.n_gpu_layers = 99
        #endif
        modelParams.progress_callback_user_data = callbackData
        modelParams.progress_callback = { _, data in
            guard let data else { return false }
            return !Unmanaged<InferenceCancellation>.fromOpaque(data).takeUnretainedValue().shouldStop
        }
        guard let model = llama_model_load_from_file(modelURL.path, modelParams) else {
            try cancellation.check()
            throw OnDeviceRuntimeError.modelLoadFailed
        }
        defer { llama_model_free(model) }
        try cancellation.check()
        guard let vocab = llama_model_get_vocab(model) else { throw OnDeviceRuntimeError.modelLoadFailed }
        var tokens = [llama_token](repeating: 0, count: 2048)
        let count = prompt.withCString { llama_tokenize(vocab, $0, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true) }
        guard count > 0, Int(count) + maximumTokens <= 2048 else { throw OnDeviceRuntimeError.inputTooLong }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048
        contextParams.n_batch = 256
        contextParams.n_ubatch = 256
        contextParams.n_threads = Int32(min(4, ProcessInfo.processInfo.activeProcessorCount))
        contextParams.n_threads_batch = contextParams.n_threads
        contextParams.abort_callback_data = callbackData
        contextParams.abort_callback = { data in
            guard let data else { return true }
            return Unmanaged<InferenceCancellation>.fromOpaque(data).takeUnretainedValue().shouldStop
        }
        guard let context = llama_init_from_model(model, contextParams) else { throw OnDeviceRuntimeError.contextCreationFailed }
        defer { llama_free(context) }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw OnDeviceRuntimeError.invalidGrammar }
        defer { llama_sampler_free(sampler) }
        guard !grammar.isEmpty, let grammarSampler = llama_sampler_init_grammar(vocab, grammar, "root") else { throw OnDeviceRuntimeError.invalidGrammar }
        llama_sampler_chain_add(sampler, grammarSampler)
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        for start in stride(from: 0, to: Int(count), by: 256) {
            try cancellation.check()
            let end = min(start + 256, Int(count))
            let status = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress!.advanced(by: start), Int32(end - start)))
            }
            try cancellation.check()
            guard status == 0 else { throw OnDeviceRuntimeError.decodingFailed }
        }
        var output = Data()
        for _ in 0..<maximumTokens {
            try cancellation.check()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                guard let result = String(data: output, encoding: .utf8) else { throw OnDeviceRuntimeError.decodingFailed }
                return result
            }
            var piece = [CChar](repeating: 0, count: 256)
            var size = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if size < 0 {
                piece = [CChar](repeating: 0, count: Int(-size))
                size = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            }
            guard size >= 0 else { throw OnDeviceRuntimeError.decodingFailed }
            output.append(contentsOf: piece.prefix(Int(size)).map { UInt8(bitPattern: $0) })
            let status = withUnsafeMutablePointer(to: &token) { llama_decode(context, llama_batch_get_one($0, 1)) }
            try cancellation.check()
            guard status == 0 else { throw OnDeviceRuntimeError.decodingFailed }
        }
        throw OnDeviceRuntimeError.tokenLimit
    }
}

private final class InferenceCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let deadline: TimeInterval
    init(timeout: TimeInterval) { deadline = ProcessInfo.processInfo.systemUptime + timeout }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var shouldStop: Bool {
        lock.lock(); let value = cancelled; lock.unlock()
        #if os(iOS)
        if ProcessInfo.processInfo.thermalState == .critical || ProcessInfo.processInfo.thermalState == .serious { return true }
        #endif
        return value || ProcessInfo.processInfo.systemUptime >= deadline
    }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
        #if os(iOS)
        if ProcessInfo.processInfo.thermalState == .critical || ProcessInfo.processInfo.thermalState == .serious { throw OnDeviceRuntimeError.resourcePressure }
        #endif
        if ProcessInfo.processInfo.systemUptime >= deadline { throw OnDeviceRuntimeError.timedOut }
    }
}
