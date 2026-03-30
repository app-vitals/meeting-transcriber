// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingTranscriberApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MeetingTranscriberApp",
            path: "Sources/MeetingTranscriberApp",
            linkerSettings: [
                // Embed Info.plist so macOS reads LSUIElement and bundle metadata
                // from the binary even without a .app bundle wrapper.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/MeetingTranscriberApp/Info.plist",

                ]),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
