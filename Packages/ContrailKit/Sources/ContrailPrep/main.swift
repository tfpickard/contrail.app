import Foundation
import ContrailData

/// `contrail-prep airports <ourairports airports.csv> <output.bin>`
/// `contrail-prep places <geonames cities1000.txt> <output.bin>`
/// `contrail-prep navfixes <NASR FIX_BASE.csv> <NASR NAV_BASE.csv> <output.bin>`
/// `contrail-prep artcc <NASR ARB_BASE.csv> <NASR ARB_SEG.csv> <output.bin>`
///
/// The compiler §5/§10 calls for: run once against the raw upstream files, producing
/// the flat binaries the app bundles. Not itself shipped in the app.

let arguments = CommandLine.arguments

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func readText(_ path: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("could not read input file: \(path)")
    }
    return text
}

let usage = """
Usage:
  contrail-prep airports <input airports.csv> <output.bin>
  contrail-prep places <input cities1000.txt> <output.bin>
  contrail-prep navfixes <input FIX_BASE.csv> <input NAV_BASE.csv> <output.bin>
  contrail-prep artcc <input ARB_BASE.csv> <input ARB_SEG.csv> <output.bin>
"""

guard arguments.count >= 2 else { fail(usage) }
let command = arguments[1]

let outputData: Data
let count: Int
let outputPath: String

switch command {
case "airports":
    guard arguments.count == 4 else { fail(usage) }
    let records = AirportCompiler.compile(csv: readText(arguments[2]))
    outputData = AirportIndex.compile(records: records)
    count = records.count
    outputPath = arguments[3]
case "places":
    guard arguments.count == 4 else { fail(usage) }
    let records = PlaceCompiler.compile(tsv: readText(arguments[2]))
    outputData = PlaceIndex.compile(records: records)
    count = records.count
    outputPath = arguments[3]
case "navfixes":
    guard arguments.count == 5 else { fail(usage) }
    let fixes = NavFixCompiler.compileFixes(csv: readText(arguments[2]))
    let navaids = NavFixCompiler.compileNavaids(csv: readText(arguments[3]))
    let records = fixes + navaids
    outputData = NavFixIndex.compile(records: records)
    count = records.count
    outputPath = arguments[4]
case "artcc":
    guard arguments.count == 5 else { fail(usage) }
    let boundaries = ARTCCBoundaryCompiler.compile(
        baseCSV: readText(arguments[2]), segmentsCSV: readText(arguments[3])
    )
    outputData = ARTCCBoundaryIndex.compile(boundaries: boundaries)
    count = boundaries.count
    outputPath = arguments[4]
default:
    fail("unknown command '\(command)'\n\n\(usage)")
}

do {
    try outputData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fail("could not write output file: \(outputPath) (\(error))")
}

print("compiled \(count) records -> \(outputPath) (\(outputData.count) bytes)")
