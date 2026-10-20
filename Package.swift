// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SekaiKit",
  platforms: [.iOS(.v26), .macOS(.v26), .tvOS(.v26), .visionOS(.v26)],
  products: [.library(name: "SekaiKit", targets: ["SekaiKit"])],
  targets: [
    .target(name: "SekaiKit", resources: [.process("Resources")]),
    .testTarget(name: "SekaiKitTests", dependencies: ["SekaiKit"]),
  ],
  swiftLanguageModes: [.v6]
)
