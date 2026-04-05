// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VigilantEar",
    platforms: [.iOS(.v18)],
    products: [
        .executable(name: "VigilantEar", targets: ["VigilantEar"])
    ],
    dependencies: [
        // .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "10.10.0"),  // temporarily disabled
    ],
targets: [
    .executableTarget(
        name: "VigilantEar",
        dependencies: [
            .product(name: "GoogleMaps", package: "ios-maps-sdk")
        ],
        path: "Sources",                    // ← This tells SPM to look here
        sources: ["App", "Core", "Features", "Models"],  // explicitly include your folders
        resources: [.process("Info.plist")] // optional but good practice
    ),
    .testTarget(
        name: "VigilantEarTests",
        dependencies: ["VigilantEar"]
    )
]
)
