import Foundation

/// One directory entry. `runLength == 0` means this entry points to a *leaf
/// directory* (recurse into it), not a tile; otherwise it covers `runLength`
/// consecutive tile IDs starting at `tileId`, all sharing the same `offset`/`length`
/// (a common optimization: many adjacent tiles at low zoom are byte-identical, e.g.
/// open ocean).
struct PMTilesEntry: Equatable {
    let tileId: UInt64
    var offset: UInt64
    var length: UInt64
    var runLength: UInt64
}

enum PMTilesDirectoryCoding {
    /// Deserializes a directory buffer — five sequential arrays (count, delta-coded
    /// tileIds, runLengths, lengths, offsets), exactly matching the reference
    /// implementation's `deserializeIndex`. The offset array's "0 means contiguous
    /// with the previous entry" special case is the one detail most likely to be
    /// gotten wrong from the prose spec alone; this mirrors the reference code's
    /// exact `v == 0 && i > 0 ? previous.offset + previous.length : v - 1` logic.
    static func deserialize(_ data: Data) throws -> [PMTilesEntry] {
        var reader = VarintReader(data)
        let count = Int(try reader.readVarint())
        guard count > 0 else { return [] }

        var tileIds = [UInt64](repeating: 0, count: count)
        var lastId: UInt64 = 0
        for i in 0..<count {
            let delta = try reader.readVarint()
            lastId += delta
            tileIds[i] = lastId
        }

        var runLengths = [UInt64](repeating: 0, count: count)
        for i in 0..<count { runLengths[i] = try reader.readVarint() }

        var lengths = [UInt64](repeating: 0, count: count)
        for i in 0..<count { lengths[i] = try reader.readVarint() }

        var entries: [PMTilesEntry] = []
        entries.reserveCapacity(count)
        var previousOffset: UInt64 = 0
        var previousLength: UInt64 = 0
        for i in 0..<count {
            let v = try reader.readVarint()
            let offset: UInt64
            if v == 0, i > 0 {
                offset = previousOffset + previousLength
            } else {
                offset = v - 1
            }
            entries.append(PMTilesEntry(tileId: tileIds[i], offset: offset, length: lengths[i], runLength: runLengths[i]))
            previousOffset = offset
            previousLength = lengths[i]
        }
        return entries
    }

    /// Binary search for `tileId` within a directory's entries — exactly
    /// `findTile` from the reference implementation: an exact match returns
    /// directly; otherwise, the largest entry with `tileId <= target` is checked —
    /// a `runLength == 0` entry is a leaf-directory pointer (always "found," since
    /// descending into it is the next step regardless of the exact target),
    /// otherwise the target must fall within `[entry.tileId, entry.tileId +
    /// runLength)` to count as a match.
    static func findTile(_ entries: [PMTilesEntry], tileId: UInt64) -> PMTilesEntry? {
        var lo = 0
        var hi = entries.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = entries[mid]
            if tileId == entry.tileId {
                return entry
            } else if tileId > entry.tileId {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        guard hi >= 0 else { return nil }
        let candidate = entries[hi]
        if candidate.runLength == 0 { return candidate }
        if tileId - candidate.tileId < candidate.runLength { return candidate }
        return nil
    }
}
