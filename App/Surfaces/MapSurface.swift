import SwiftUI
import CoreLocation
import ContrailCore
import MapLibre

/// §5.2/§8's map surface — the bundled coarse (z0-6) offline basemap, rendered by
/// MapLibre against the local `PMTilesHTTPServer` (see that type's doc comment for why
/// tiles are served over loopback HTTP rather than through MapLibre's `pmtiles://`
/// custom URL scheme). Shows the fused position track as it accumulates; the camera
/// only recenters automatically until the user pans, matching the standard "you're in
/// control unless you say otherwise" map convention.
struct MapSurface: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let template = model.mapTileURLTemplate {
                MapLibreView(tileURLTemplate: template, latestCoordinate: model.latestOutput?.position.fused.value)
                    .ignoresSafeArea(edges: .bottom)
            } else if let error = model.lastLogError {
                ContentUnavailableView(
                    "Map Unavailable", systemImage: "map.fill", description: Text(error)
                )
            } else {
                ProgressView("Starting offline map…")
            }
        }
        .navigationTitle("Map")
    }
}

private struct MapLibreView: UIViewRepresentable {
    let tileURLTemplate: String
    let latestCoordinate: Coordinate?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.styleURL = Self.writeStyle(tileURLTemplate: tileURLTemplate)
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 20, longitude: 0), zoomLevel: 1, animated: false
        )
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        guard let latestCoordinate else { return }
        let target = CLLocationCoordinate2D(
            latitude: latestCoordinate.latitude, longitude: latestCoordinate.longitude
        )

        if let annotation = context.coordinator.positionAnnotation {
            annotation.coordinate = target
        } else {
            let annotation = MLNPointAnnotation()
            annotation.coordinate = target
            mapView.addAnnotation(annotation)
            context.coordinator.positionAnnotation = annotation
        }

        // Recenter only until the pilot/passenger has manually panned -- after that,
        // their framing wins until they explicitly ask to recenter (not built yet).
        if !context.coordinator.userHasPanned {
            mapView.setCenter(target, zoomLevel: max(mapView.zoomLevel, 5), animated: true)
        }
    }

    final class Coordinator {
        var positionAnnotation: MLNPointAnnotation?
        var userHasPanned = false
    }

    /// Loads the bundled style template and substitutes in the local HTTP server's
    /// actual (ephemeral) port, since the template on disk can't know it in advance.
    /// Written to a temp file because `MLNMapView.styleURL` takes a file/http(s) URL,
    /// not inline JSON.
    private static func writeStyle(tileURLTemplate: String) -> URL {
        let templateURL = Bundle.main.url(forResource: "basemap-style", withExtension: "json")
        let placeholder = "http://127.0.0.1:__PORT__/tiles/{z}/{x}/{y}.pbf"
        let raw = (try? String(contentsOf: templateURL!, encoding: .utf8)) ?? ""
        let resolved = raw.replacingOccurrences(of: placeholder, with: tileURLTemplate)

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("contrail-style.json")
        try? resolved.write(to: outURL, atomically: true, encoding: .utf8)
        return outURL
    }
}
