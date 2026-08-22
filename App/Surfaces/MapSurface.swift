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
    @StateObject private var mapController = MapViewController()

    var body: some View {
        Group {
            if let template = model.mapTileURLTemplate {
                ZStack(alignment: .bottomTrailing) {
                    MapLibreView(
                        tileURLTemplate: template,
                        latestCoordinate: model.latestOutput?.position.fused.value,
                        controller: mapController
                    )
                    .ignoresSafeArea(edges: .bottom)

                    // The auto-follow camera stops the instant the pilot/passenger
                    // pans (see Coordinator's own doc comment) -- without this, that
                    // framing is permanent, since nothing else in the view can get
                    // it back. Always shown, not just after a pan: tapping it while
                    // already centered is a harmless no-op, and a button that
                    // appears and disappears is more surprising than one that's
                    // simply always there, like every other maps app's.
                    Button {
                        mapController.recenter(on: model.latestOutput?.position.fused.value)
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(ContrailSignal.cyan, in: Circle())
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    }
                    .padding(20)
                }
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

/// Bridges a SwiftUI button (the recenter control) to the `MLNMapView`/`Coordinator`
/// pair `MapLibreView` owns -- both held weakly, since this controller outlives any
/// particular `UIViewRepresentable` instantiation and must never be what keeps the
/// map view alive.
@MainActor
final class MapViewController: ObservableObject {
    fileprivate weak var mapView: MLNMapView?
    fileprivate weak var coordinator: MapLibreView.Coordinator?

    func recenter(on coordinate: Coordinate?) {
        guard let mapView, let coordinate else { return }
        coordinator?.userHasPanned = false
        coordinator?.isProgrammaticRecenter = true
        let target = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        mapView.setCenter(target, zoomLevel: max(mapView.zoomLevel, 5), animated: true)
    }
}

private struct MapLibreView: UIViewRepresentable {
    let tileURLTemplate: String
    let latestCoordinate: Coordinate?
    let controller: MapViewController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.styleURL = Self.writeStyle(tileURLTemplate: tileURLTemplate)
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.delegate = context.coordinator
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 20, longitude: 0), zoomLevel: 1, animated: false
        )
        controller.mapView = mapView
        controller.coordinator = context.coordinator
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
        // their framing wins until they tap the recenter button. `isProgrammaticRecenter`
        // is what lets `Coordinator` tell "we just moved the camera ourselves" apart
        // from "the user just panned/zoomed" -- both fire the same delegate callback.
        if !context.coordinator.userHasPanned {
            context.coordinator.isProgrammaticRecenter = true
            mapView.setCenter(target, zoomLevel: max(mapView.zoomLevel, 5), animated: true)
        }
    }

    /// `MLNMapViewDelegate` only for `mapView(_:imageFor:)` -- MapLibre's default
    /// annotation is a generic map-pin teardrop, which reads as "a place," not "you,
    /// live, right now." A small solid dot with a bright ring is the same visual
    /// language the rest of the app uses for a live GNSS fix (`ContrailSignal.cyan`),
    /// deliberately not a fake animated blue dot -- see the README's own rejection of
    /// that idea; this is a static marker MapLibreView repositions on every update.
    /// `@MainActor`: MapLibre delivers every delegate callback on the main thread in
    /// practice (it's a UIKit-backed map view), and `dequeueReusableAnnotationImage`
    /// is itself main-actor-isolated in this SDK's bindings -- annotating the whole
    /// coordinator is what lets `imageFor annotation:` call it without a spurious
    /// cross-actor error for a hop that was never actually happening.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var positionAnnotation: MLNPointAnnotation?
        var userHasPanned = false
        /// Set immediately before every recenter call this file makes, cleared once
        /// that move settles -- `regionWillChangeAnimated` fires for *any* camera
        /// move, ours or the user's, and this is what lets it tell them apart: only
        /// a change that arrives with this still `false` gets attributed to the user.
        var isProgrammaticRecenter = false

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            if !isProgrammaticRecenter {
                userHasPanned = true
            }
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            isProgrammaticRecenter = false
        }

        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            let reuseIdentifier = "contrail-position"
            if let existing = mapView.dequeueReusableAnnotationImage(withIdentifier: reuseIdentifier) {
                return existing
            }
            return MLNAnnotationImage(image: Self.positionMarkerImage(), reuseIdentifier: reuseIdentifier)
        }

        private static func positionMarkerImage() -> UIImage {
            let diameter: CGFloat = 22
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
            return renderer.image { _ in
                let ringColor = UIColor(ContrailSignal.cyan)
                let ring = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2))
                UIColor.white.setFill()
                ring.fill()
                ringColor.setStroke()
                ring.lineWidth = 2.5
                ring.stroke()
                let core = UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: diameter - 12, height: diameter - 12))
                ringColor.setFill()
                core.fill()
            }
        }
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
