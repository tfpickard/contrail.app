import Foundation

/// §6: "newline-delimited JSON, append-only... line-oriented and append-safe so that
/// a crash, a thermal shutdown, or a dead battery mid-flight costs at most the last
/// line, not the flight." One writer per open flight log, meant for single-writer
/// use from whichever queue is producing `EstimatorOutput`s — like `Estimator`.
///
/// `@unchecked Sendable`: this is the "construct once, hand off exclusive ownership
/// once, then never touch it again" pattern, not genuine concurrent access. A caller
/// typically constructs this on one isolation domain (e.g. `@MainActor`, to resolve
/// the file URL) and immediately hands it to another (e.g. an actor that owns its
/// full write lifecycle) — that one-time transfer is safe; two domains writing to it
/// *concurrently* would not be, and nothing about this type enforces that beyond
/// convention. Don't retain a reference on both sides of a handoff.
public final class NDJSONLogWriter: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder

    public init(fileURL: URL) throws {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: fileURL)
        try fileHandle.seekToEnd()
        encoder = JSONEncoder()
    }

    /// Appends one record as a single JSON line. Does not itself force a sync to
    /// disk — call `flush()` at whatever batching cadence the caller chooses (the
    /// plan calls for "batched fsync").
    public func append(_ record: LogRecord) throws {
        var data = try encoder.encode(record)
        data.append(0x0A) // "\n"
        try fileHandle.write(contentsOf: data)
    }

    /// Forces pending writes to durable storage. This is the actual crash-safety
    /// boundary — anything appended since the last `flush()` is what a crash could
    /// lose; everything before it is safe on disk.
    public func flush() throws {
        try fileHandle.synchronize()
    }

    public func close() throws {
        try fileHandle.close()
    }
}

/// The reading half of §6's append-only log. A truncated final line — the one a
/// crash mid-write would leave behind — is silently skipped rather than failing the
/// whole read; every line before it decodes normally. A truncated *non-final* line
/// indicates real corruption and is not tolerated.
public enum NDJSONLogReader {
    public static func readAll(from fileURL: URL) throws -> [LogRecord] {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try readAll(fromContents: text)
    }

    public static func readAll(fromContents text: String) throws -> [LogRecord] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let decoder = JSONDecoder()
        var records: [LogRecord] = []
        for (index, line) in lines.enumerated() {
            do {
                records.append(try decoder.decode(LogRecord.self, from: Data(line.utf8)))
            } catch {
                let isLastLine = index == lines.count - 1
                if isLastLine { continue }
                throw error
            }
        }
        return records
    }
}
