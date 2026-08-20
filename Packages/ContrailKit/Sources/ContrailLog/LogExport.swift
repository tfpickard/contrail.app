import Foundation
import ContrailCore

/// §6: "CSV is an export transform, not a storage format... provide CSV and JSON
/// export via the share sheet." Both read from already-decoded `LogRecord`s — NDJSON
/// remains the single source of truth on disk; these are one-way views onto it.
public enum LogExport {
    private static let csvColumns = [
        "timestamp", "phase", "latitude", "longitude", "confidenceRadiusM",
        "altitudeGpsM", "groundspeedMS", "trueCourseDeg", "verticalSpeedMS",
        "cabinPressureKPa", "cabinPressureAltitudeM", "pressurizationRateMS",
        "crossTrackErrorM", "alongTrackFlownM", "alongTrackRemainingM", "fractionalProgress",
    ]

    /// A flat CSV with one row per sample record (event/marker records are skipped —
    /// they don't share this row shape). Every cell is either a formatted number or
    /// empty, never a sentinel — an `.unavailable` channel produces an empty cell,
    /// matching the same "absence, not a lie" principle `Channel` itself follows.
    public static func csv(records: [LogRecord]) -> String {
        var lines = [csvColumns.joined(separator: ",")]
        for record in records where record.kind == .sample {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let cells: [String] = [
                iso.string(from: record.t),
                record.phase.value?.rawValue ?? "",
                record.position.fused.value.map { format($0.latitude) } ?? "",
                record.position.fused.value.map { format($0.longitude) } ?? "",
                record.position.confidenceRadius.value.map(format) ?? "",
                record.position.altitudeGPS.value.map(format) ?? "",
                record.motion.groundspeed.value.map(format) ?? "",
                record.motion.trueCourse.value.map(format) ?? "",
                record.motion.verticalSpeed.value.map(format) ?? "",
                record.cabin.pressure.value.map(format) ?? "",
                record.cabin.pressureAltitude.value.map(format) ?? "",
                record.cabin.pressurizationRate.value.map(format) ?? "",
                record.route.crossTrackError.value.map(format) ?? "",
                record.route.alongTrackFlown.value.map(format) ?? "",
                record.route.alongTrackRemaining.value.map(format) ?? "",
                record.route.fractionalProgress.value.map(format) ?? "",
            ]
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// The same records as a pretty-printed JSON array — human-readable, unlike the
    /// compact NDJSON storage format, at the cost of losing the append-only property
    /// (this is a one-shot export, not something written incrementally in flight).
    public static func jsonArray(records: [LogRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
