// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "word2text",
    dependencies: [
        .package(url: "https://github.com/smittytone/clicore", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "word2text",
            dependencies: [
                .product(name: "Clicore", package: "clicore"),
            ],
            path: "word2text",
            // macOS only:
            //linkerSettings: [
            //    .unsafeFlags(
            //        ["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "word2text/Info.plist"]
            //    )
            //],
            // Linux/macOS:
            exclude: [
                // File not needed for Linux build (so far...)
                "Info.plist"
            ]
        )
    ]
)
