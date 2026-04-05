// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VigilantEar",
    platforms: [.iOS(.v18)],
    products: [
        .executable(name: "VigilantEar", targets: ["VigilantEar"])
    ],
    dependencies: [
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "10.10.0")  // latest stable
    ],
    targets: [
        .executableTarget(
            name: "VigilantEar",
            path: "Sources",
            sources: ["App", "Core", "Features", "Models"],
            linkerSettings: [
                .unsafeFlags([
                    "-sectcreate", "__TEXT", "__info_plist", "Sources/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "VigilantEarTests",
            dependencies: ["VigilantEar"]
        )
    ]
)
