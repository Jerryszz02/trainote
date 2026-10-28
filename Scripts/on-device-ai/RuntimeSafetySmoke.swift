import Foundation

@main struct RuntimeSafetySmoke {
    static func main() async throws {
        let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let missing = BundledLlamaRuntime(modelURL: URL(fileURLWithPath: "/missing/trainote-test.gguf"))
        do { _ = try await missing.generate(prompt: "x", grammar: "root ::= \"{}\"", maximumTokens: 1); fatalError("missing model accepted") }
        catch OnDeviceRuntimeError.modelUnavailable {}
        let runtime = BundledLlamaRuntime(modelURL: modelURL)
        do { _ = try await runtime.generate(prompt: "x", grammar: "root ::= \"{}\"", maximumTokens: 257); fatalError("token limit accepted") }
        catch OnDeviceRuntimeError.inputTooLong {}
        do { _ = try await runtime.generate(prompt: String(repeating: "x", count: 24_001), grammar: "root ::= \"{}\"", maximumTokens: 1); fatalError("oversized input accepted") }
        catch OnDeviceRuntimeError.inputTooLong {}
        let task = Task { try await runtime.generate(prompt: "test", grammar: "root ::= \"{}\"", maximumTokens: 256) }
        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        do { _ = try await task.value; fatalError("cancelled generation returned output") }
        catch is CancellationError {}
        let timed = BundledLlamaRuntime(modelURL: modelURL, timeout: 0.01)
        do { _ = try await timed.generate(prompt: "test", grammar: "root ::= \"{}\"", maximumTokens: 256); fatalError("timeout returned output") }
        catch OnDeviceRuntimeError.timedOut {}
        // A cancelled invocation must release its model/context and allow a later invocation.
        let output = try await runtime.generate(prompt: "Return the JSON object {} only. /no_think", grammar: "root ::= \"{}\"", maximumTokens: 256)
        guard output == "{}" else { fatalError("runtime failed after cancellation") }
        print("PASS: missing model, token cap, byte cap, cancellation, timeout, release and next generation")
    }
}
