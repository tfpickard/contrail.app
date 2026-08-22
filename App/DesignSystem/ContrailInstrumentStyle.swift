import SwiftUI
import ContrailCore

/// The instrument design system every live-data surface draws from. Grounded in
/// real glass-cockpit convention rather than a generic dashboard look: four signal
/// colors used *semantically*, never decoratively, and a hard split between
/// monospaced digits (anything measured or derived -- a sensor or computation
/// produced this number) and rounded type (anything a person wrote or a label
/// naming what the number means). That split is itself the rule: if you're ever
/// tempted to set a measured value in `.rounded`, that's a sign the value doesn't
/// belong here.
enum ContrailSignal {
    /// Live/nav -- a fresh GNSS fix, an on-course reading, "this is current."
    static let cyan = Color(red: 0.184, green: 0.835, blue: 0.835)
    /// Caution -- dead reckoning, a marginal divert, a stale fix.
    static let amber = Color(red: 1.0, green: 0.690, blue: 0.125)
    /// Nominal/go -- smooth air, a reachable divert, a verified asset.
    static let green = Color(red: 0.204, green: 0.827, blue: 0.600)
    /// Warning/severe -- rough air, an unreachable divert, a failure.
    static let red = Color(red: 1.0, green: 0.271, blue: 0.227)

    static func forTurbulence(_ category: TurbulenceCategory) -> Color {
        switch category {
        case .smooth: return green
        case .light: return cyan
        case .moderate: return amber
        case .severe: return red
        }
    }
}

extension Font {
    /// Tabular monospaced digits for measured/derived readouts -- fixed digit
    /// width, so a tile's layout doesn't jump as the value changes underneath it.
    static func instrumentValue(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Small-caps-style labels for instrument tiles -- the aviation abbreviation
    /// convention (GS, VS, ALT), not a full English word, when the tile itself
    /// carries a unit suffix to disambiguate.
    static func instrumentLabel(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

/// One glanceable readout: a small-caps label, a big monospaced value, a unit, and
/// a signal color -- the Garmin-G1000-style data tile every `InstrumentsSurface`
/// gauge is built from. `value == nil` renders an em dash in the secondary color,
/// never a fake zero (the same "absence, not a lie" rule `Channel` follows all the
/// way up to the pixel).
struct InstrumentTile: View {
    let label: String
    let value: String?
    let unit: String?
    var signal: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.instrumentLabel())
                .foregroundStyle(.secondary)
                .tracking(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—")
                    .font(.instrumentValue(28))
                    .foregroundStyle(value == nil ? .secondary : signal)
                    .contentTransition(.numericText())
                if let unit, value != nil {
                    Text(unit)
                        .font(.instrumentLabel(12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(signal.opacity(value == nil ? 0 : 0.35), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// A tappable feature-entry card -- for hub screens ("You") linking out to a
/// self-contained surface (Group Flight, Nearby Passengers), styled as a real
/// destination rather than a plain disclosure row. No chevron of its own: every
/// use site is the label of a `NavigationLink` inside a `List`, which already
/// draws its own disclosure indicator -- adding a second one here read as a
/// doubled-up arrow.
struct FeatureCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var signal: Color = ContrailSignal.cyan

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(signal)
                .frame(width: 44, height: 44)
                .background(signal.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
