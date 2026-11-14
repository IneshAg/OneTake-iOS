// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OneTakeUI",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .library(
            name: "OneTakeUI",
            targets: ["OneTakeUI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OneTakeUI",
            dependencies: [],
            path: "Sources/OneTakeUI"
        )
    ]
)
