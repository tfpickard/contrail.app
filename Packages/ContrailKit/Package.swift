// swift-tools-version:6.0
import PackageDescription

// NOTE: targets are added to this manifest as each module is completed, matching the
// plan's stated build order (ContrailCore -> ContrailGeo -> ContrailData -> ...). A
// target only appears here once it has real content and passing tests — an empty
// target is a build error in SwiftPM, and a placeholder file would be exactly the
// kind of stub the spec's quality bar rules out.

let package = Package(
    name: "ContrailKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),   // enables `swift test` on the build host with no simulator
    ],
    products: [
        .library(name: "ContrailCore", targets: ["ContrailCore"]),
        .library(name: "ContrailGeo", targets: ["ContrailGeo"]),
        .library(name: "ContrailSensors", targets: ["ContrailSensors"]),
        .library(name: "ContrailEstimator", targets: ["ContrailEstimator"]),
        .library(name: "ContrailLog", targets: ["ContrailLog"]),
    ],
    targets: [
        // MARK: - Libraries (Foundation only — no UIKit/SwiftUI, no Apple sensor
        // frameworks. This is what keeps the estimator testable on macOS.)

        .target(name: "ContrailCore"),

        .target(
            name: "ContrailGeo",
            dependencies: ["ContrailCore"]
        ),

        .target(
            name: "ContrailSensors",
            dependencies: ["ContrailCore", "ContrailGeo"]
        ),

        .target(
            name: "ContrailEstimator",
            dependencies: ["ContrailCore", "ContrailGeo", "ContrailSensors"]
        ),

        .target(
            name: "ContrailLog",
            dependencies: ["ContrailCore"]
        ),

        // MARK: - Tests

        .testTarget(name: "ContrailCoreTests", dependencies: ["ContrailCore"]),
        .testTarget(name: "ContrailGeoTests", dependencies: ["ContrailGeo"]),
        .testTarget(name: "ContrailSensorsTests", dependencies: ["ContrailSensors", "ContrailGeo"]),
        .testTarget(
            name: "ContrailEstimatorTests",
            dependencies: ["ContrailEstimator", "ContrailSensors", "ContrailGeo", "ContrailCore"]
        ),
        .testTarget(
            name: "ContrailLogTests",
            dependencies: ["ContrailLog", "ContrailCore", "ContrailGeo", "ContrailSensors", "ContrailEstimator"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
