// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotFluid",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotFluid", targets: ["NotFluid"]),
        .executable(name: "PasteTest", targets: ["PasteTest"]),
        .executable(name: "BoostBenchmark", targets: ["BoostBenchmark"]),
        .library(name: "NotFluidSupport", targets: ["NotFluidSupport"])
    ],
    targets: [
        .target(
            name: "NotFluidSupport",
            path: "Sources/NotFluidSupport"
        ),
        .executableTarget(
            name: "NotFluid",
            dependencies: ["NotFluidSupport"],
            path: "Sources/NotFluid",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Speech"),
                .linkedFramework("WebKit")
            ]
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
            dependencies: ["NotFluidSupport"],
            path: "Sources/BoostBenchmark"
        )
    ]
)
