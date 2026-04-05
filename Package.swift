// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VigilantEar",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .executable(
            name: "VigilantEar",
            targets: ["VigilantEar"]
        ),
    ],
    dependencies: [
        // Add Google Maps or any future SPM dependencies here later
        // .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "8.0.0"),
    ],
    targets: [
        .executableTarget(   // changed from .target → .executableTarget (important for an app)
            name: "VigilantEar",
            // resources line removed — Info.plist is now at target root
            resources: []
        ),
        .testTarget(
            name: "VigilantEarTests",
            dependencies: ["VigilantEar"]
        ),
    ])
