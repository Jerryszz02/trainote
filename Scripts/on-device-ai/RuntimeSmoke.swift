import Foundation

@main struct RuntimeSmoke {
    static func main() async {
        do {
            let args = CommandLine.arguments
            guard args.count == 4 else { fatalError("model prompt-file grammar-file") }
            let runtime = BundledLlamaRuntime(modelURL: URL(fileURLWithPath: args[1]))
            let start = ProcessInfo.processInfo.systemUptime
            let output = try await runtime.generate(prompt: String(contentsOfFile: args[2]), grammar: String(contentsOfFile: args[3]), maximumTokens: 256)
            let data = try JSONSerialization.data(withJSONObject: ["output": output, "seconds": ProcessInfo.processInfo.systemUptime-start], options: [.sortedKeys])
            print(String(decoding:data,as:UTF8.self))
        } catch {
            fputs("RuntimeSmoke: \(error)\n", stderr)
            exit(1)
        }
    }
}
