// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GridFixCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "GridFixCore", targets: ["GridFixCore"]),
    ],
    targets: [
        .target(
            name: "GridFixCore",
            // Declaring resources is what makes Bundle.module exist. WMM.COF
            // drops into this folder and is picked up with no code change.
            resources: [.process("Resources")],
            linkerSettings: [
                // zlib for ZIP DEFLATE inflate (Android ZipOutputStream backups).
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "GridFixCoreTests",
            dependencies: ["GridFixCore"],
            // .process flattens the folder into the bundle root, so dropping
            // WMM2025_TestValues.txt in beside golden.json needs no edit here.
            resources: [.process("Resources")]
        ),
    ]
)
