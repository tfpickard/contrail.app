import Foundation
import Testing
import CoreGraphics
import ImageIO
@testable import ContrailPhoto

/// The strongest verification available for this: build a real JPEG with real
/// ImageIO (`CGImageDestination`), inject XMP by hand, then read it back with
/// real ImageIO (`CGImageMetadata`) -- not just "the bytes look plausible," but
/// "Apple's own JPEG/XMP reader parses what this wrote."
struct JPEGSegmentInjectorTests {
    /// A minimal real JPEG (2×2 solid-color pixels), produced by `CGImageDestination`
    /// rather than hand-written bytes -- this is a genuine JPEG file, exercising the
    /// injector against real encoder output rather than a synthetic fixture.
    private func makeRealJPEG() throws -> Data {
        let width = 2, height = 2
        var pixels: [UInt8] = Array(repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 200; pixels[i + 1] = 100; pixels[i + 2] = 50; pixels[i + 3] = 255
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cgImage = try #require(context.makeImage())

        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func injectsIntoARealJPEGAndImageIOReadsItBackCorrectly() throws {
        let jpeg = try makeRealJPEG()
        let json = #"{"altitude":11582.4,"phase":"cruise","route":{"nearestCity":"Ely, Nevada"}}"#
        let packet = XMPPacketBuilder.buildPacket(jsonSnapshot: json)

        let injected = try JPEGSegmentInjector.injectXMP(packet, intoJPEG: jpeg)

        // Still a valid, decodable JPEG after injection.
        let source = try #require(CGImageSourceCreateWithData(injected as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
        #expect(decoded != nil)
        #expect(decoded?.width == 2)

        // The real assertion: Apple's own CGImageMetadata reads the injected XMP
        // back out, under the exact namespace/property this module wrote. The
        // namespace has to be registered on the specific (mutable) metadata
        // instance being queried -- there's no global registry.
        let immutableMetadata = try #require(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
        let metadata = try #require(CGImageMetadataCreateMutableCopy(immutableMetadata))
        #expect(CGImageMetadataRegisterNamespaceForPrefix(
            metadata, XMPPacketBuilder.namespaceURI as CFString, XMPPacketBuilder.namespacePrefix as CFString, nil
        ))
        let value = CGImageMetadataCopyStringValueWithPath(
            metadata, nil, "\(XMPPacketBuilder.namespacePrefix):snapshot" as CFString
        )
        #expect(value as String? == json)
    }

    @Test func rejectsDataThatIsNotAJPEG() {
        let notJPEG = Data([0x00, 0x01, 0x02, 0x03])
        #expect(throws: JPEGSegmentInjector.InjectionError.notAJPEG) {
            _ = try JPEGSegmentInjector.injectXMP("<xmp/>", intoJPEG: notJPEG)
        }
    }

    @Test func injectedSegmentImmediatelyFollowsExistingAPPnSegments() throws {
        // A hand-built minimal JPEG: SOI, one APP0 (JFIF) segment, then EOI --
        // verifies the new APP1 lands right after the existing APP0, not at the
        // very start (which would come before JFIF, an unconventional ordering)
        // and not at the very end (past EOI, which would be invalid).
        var bytes: [UInt8] = [0xFF, 0xD8] // SOI
        bytes += [0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46] // APP0, length 4, 2 bytes payload "JF"
        bytes += [0xFF, 0xD9] // EOI
        let jpeg = Data(bytes)

        let injected = try JPEGSegmentInjector.injectXMP("<xmp/>", intoJPEG: jpeg)
        let injectedBytes = [UInt8](injected)

        // Expect: SOI, APP0 (unchanged, 6 bytes total: FF E0 00 04 4A 46), new APP1, EOI.
        #expect(Array(injectedBytes[0..<8]) == [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46])
        #expect(injectedBytes[8] == 0xFF)
        #expect(injectedBytes[9] == 0xE1) // the new APP1
        #expect(injectedBytes.suffix(2) == [0xFF, 0xD9]) // EOI still at the very end
    }
}
