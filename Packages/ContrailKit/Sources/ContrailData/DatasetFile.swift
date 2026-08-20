import Foundation

/// The whole-file envelope around a sequence of `AirportRecord`/`PlaceRecord`s:
/// magic, a kind byte (so a misrouted file is caught immediately, not partway
/// through parsing), a schema version, and a record count.
enum DatasetFile {
    static let magic: [UInt8] = Array("CTGD".utf8)

    enum Kind: UInt8 {
        case airports = 0
        case places = 1
    }

    enum FileError: Error, Equatable {
        case badMagic
        case wrongKind(expected: Kind, found: UInt8)
        case truncated
    }

    static func write<Record>(
        records: [Record],
        kind: Kind,
        schemaMajor: UInt8 = 1,
        schemaMinor: UInt8 = 0,
        encode: (Record, inout BinaryDatasetWriter) -> Void
    ) -> Data {
        var writer = BinaryDatasetWriter()
        for byte in magic { writer.writeUInt8(byte) }
        writer.writeUInt8(kind.rawValue)
        writer.writeUInt8(schemaMajor)
        writer.writeUInt8(schemaMinor)
        writer.writeUInt32(UInt32(records.count))
        for record in records {
            encode(record, &writer)
        }
        return writer.data
    }

    static func read<Record>(
        _ data: Data,
        expecting kind: Kind,
        decode: (inout BinaryDatasetReader) throws -> Record
    ) throws -> [Record] {
        var reader = BinaryDatasetReader(data)
        for expectedByte in magic {
            guard try reader.readUInt8() == expectedByte else { throw FileError.badMagic }
        }
        let kindByte = try reader.readUInt8()
        guard kindByte == kind.rawValue else { throw FileError.wrongKind(expected: kind, found: kindByte) }
        _ = try reader.readUInt8() // schemaMajor -- 1.0 has exactly one schema, nothing to branch on yet
        _ = try reader.readUInt8() // schemaMinor
        let count = try reader.readUInt32()

        var records: [Record] = []
        records.reserveCapacity(Int(count))
        for _ in 0..<count {
            records.append(try decode(&reader))
        }
        return records
    }
}
