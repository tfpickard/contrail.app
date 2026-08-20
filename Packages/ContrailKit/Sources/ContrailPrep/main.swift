import Foundation
import ContrailData

/// `contrail-prep airports <ourairports airports.csv> <output.bin>`
/// `contrail-prep places <geonames cities1000.txt> <output.bin>`
///
/// The compiler §5/§10 calls for: run once against the raw upstream files, producing
/// the flat binaries the app bundles. Not itself shipped in the app.

let arguments = CommandLine.arguments

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard arguments.count == 4 else {
    fail("""
    Usage:
      contrail-prep airports <input airports.csv> <output.bin>
      contrail-prep places <input cities1000.txt> <output.bin>
    """)
}

let command = arguments[1]
let inputPath = arguments[2]
let outputPath = arguments[3]

guard let inputText = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
    fail("could not read input file: \(inputPath)")
}

let outputData: Data
let count: Int

switch command {
case "airports":
    let records = AirportCompiler.compile(csv: inputText)
    outputData = AirportIndex.compile(records: records)
    count = records.count
case "places":
    let records = PlaceCompiler.compile(tsv: inputText)
    outputData = PlaceIndex.compile(records: records)
    count = records.count
default:
    fail("unknown command '\(command)' — expected 'airports' or 'places'")
}

do {
    try outputData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fail("could not write output file: \(outputPath) (\(error))")
}

print("compiled \(count) records -> \(outputPath) (\(outputData.count) bytes)")
