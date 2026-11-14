// swift-tools-version:5.9
import PackageDescription

// HYROXCore: platform-free logic for HYROX Lab — the race model, split recorder, race and run
// analytics, readiness, benchmarks, race readiness, training load, plans and nutrition targets.
// Foundation only; no UIKit, no CoreLocation, no database. Builds and tests on Linux so CI can
// prove the maths in minutes without an Xcode runner.
let package = Package(
    name: "HYROXCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "HYROXCore", targets: ["HYROXCore"])],
    targets: [
        .target(name: "HYROXCore"),
        .testTarget(name: "HYROXCoreTests", dependencies: ["HYROXCore"]),
    ]
)
