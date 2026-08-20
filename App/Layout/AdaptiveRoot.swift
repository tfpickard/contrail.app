import SwiftUI

/// §1's non-negotiable layout rule: "no view may branch on device type." This is the
/// **only** place that's allowed to branch, and it branches on `horizontalSizeClass`
/// (a trait, not a device idiom) — the same three child views compose differently on
/// either side, never a separate iPad-only or iPhone-only view.
///
/// The map surface (§5.2/§8) isn't built yet — MapLibre isn't wired in this pass —
/// so this composes the three surfaces that exist today. When the map lands, it
/// takes the primary/detail slot without restructuring this rule.
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
            NavigationStack { MetricsSurface() }
                .tabItem { Label("Metrics", systemImage: "gauge") }
            NavigationStack { FixQualitySurface() }
                .tabItem { Label("Fix", systemImage: "location") }
        }
    }
}

private struct RegularDashboard: View {
    private enum Surface: String, CaseIterable, Identifiable {
        case flight = "Flight"
        case metrics = "Metrics"
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
            case .metrics: MetricsSurface()
            case .fix: FixQualitySurface()
            case nil: ContentUnavailableView("Select a Surface", systemImage: "sidebar.left")
            }
        }
    }
}
