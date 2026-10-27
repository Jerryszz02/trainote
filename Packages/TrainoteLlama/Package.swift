// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TrainoteLlama",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "TrainoteLlama", targets: ["llama"])],
    targets: [.binaryTarget(name: "llama", path: "Artifacts/llama.xcframework")]
)
