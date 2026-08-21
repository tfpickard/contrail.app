import Foundation
import CoreGraphics
import ImageIO
import ContrailCore
import ContrailPhoto

/// §7.2's three metadata tiers, applied in order: standard EXIF/GPS (tier 1) and
/// EXIF `UserComment`/IPTC caption (tier 2) via `ImageIO`'s own property-dictionary
/// API, then the XMP snapshot (tier 3) via `JPEGSegmentInjector` -- ImageIO has no
/// write path for tier 3 at all (see that type's own doc comment), so it has to
/// happen as a second pass over the JPEG bytes ImageIO already wrote tiers 1-2 into.
enum PhotoMetadataWriter {
    enum WriteError: Error {
        case couldNotReadSource
        case couldNotCreateDestination
        case couldNotFinalize
        case couldNotEncodeSnapshot
    }

    static func embedMetadata(
        into jpegData: Data, capturedAt output: EstimatorOutput, title: String, description: String
    ) throws -> Data {
        let withTiersOneAndTwo = try embedEXIFAndIPTC(into: jpegData, output: output, title: title, description: description)

        let encoder = JSONEncoder()
        guard let snapshotJSON = try? encoder.encode(output),
              let snapshotString = String(data: snapshotJSON, encoding: .utf8)
        else {
            throw WriteError.couldNotEncodeSnapshot
        }
        let xmpPacket = XMPPacketBuilder.buildPacket(jsonSnapshot: snapshotString)
        return try JPEGSegmentInjector.injectXMP(xmpPacket, intoJPEG: withTiersOneAndTwo)
    }

    private static func embedEXIFAndIPTC(
        into jpegData: Data, output: EstimatorOutput, title: String, description: String
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil) else {
            throw WriteError.couldNotReadSource
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]

        // Tier 1: standard EXIF/GPS -- position, altitude, heading, timestamp.
        if let coordinate = output.position.fused.value {
            var gps: [CFString: Any] = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
            gps[kCGImagePropertyGPSLatitude] = abs(coordinate.latitude)
            gps[kCGImagePropertyGPSLatitudeRef] = coordinate.latitude >= 0 ? "N" : "S"
            gps[kCGImagePropertyGPSLongitude] = abs(coordinate.longitude)
            gps[kCGImagePropertyGPSLongitudeRef] = coordinate.longitude >= 0 ? "E" : "W"
            if let altitude = output.position.altitudeGPS.value {
                gps[kCGImagePropertyGPSAltitude] = abs(altitude)
                gps[kCGImagePropertyGPSAltitudeRef] = altitude >= 0 ? 0 : 1
            }
            if let course = output.motion.trueCourse.value {
                gps[kCGImagePropertyGPSTrack] = course
                gps[kCGImagePropertyGPSTrackRef] = "T" // true, not magnetic
            }
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss.SSSSSS"
            timeFormatter.timeZone = TimeZone(identifier: "UTC")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy:MM:dd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            gps[kCGImagePropertyGPSTimeStamp] = timeFormatter.string(from: output.t)
            gps[kCGImagePropertyGPSDateStamp] = dateFormatter.string(from: output.t)
            properties[kCGImagePropertyGPSDictionary] = gps
        }

        var exif: [CFString: Any] = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let exifDateFormatter = DateFormatter()
        exifDateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        exifDateFormatter.timeZone = TimeZone(identifier: "UTC")
        exif[kCGImagePropertyExifDateTimeOriginal] = exifDateFormatter.string(from: output.t)
        // Tier 2: EXIF UserComment -- the generated description, per §7.2.
        exif[kCGImagePropertyExifUserComment] = description
        properties[kCGImagePropertyExifDictionary] = exif

        // Tier 2: IPTC caption/description -- Photos surfaces this as an editable,
        // searchable field. Title goes in ObjectName (a headline-shaped field IPTC
        // already has, distinct from the caption); the spec assigns description to
        // two places (EXIF UserComment above, IPTC CaptionAbstract here) but only
        // says "the generated summary," not where the title specifically lives.
        var iptc: [CFString: Any] = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        iptc[kCGImagePropertyIPTCObjectName] = title
        iptc[kCGImagePropertyIPTCCaptionAbstract] = description
        properties[kCGImagePropertyIPTCDictionary] = iptc

        let outputData = NSMutableData()
        guard let type = CGImageSourceGetType(source),
              let destination = CGImageDestinationCreateWithData(outputData, type, 1, nil)
        else {
            throw WriteError.couldNotCreateDestination
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WriteError.couldNotFinalize }
        return outputData as Data
    }
}
