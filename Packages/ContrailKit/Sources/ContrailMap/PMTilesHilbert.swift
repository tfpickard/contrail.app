import Foundation

/// The PMTiles global tile ID: a single running index across a Hilbert curve at
/// every zoom level starting from 0, used as the key directory entries are sorted
/// and searched by. Translated as directly as possible from the reference
/// implementation's `zxyToTileId` (`js/src/index.ts`) — deliberately keeping the
/// same variable roles and the *exact* bit arithmetic rather than a "cleaner"
/// rewrite: `rx`/`ry` are **raw bit values** (`0` or the current bit position `s`),
/// not normalized booleans, and `(3 * rx) ^ ry` only produces the correct Hilbert
/// quadrant index when `rx`/`ry` keep that raw form. A seemingly-equivalent version
/// using 0/1 booleans would silently compute wrong tile IDs.
///
/// Internally uses `Int` (signed), matching JS's own always-signed-double
/// semantics, converting to `UInt64` only at the final return — the `rotate` step's
/// `n - 1 - y` subtraction has no proof-by-inspection guarantee of staying
/// non-negative at every intermediate step, and computing it in `UInt64` would trap
/// on any underflow rather than behaving like the reference implementation.
enum PMTilesHilbert {
    static func tileId(z: UInt8, x: UInt64, y: UInt64) -> UInt64 {
        if z == 0 { return 0 }

        let side = 1 << Int(z)
        var acc = (side * side - 1) / 3
        var a = Int(z) - 1
        var tx = Int(x)
        var ty = Int(y)

        var s = 1 << a
        while s > 0 {
            let rx = tx & s
            let ry = ty & s
            acc += ((3 * rx) ^ ry) * (1 << a)
            (tx, ty) = rotate(n: s, x: tx, y: ty, rx: rx, ry: ry)
            a -= 1
            s = a >= 0 ? (1 << a) : 0
        }
        return UInt64(acc)
    }

    private static func rotate(n: Int, x: Int, y: Int, rx: Int, ry: Int) -> (Int, Int) {
        if ry == 0 {
            if rx != 0 {
                return (n - 1 - y, n - 1 - x)
            }
            return (y, x)
        }
        return (x, y)
    }
}
