// swift-tools-version: 5.10

import PackageDescription

/*

 This package definition was originally written to support CLI building of the word2text utility under Linux.
 This is because macOS users are expected to build using Xcode and the Xcode project files in this repository,
 and Linux users can't do this because (surprise, surprise) there's no Xcdoe for Linux.

 It has been updated to support the use of core files minus the host CLI code within third-party apps, currently
 macOS only. This is experimental.
 */

#if os(Linux)
let package = Package(
    name: "word2text",
    dependencies: [
        .package(
            url: "https://github.com/smittytone/clicore",
            branch: "main"
        ),
    ],
    targets: [
        .executableTarget(
            name: "word2text",
            dependencies: [
                .product(
                    name: "Clicore",
                    package: "clicore"
                ),
            ],
            path: "word2text",
            exclude: [
                // File not needed for Linux build (so far...)
                "Info.plist",
                "logging_lib.swift"
            ]
        )
    ]
)
#else
let package = Package(
    name: "word2text-lib",
    products: [
        .library(
            name: "Word2text",
            targets: ["Word2text"])
    ],
    targets: [
        .target(
            name: "Word2text",
            path: "word2text",
            sources: [
                // Files not needed for macOS lib usage
                "word.swift",
                "entities.swift",
                "logging_lib.swift"
            ]
        )
    ]
)
#endif
