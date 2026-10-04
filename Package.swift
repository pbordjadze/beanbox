// swift-tools-version: 6.2
import PackageDescription

// BeanCore is the portable, dependency-free heart of the app: colour measurement from photo
// pixels, the sheet-per-flavour assignment, and the look-alike bean sorter. It builds on Apple
// platforms and on Linux, so all of it is tested headlessly (see tools/swift.sh).
let package = Package(
    name: "BeanCore",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "BeanCore", targets: ["BeanCore"]),
        .executable(name: "beans", targets: ["beans"]),
    ],
    targets: [
        .target(
            name: "BeanCore",
            swiftSettings: [
                // The sorter walks every pixel of a photo; it must stay fast in Debug app builds too.
                .unsafeFlags(["-O"], .when(configuration: .debug)),
                .unsafeFlags(["-Ounchecked", "-wmo"], .when(configuration: .release)),
            ]
        ),
        .executableTarget(name: "beans", dependencies: ["BeanCore"]),
        .testTarget(
            name: "BeanCoreTests",
            dependencies: ["BeanCore"],
            // The tests render megapixel synthetic photos; unoptimised that takes minutes.
            swiftSettings: [.unsafeFlags(["-O"])]
        ),
    ],
    swiftLanguageModes: [.v6]
)
