// swift-tools-version: 5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "word2text",
    targets: [
        .executableTarget(
            name: "word2text",
            path: "word2text",
            exclude: [
                // File not needed for Linux build (so far...)
                "Info.plist"    
            ]
        )
    ]
)
