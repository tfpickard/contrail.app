import Testing
import ContrailCore
@testable import ContrailGeo

struct PointInPolygonTests {
    private let unitSquare: [Coordinate] = [
        Coordinate(latitude: 0, longitude: 0),
        Coordinate(latitude: 0, longitude: 1),
        Coordinate(latitude: 1, longitude: 1),
        Coordinate(latitude: 1, longitude: 0),
    ]

    @Test func containsAPointStrictlyInside() {
        #expect(PointInPolygon.contains(Coordinate(latitude: 0.5, longitude: 0.5), polygon: unitSquare))
    }

    @Test func excludesAPointStrictlyOutside() {
        #expect(!PointInPolygon.contains(Coordinate(latitude: 2, longitude: 2), polygon: unitSquare))
    }

    @Test func excludesAPointOnTheOppositeSide() {
        #expect(!PointInPolygon.contains(Coordinate(latitude: -0.5, longitude: 0.5), polygon: unitSquare))
    }

    @Test func degeneratePolygonsContainNothing() {
        #expect(!PointInPolygon.contains(Coordinate(latitude: 0, longitude: 0), polygon: []))
        #expect(!PointInPolygon.contains(
            Coordinate(latitude: 0, longitude: 0),
            polygon: [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 1, longitude: 1)]
        ))
    }

    // The real FAA NASR ZAB (Albuquerque) HIGH-altitude ARTCC boundary, all 67
    // published vertices (2026-08-06 28-day cycle) -- verifies the algorithm against
    // an actual, non-convex, real-world polygon, not just a synthetic square.
    private let zabHighBoundary: [Coordinate] = [
        Coordinate(latitude: 35.76666666, longitude: -111.84166666),
        Coordinate(latitude: 35.7, longitude: -110.23333333),
        Coordinate(latitude: 36.03333333, longitude: -108.21666666),
        Coordinate(latitude: 36.2, longitude: -107.46666666),
        Coordinate(latitude: 36.71666666, longitude: -106.08333333),
        Coordinate(latitude: 36.71666666, longitude: -105),
        Coordinate(latitude: 37.5, longitude: -102.55),
        Coordinate(latitude: 36.5, longitude: -101.75),
        Coordinate(latitude: 35.82916666, longitude: -100),
        Coordinate(latitude: 35.33333333, longitude: -100),
        Coordinate(latitude: 34.86666666, longitude: -100.31666666),
        Coordinate(latitude: 34.46666666, longitude: -100.75),
        Coordinate(latitude: 34.6, longitude: -102),
        Coordinate(latitude: 34.55, longitude: -102.325),
        Coordinate(latitude: 34.31666666, longitude: -102.8),
        Coordinate(latitude: 33.775, longitude: -103.36666666),
        Coordinate(latitude: 33.40277777, longitude: -103.69166666),
        Coordinate(latitude: 33.38333333, longitude: -103.8),
        Coordinate(latitude: 33, longitude: -103.8),
        Coordinate(latitude: 32.46666666, longitude: -103.93333333),
        Coordinate(latitude: 32.03333333, longitude: -103.8),
        Coordinate(latitude: 31.65, longitude: -103.33333333),
        Coordinate(latitude: 31.28333333, longitude: -102.15),
        Coordinate(latitude: 29.76666666, longitude: -102.55833333),
        Coordinate(latitude: 29.725, longitude: -102.675),
        Coordinate(latitude: 29.36111111, longitude: -102.84027777),
        Coordinate(latitude: 29.35833333, longitude: -102.88333333),
        Coordinate(latitude: 29.21666666, longitude: -102.86666666),
        Coordinate(latitude: 29.18333333, longitude: -102.98333333),
        Coordinate(latitude: 28.95, longitude: -103.15),
        Coordinate(latitude: 28.97666666, longitude: -103.28555555),
        Coordinate(latitude: 29.06666666, longitude: -103.45),
        Coordinate(latitude: 29.15, longitude: -103.55),
        Coordinate(latitude: 29.18055555, longitude: -103.71666666),
        Coordinate(latitude: 29.26527777, longitude: -103.78333333),
        Coordinate(latitude: 29.30555555, longitude: -104),
        Coordinate(latitude: 29.4, longitude: -104.15),
        Coordinate(latitude: 29.48333333, longitude: -104.21666666),
        Coordinate(latitude: 29.53333333, longitude: -104.35),
        Coordinate(latitude: 29.65, longitude: -104.51666666),
        Coordinate(latitude: 30, longitude: -104.7),
        Coordinate(latitude: 30.15, longitude: -104.68333333),
        Coordinate(latitude: 30.36666666, longitude: -104.83333333),
        Coordinate(latitude: 30.68333333, longitude: -104.98333333),
        Coordinate(latitude: 30.83333333, longitude: -105.31666666),
        Coordinate(latitude: 31, longitude: -105.55),
        Coordinate(latitude: 31.33333333, longitude: -105.96666666),
        Coordinate(latitude: 31.46666666, longitude: -106.2),
        Coordinate(latitude: 31.73333333, longitude: -106.38333333),
        Coordinate(latitude: 31.75, longitude: -106.5),
        Coordinate(latitude: 31.78333333, longitude: -106.53333333),
        Coordinate(latitude: 31.78333333, longitude: -108.2),
        Coordinate(latitude: 31.33333333, longitude: -108.2),
        Coordinate(latitude: 31.33333333, longitude: -111.08333333),
        Coordinate(latitude: 31.63333333, longitude: -112),
        Coordinate(latitude: 32.1, longitude: -113.50833333),
        Coordinate(latitude: 32.11622777, longitude: -113.51276944),
        Coordinate(latitude: 32.7375, longitude: -113.68472222),
        Coordinate(latitude: 32.68333333, longitude: -114),
        Coordinate(latitude: 33.4, longitude: -114),
        Coordinate(latitude: 34.66666666, longitude: -114),
        Coordinate(latitude: 34.86666666, longitude: -113.7),
        Coordinate(latitude: 34.91666666, longitude: -113.61666666),
        Coordinate(latitude: 35.25555555, longitude: -112.92777777),
        Coordinate(latitude: 35.38333333, longitude: -112.66666666),
        Coordinate(latitude: 35.39666666, longitude: -112.15305555),
        Coordinate(latitude: 35.4, longitude: -112),
    ]

    @Test func realZABBoundaryContainsAlbuquerqueItself() {
        // Albuquerque International Sunport, literally inside its own center's airspace.
        #expect(PointInPolygon.contains(Coordinate(latitude: 35.0844, longitude: -106.6504), polygon: zabHighBoundary))
    }

    @Test func realZABBoundaryExcludesMiami() {
        #expect(!PointInPolygon.contains(Coordinate(latitude: 25.7617, longitude: -80.1918), polygon: zabHighBoundary))
    }

    @Test func realZABBoundaryExcludesDenverWhichIsAnotherCenter() {
        // Denver is ZDV's territory, not ZAB's -- a real adjacent-center check, not
        // just "somewhere far away."
        #expect(!PointInPolygon.contains(Coordinate(latitude: 39.7392, longitude: -104.9903), polygon: zabHighBoundary))
    }
}
