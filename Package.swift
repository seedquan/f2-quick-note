// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "F2QuickNote",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "F2QuickNoteCore",
            path: "Sources/F2QuickNoteCore"
        ),
        .executableTarget(
            name: "F2QuickNote",
            dependencies: ["F2QuickNoteCore"],
            path: "Sources/F2QuickNote"
        ),
        .testTarget(
            name: "F2QuickNoteCoreTests",
            dependencies: ["F2QuickNoteCore"],
            path: "Tests/F2QuickNoteCoreTests"
        ),
    ]
)
