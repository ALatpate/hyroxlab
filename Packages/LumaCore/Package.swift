// swift-tools-version:5.9
import PackageDescription

// LumaCore: platform-free logic for Luma: the data model, health / sleep / load / fitness analytics,
// insights, the HYROX race model and analytics, run analytics, nutrition, the schedule, and the coach
// wire format and tools. Foundation only; no UIKit, no CoreLocation, no database. Builds and tests on
// Linux so CI can prove the maths in minutes without an Xcode runner.
let package = Package(
    name: "LumaCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LumaCore", targets: ["LumaCore"])],
    targets: [
        .target(name: "LumaCore"),
        .testTarget(name: "LumaCoreTests", dependencies: ["LumaCore"]),
    ]
)
