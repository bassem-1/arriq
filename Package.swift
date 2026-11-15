// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "arriq",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "arriq", targets: ["arriq"])],
    targets: [
        .target(
            name: "ArriqKit",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(name: "arriq", dependencies: ["ArriqKit"]),
        .testTarget(name: "ArriqKitTests", dependencies: ["ArriqKit"]),
    ]
)
