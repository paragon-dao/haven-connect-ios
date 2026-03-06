// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HavenConnect",
    platforms: [.iOS(.v16)],
    targets: [
        .executableTarget(
            name: "HavenConnect",
            path: "HavenConnect"
        ),
        .testTarget(
            name: "HavenConnectTests",
            dependencies: ["HavenConnect"],
            path: "Tests"
        ),
    ]
)
