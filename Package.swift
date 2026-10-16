// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrcaWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OrcaWhisper",
            targets: ["OrcaWhisper"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OrcaWhisper",
            path: "OrcaWhisper/Sources"
        )
    ]
)
