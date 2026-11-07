// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JianliCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "JianliCore", targets: ["JianliCore"])
    ],
    targets: [
        .target(name: "JianliCore"),
        .testTarget(name: "JianliCoreTests", dependencies: ["JianliCore"])
    ]
)
