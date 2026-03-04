// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingTranscriberApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MeetingTranscriberApp",
            path: "Sources/MeetingTranscriberApp"
        ),
    ]
)
