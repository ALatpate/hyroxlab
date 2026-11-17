// swift-tools-version:5.9
import PackageDescription

// LumaUI: every Luma screen, the design system and the chart kit. It depends only on LumaCore and
// talks to the strap, the database and the system through the small protocols in LumaEnv.swift, so
// the whole interface builds and runs (with demo data) without the app target. LumaKit is the slice
// the widget extension links: tokens, primitives, the glance snapshot and the widget / Live Activity
// views.
let package = Package(
    name: "LumaUI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LumaUI", targets: ["LumaUI"]),
        .library(name: "LumaKit", targets: ["LumaKit"]),
    ],
    dependencies: [.package(path: "../LumaCore")],
    targets: [
        // The fonts are Barlow Condensed (SIL Open Font License 1.1; the licence sits beside them).
        .target(name: "LumaKit", resources: [.process("Fonts")]),
        .target(name: "LumaUI", dependencies: ["LumaKit", .product(name: "LumaCore", package: "LumaCore")]),
    ]
)
