// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VigilantEar",
    platforms: [.iOS(.v18)],
    products: [
        .executable(name: "VigilantEar", targets: ["VigilantEar"])
    ],
    dependencies: [
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "10.10.0")
    ],
    targets: [
        .executableTarget(
            name: "VigilantEar",
            dependencies: [
                .product(name: "GoogleMaps", package: "ios-maps-sdk")
            ]
        ),
        .testTarget(
            name: "VigilantEarTests",
            dependencies: ["VigilantEar"]
        )
    ]
)
