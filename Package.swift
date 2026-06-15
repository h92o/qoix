// swift-tools-version: 5.9
import PackageDescription

// R4Viz — a native macOS/iOS port of the Win32 "R4" visualization project.
//
// The reusable rendering + scene engine lives in the `R4VizKit` library so it
// can be shared verbatim between the macOS and iOS app targets (see project.yml,
// built with XcodeGen) and exercised from unit tests under SwiftPM.
let package = Package(
    name: "R4Viz",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(name: "R4VizKit", targets: ["R4VizKit"])
    ],
    targets: [
        .target(name: "R4VizKit"),
        .testTarget(
            name: "R4VizKitTests",
            dependencies: ["R4VizKit"]
        )
    ]
)
