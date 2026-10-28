// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PushToType",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PushToType", targets: ["PushToType"]),
        .executable(name: "PasteTest", targets: ["PasteTest"]),
        .executable(name: "BoostBenchmark", targets: ["BoostBenchmark"]),
        .library(name: "PushToTypeSupport", targets: ["PushToTypeSupport"])
    ],
    targets: [
        .target(
            name: "PushToTypeSupport",
            path: "Sources/PushToTypeSupport",
            resources: [
                .process("DevLexicon.tsv")
            ]
        ),
        .executableTarget(
            name: "PushToType",
            dependencies: ["PushToTypeSupport"],
            path: "Sources/PushToType",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Speech"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "PushToTypeTests",
            dependencies: ["PushToTypeSupport"],
            path: "Tests/PushToTypeTests"
        ),
        .executableTarget(
            name: "PasteTest",
            path: "Sources/PasteTest",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "BoostBenchmark",
            dependencies: ["PushToTypeSupport"],
            path: "Sources/BoostBenchmark"
        )
    ]
)
