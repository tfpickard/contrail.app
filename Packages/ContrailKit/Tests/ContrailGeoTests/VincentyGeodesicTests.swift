import Testing
import ContrailCore
@testable import ContrailGeo

/// Reference values from Vincenty's 1975 paper, as republished by Geoscience
/// Australia: Flinders Peak → Buninyong. Independently confirmed (not transcribed
/// from memory) against the commonly cited DMS coordinates:
///   Flinders Peak: 37°57′03.72030″S, 144°25′29.52440″E
///   Buninyong:     37°39′10.15610″S, 143°55′35.38390″E
///   distance = 54972.271 m, α1 = 306°52′05.37″, α2 = 127°10′25.07″
/// `finalBearing` here is the classical Vincenty **back azimuth** (α2 as published:
/// the direction from Buninyong back toward Flinders Peak). This implementation's
/// `finalBearing` deliberately uses the opposite, **forward-continuing** convention —
/// the direction of travel *at* the destination, matching `initialBearing`'s meaning
/// — because that is what `trueCourse` needs when this same routine is reused to
/// compute course between two successive position fixes (§2.2). The two conventions
/// are always exactly 180° apart, hence `publishedBackAzimuth + 180`.
private enum VincentyReference {
    static let flindersPeak = Coordinate(latitude: -37.9510334167, longitude: 144.4248678889)
    static let buninyong = Coordinate(latitude: -37.6528211389, longitude: 143.9264955278)
    static let distance = 54972.271
    static let initialBearing = 306.8681583333
    static let publishedBackAzimuth = 127.1736305556
    static let finalBearing = (publishedBackAzimuth + 180).truncatingRemainder(dividingBy: 360)
}

struct VincentyGeodesicTests {
    @Test func inverseMatchesPublishedReferenceCase() throws {
        let result = try VincentyGeodesic.inverse(
            from: VincentyReference.flindersPeak,
            to: VincentyReference.buninyong
        )
        #expect(abs(result.distance - VincentyReference.distance) < 0.001)
        #expect(abs(result.initialBearing - VincentyReference.initialBearing) < 0.0001)
        #expect(abs(result.finalBearing - VincentyReference.finalBearing) < 0.0001)
    }

    @Test func directIsInverseOfInverse() throws {
        // Round-trip: walk from Flinders Peak along the inverse-computed bearing and
        // distance to Buninyong; direct() should land within millimetres.
        let inv = try VincentyGeodesic.inverse(
            from: VincentyReference.flindersPeak,
            to: VincentyReference.buninyong
        )
        let dir = try VincentyGeodesic.direct(
            from: VincentyReference.flindersPeak,
            initialBearing: inv.initialBearing,
            distance: inv.distance
        )
        #expect(abs(dir.destination.latitude - VincentyReference.buninyong.latitude) < 1e-6)
        #expect(abs(dir.destination.longitude - VincentyReference.buninyong.longitude) < 1e-6)
        #expect(abs(dir.finalBearing - inv.finalBearing) < 0.0001)
    }

    @Test func coincidentPointsHaveZeroDistance() throws {
        let p = Coordinate(latitude: 39.8617, longitude: -104.6731)
        let result = try VincentyGeodesic.inverse(from: p, to: p)
        #expect(result.distance == 0)
    }

    @Test func denverToLosAngelesIsApproximatelyCorrect() throws {
        // DEN -> LAX great-circle distance is well known to be ~1385 km (~747 nm).
        let den = Coordinate(latitude: 39.8617, longitude: -104.6731)
        let lax = Coordinate(latitude: 33.9416, longitude: -118.4085)
        let result = try VincentyGeodesic.inverse(from: den, to: lax)
        #expect(result.distance > 1_370_000)
        #expect(result.distance < 1_400_000)
        // Bearing should be roughly southwest (between 220° and 260°).
        #expect(result.initialBearing > 220)
        #expect(result.initialBearing < 260)
    }
}
