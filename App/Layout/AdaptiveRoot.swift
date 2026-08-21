import SwiftUI

/// §1's non-negotiable layout rule: "no view may branch on device type." This is the
/// **only** place that's allowed to branch, and it branches on `horizontalSizeClass`
/// (a trait, not a device idiom) — the same three child views compose differently on
/// either side, never a separate iPad-only or iPhone-only view.
///
/// Composes six surfaces: pre-flight, map, metrics, statistics, turbulence, fix
/// quality. Same child views on both branches — only the container differs.
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
            NavigationStack { MapSurface() }
                .tabItem { Label("Map", systemImage: "map") }
            NavigationStack { MetricsSurface() }
                .tabItem { Label("Metrics", systemImage: "gauge") }
            NavigationStack { StatisticsSurface() }
                .tabItem { Label("Stats", systemImage: "chart.bar") }
            NavigationStack { TurbulenceSurface() }
                .tabItem { Label("Turbulence", systemImage: "waveform.path.ecg") }
            NavigationStack { FixQualitySurface() }
                .tabItem { Label("Fix", systemImage: "location") }
        }
    }
}

private struct RegularDashboard: View {
    private enum Surface: String, CaseIterable, Identifiable {
        case flight = "Flight"
        case map = "Map"
        case metrics = "Metrics"
        case statistics = "Statistics"
        case turbulence = "Turbulence"
        case fix = "Fix Quality"
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
            case .map: MapSurface()
            case .metrics: MetricsSurface()
            case .statistics: StatisticsSurface()
            case .turbulence: TurbulenceSurface()
            case .fix: FixQualitySurface()
            case nil: ContentUnavailableView("Select a Surface", systemImage: "sidebar.left")
            }
        }
    }
}
