import Foundation

/// A minimal, versioned binary writer/reader for §5's "flat binary" datasets —
/// deliberately not JSON: a JSON parse of tens of thousands of records is real
/// overhead this format skips entirely, at the cost of hand-rolled (but simple, and
/// bounds-checked — no unsafe pointer arithmetic) encoding. Little-endian throughout.
///
/// This does not attempt true zero-copy `mmap` struct casting — that's a genuine
/// future optimization once dataset sizes or launch-time budgets demand it, not a
/// correctness requirement now: eagerly decoding tens of thousands of records into
/// Swift structs at launch is comfortably sub-second.
public struct BinaryDatasetWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func writeUInt8(_ value: UInt8) { data.append(value) }

    public mutating func writeUInt16(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    public mutating func writeUInt32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    public mutating func writeDouble(_ value: Double) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    /// A length-prefixed (UInt16, so max 65535 bytes) UTF-8 string.
    public mutating func writeString(_ value: String) {
        let bytes = Array(value.utf8)
        precondition(bytes.count <= UInt16.max, "string too long for a UInt16-prefixed field")
        writeUInt16(UInt16(bytes.count))
        data.append(contentsOf: bytes)
    }
}

public struct BinaryDatasetReader {
    private let data: Data
    private var offset: Int

    public init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    public enum ReadError: Error { case truncated }

    public mutating func readUInt8() throws -> UInt8 {
        guard offset < data.endIndex else { throw ReadError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    public mutating func readUInt16() throws -> UInt16 {
        try readInteger(UInt16.self)
    }

    public mutating func readUInt32() throws -> UInt32 {
        try readInteger(UInt32.self)
    }

    public mutating func readDouble() throws -> Double {
        let bits = try readInteger(UInt64.self)
        return Double(bitPattern: bits)
    }

    public mutating func readString() throws -> String {
        let length = Int(try readUInt16())
        guard offset + length <= data.endIndex else { throw ReadError.truncated }
        defer { offset += length }
        guard let string = String(data: data[offset..<(offset + length)], encoding: .utf8) else {
            throw ReadError.truncated
        }
        return string
    }

    public var isAtEnd: Bool { offset >= data.endIndex }

    private mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.endIndex else { throw ReadError.truncated }
        defer { offset += size }
        let bytes = data[offset..<(offset + size)]
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { dest in
            dest.copyBytes(from: bytes)
        }
        return T(littleEndian: value)
    }
}
