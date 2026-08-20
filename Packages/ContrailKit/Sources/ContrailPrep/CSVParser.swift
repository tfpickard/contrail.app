import Foundation

/// A minimal RFC4180-style CSV parser: quoted fields, embedded commas inside quotes,
/// and `""` as an escaped literal quote. OurAirports' `airports.csv` needs exactly
/// this (its `name`/`keywords` columns can contain commas); GeoNames' TSV dumps don't
/// need it at all (tab-delimited, no quoting), so `PlaceCompiler` just splits on tabs.
enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        // Swift's `Character` is an extended grapheme cluster, and "\r\n" is a
        // recognized cluster boundary exception — so it arrives as ONE `Character`,
        // not two. A switch matching `"\r"` and `"\n"` separately silently never
        // fires on it, falling through to the default case and corrupting the row.
        // Normalizing line endings up front sidesteps the whole grapheme-cluster
        // subtlety rather than trying to special-case it in the state machine below.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        var iterator = normalized.makeIterator()
        var pending: Character?

        func nextChar() -> Character? {
            if let p = pending {
                pending = nil
                return p
            }
            return iterator.next()
        }

        while let char = nextChar() {
            if insideQuotes {
                if char == "\"" {
                    if let next = nextChar() {
                        if next == "\"" {
                            currentField.append("\"")
                        } else {
                            insideQuotes = false
                            pending = next
                        }
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
                continue
            }

            switch char {
            case "\"":
                insideQuotes = true
            case ",":
                currentRow.append(currentField)
                currentField = ""
            case "\n":
                currentRow.append(currentField)
                currentField = ""
                rows.append(currentRow)
                currentRow = []
            default:
                currentField.append(char)
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }
}
