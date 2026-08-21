import Foundation
import ContrailData

/// §5.6/§5.1: loads the bundled, `ContrailPrep`-compiled airport and populated-place
/// datasets from the app bundle. See `THIRD-PARTY-DATA.md` at the repo root — the
/// GeoNames dataset is CC BY 4.0 and its attribution belongs wherever this app
/// surfaces an Acknowledgments screen.
enum BundledDatasets {
    enum LoadError: Error {
        case resourceMissing(String)
    }

    static func loadAirportIndex() throws -> AirportIndex {
        try AirportIndex(data: Data(contentsOf: assetURL(named: "airports", extension: "bin")))
    }

    static func loadPlaceIndex() throws -> PlaceIndex {
        try PlaceIndex(data: Data(contentsOf: assetURL(named: "places", extension: "bin")))
    }

    static func basemapURL() throws -> URL {
        try assetURL(named: "basemap-z0-6", extension: "pmtiles")
    }

    /// No `subdirectory:` argument — XcodeGen's `resources:` key (a per-target
    /// grouping concept) doesn't translate into an actual folder in the compiled app
    /// bundle here; individual resource files land flat at the bundle root
    /// regardless of their source-tree grouping in Xcode. Confirmed against the
    /// actual built `.app` on this session's build host, not assumed.
    static func assetURL(named name: String, extension ext: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw LoadError.resourceMissing("\(name).\(ext)")
        }
        return url
    }
}
