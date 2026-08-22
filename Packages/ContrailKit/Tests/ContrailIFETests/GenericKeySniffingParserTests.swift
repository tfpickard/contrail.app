import Foundation
import Testing
@testable import ContrailIFE

struct GenericKeySniffingParserTests {
    private let parser = GenericKeySniffingParser()

    @Test func parsesAFlatShapeWithCommonKeyNames() {
        let json = """
        {"sat": -54.5, "tas": 231.2, "windSpeed": 11.0, "windDirection": 265.0}
        """
        let reading = parser.parse(Data(json.utf8))
        #expect(reading?.staticAirTemperatureC == -54.5)
        #expect(reading?.trueAirspeedMS == 231.2)
        #expect(reading?.windSpeedMS == 11.0)
        #expect(reading?.windDirectionDeg == 265.0)
    }

    @Test func parsesFieldsNestedUnderAnArbitraryWrapperKey() {
        // Real vendor shapes are unknown (ROADMAP 3b) -- this stands in for "the
        // field we want is two levels deep under some vendor-specific envelope,"
        // which the parser must not assume away.
        let json = """
        {"response": {"aircraft": {"staticAirTemp": -58.0, "trueAirspeed": 240.0}}}
        """
        let reading = parser.parse(Data(json.utf8))
        #expect(reading?.staticAirTemperatureC == -58.0)
        #expect(reading?.trueAirspeedMS == 240.0)
    }

    @Test func recognizesAlternateKeyAliases() {
        let json = """
        {"outsideAirTemp": -50.0, "airspeed": 220.0, "ground_speed": 200.0,
         "lat": 39.86, "lng": -104.67, "eta_seconds": 1800}
        """
        let reading = parser.parse(Data(json.utf8))
        #expect(reading?.staticAirTemperatureC == -50.0)
        #expect(reading?.trueAirspeedMS == 220.0)
        #expect(reading?.groundspeedMS == 200.0)
        #expect(reading?.latitude == 39.86)
        #expect(reading?.longitude == -104.67)
        #expect(reading?.timeToDestinationSeconds == 1800)
    }

    @Test func coercesNumericStringValues() {
        let json = """
        {"sat": "-54.5", "tas": "231.2"}
        """
        let reading = parser.parse(Data(json.utf8))
        #expect(reading?.staticAirTemperatureC == -54.5)
        #expect(reading?.trueAirspeedMS == 231.2)
    }

    @Test func returnsNilForInvalidJSON() {
        #expect(parser.parse(Data("not json at all".utf8)) == nil)
    }

    @Test func returnsNilWhenNoRecognizableKeysArePresent() {
        let json = """
        {"unrelatedField": 42, "anotherOne": "hello"}
        """
        #expect(parser.parse(Data(json.utf8)) == nil)
    }
}
