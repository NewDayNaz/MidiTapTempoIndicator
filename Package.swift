// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MidiTapTempoIndicator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MidiTapTempoIndicator",
            path: "Sources/MidiTapTempoIndicator",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("CoreMIDI"),
                .linkedFramework("Cocoa"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "MidiTapTempoIndicatorTests",
            dependencies: ["MidiTapTempoIndicator"]
        ),
    ]
)
