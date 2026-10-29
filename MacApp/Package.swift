// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MorseEye",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MorseEye",
            path: "Sources/MorseEye",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
