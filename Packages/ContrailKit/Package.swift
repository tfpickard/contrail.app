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
        .library(name: "ContrailIdentity", targets: ["ContrailIdentity"]),
        .library(name: "ContrailIFE", targets: ["ContrailIFE"]),
        .library(name: "ContrailDiscovery", targets: ["ContrailDiscovery"]),
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

        // Phase 2 -- Identity: profiles (freeform + derived-from-history) and group
        // flight records. Depends on ContrailLog because a "generated" profile is
        // computed from the same FlightManifest/LogRecord types the logger already
        // writes, and a group flight record is literally a bundle of those from
        // multiple participants' phones.
        .target(
            name: "ContrailIdentity",
            dependencies: ["ContrailCore", "ContrailLog"]
        ),

        // Phase 3b -- Aircraft data endpoint: a pluggable prober for in-flight-
        // entertainment moving-map JSON endpoints. Depends only on ContrailCore
        // (for OutsideAirData/Channel) -- no networking library, URLSession is
        // injected by the App layer, same pattern as ContrailForecast.
        .target(
            name: "ContrailIFE",
            dependencies: ["ContrailCore"]
        ),

        // Phase 3a -- Passenger discovery. Foundation-only, transport-agnostic, and
        // deliberately has no dependency on ContrailCore or anything else in this
        // package -- it doesn't need to know a flight, a route, or a Channel exists.
        // Real CoreBluetooth/MultipeerConnectivity conformers of the transport
        // protocols here live in the App layer (which does need those frameworks),
        // same split as ContrailSensors/LiveSensorSource.
        .target(name: "ContrailDiscovery"),

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
        .testTarget(
            name: "ContrailIdentityTests",
            dependencies: ["ContrailIdentity", "ContrailCore", "ContrailLog"]
        ),
        .testTarget(
            name: "ContrailIFETests",
            dependencies: ["ContrailIFE", "ContrailCore"]
        ),
        .testTarget(
            name: "ContrailDiscoveryTests",
            dependencies: ["ContrailDiscovery"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
