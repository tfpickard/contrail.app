import SwiftUI

/// §1's non-negotiable layout rule: "no view may branch on device type." This is the
/// **only** place that's allowed to branch, and it branches on `horizontalSizeClass`
/// (a trait, not a device idiom) — the same five child surfaces compose differently
/// on either side, never a separate iPad-only or iPhone-only view.
///
/// Five top-level surfaces, deliberately: Flight, Instruments, Map, Log, You. iOS
/// folds a sixth-plus tab into a generic system "More" list on compact width, which
/// buried Turbulence, Camera, and Profile -- three of the app's best features --
/// two taps deep behind a screen nobody designed. `InstrumentsSurface` and
/// `ProfileSurface` are hubs, not fewer features: Statistics/Fix Quality/Turbulence
/// live under Instruments as real destinations, and Group Flight/Nearby Passengers
/// live under You, each still a whole, self-contained surface. Camera and Route
/// are one tap from the Flight tab's in-flight view, where they're actually needed.
struct AdaptiveRoot: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            CompactDashboard()
        } else {
            RegularDashboard()
        }
    }
}

private struct CompactDashboard: View {
    var body: some View {
        TabView {
            NavigationStack { PreFlightSurface() }
                .tabItem { Label("Flight", systemImage: "airplane") }
            NavigationStack { InstrumentsSurface() }
                .tabItem { Label("Instruments", systemImage: "gauge.with.dots.needle.67percent") }
            NavigationStack { MapSurface() }
                .tabItem { Label("Map", systemImage: "map") }
            NavigationStack { FlightLogSurface() }
                .tabItem { Label("Log", systemImage: "doc.text") }
            NavigationStack { ProfileSurface() }
                .tabItem { Label("You", systemImage: "person.crop.circle") }
        }
    }
}

private struct RegularDashboard: View {
    private enum Surface: String, CaseIterable, Identifiable {
        case flight = "Flight"
        case instruments = "Instruments"
        case map = "Map"
        case log = "Flight Log"
        case profile = "You"
        var id: String { rawValue }
    }

    @State private var selection: Surface? = .flight

    var body: some View {
        NavigationSplitView {
            List(Surface.allCases, selection: $selection) { surface in
                Text(surface.rawValue).tag(surface)
            }
            .navigationTitle("Contrail")
        } detail: {
            switch selection {
            case .flight: PreFlightSurface()
            case .instruments: InstrumentsSurface()
            case .map: MapSurface()
            case .log: FlightLogSurface()
            case .profile: ProfileSurface()
            case nil: ContentUnavailableView("Select a Surface", systemImage: "sidebar.left")
            }
        }
    }
}
