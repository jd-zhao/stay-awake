// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StayAwake",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "StayAwake", targets: ["StayAwake"])],
    targets: [.executableTarget(name: "StayAwake")]
)
