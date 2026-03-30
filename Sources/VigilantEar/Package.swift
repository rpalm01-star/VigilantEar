// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VigilantEar",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        // Main library product (Xcode will use this when you open the package)
        .library(
            name: "VigilantEar",
            targets: ["VigilantEar"]
        ),
    ],
    dependencies: [
        // Add Google Maps or any future SPM dependencies here later
        // .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "8.0.0"),
    ],
    targets: [
        .target(
            name: "VigilantEar",
            dependencies: [],
            resources: [.process("Resources")]  // for future Info.plist, images, etc.
        ),
        .testTarget(
            name: "VigilantEarTests",
            dependencies: ["VigilantEar"]
        ),
    ]
)
