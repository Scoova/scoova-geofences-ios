// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScoovaGeofences",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "ScoovaGeofences", targets: ["ScoovaGeofences"]),
    ],
    targets: [
        .target(name: "ScoovaGeofences", path: "Sources/ScoovaGeofences"),
    ]
)
