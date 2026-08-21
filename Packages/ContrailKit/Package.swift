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
        .library(name: "ContrailData", targets: ["ContrailData"]),
        .library(name: "ContrailStatistics", targets: ["ContrailStatistics"]),
        .library(name: "ContrailTurbulence", targets: ["ContrailTurbulence"]),
        .library(name: "ContrailMap", targets: ["ContrailMap"]),
        .library(name: "ContrailPhoto", targets: ["ContrailPhoto"]),
        .library(name: "ContrailForecast", targets: ["ContrailForecast"]),
        .executable(name: "contrail-prep", targets: ["ContrailPrep"]),
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
            dependencies: ["ContrailCore", "ContrailGeo", "ContrailSensors", "ContrailTurbulence"]
        ),

        .target(
            name: "ContrailLog",
            dependencies: ["ContrailCore"]
        ),

        .target(
            name: "ContrailData",
            dependencies: ["ContrailCore", "ContrailGeo"]
        ),

        .target(name: "ContrailStatistics"),

        .target(
            name: "ContrailTurbulence",
            dependencies: ["ContrailCore", "ContrailSensors"]
        ),

        .target(name: "ContrailMap"),

        .target(
            name: "ContrailPhoto",
            dependencies: ["ContrailCore", "ContrailData"]
        ),

        .target(
            name: "ContrailForecast",
            dependencies: ["ContrailCore", "ContrailGeo"]
        ),

        // MARK: - Dataset compiler (macOS CLI only; not shipped in the app)

        .executableTarget(
            name: "ContrailPrep",
            dependencies: ["ContrailCore", "ContrailData"]
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
        .testTarget(
            name: "ContrailDataTests",
            dependencies: ["ContrailData", "ContrailCore", "ContrailGeo"]
        ),
        .testTarget(
            name: "ContrailPrepTests",
            dependencies: ["ContrailPrep", "ContrailData", "ContrailCore"]
        ),
        .testTarget(
            name: "ContrailStatisticsTests",
            dependencies: ["ContrailStatistics"]
        ),
        .testTarget(
            name: "ContrailTurbulenceTests",
            dependencies: ["ContrailTurbulence", "ContrailSensors", "ContrailCore"]
        ),
        .testTarget(
            name: "ContrailMapTests",
            dependencies: ["ContrailMap"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ContrailPhotoTests",
            dependencies: ["ContrailPhoto", "ContrailCore", "ContrailData"]
        ),
        .testTarget(
            name: "ContrailForecastTests",
            dependencies: ["ContrailForecast", "ContrailCore", "ContrailGeo"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
