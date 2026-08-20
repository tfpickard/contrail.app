import Foundation
import Testing
@testable import ContrailPrep

struct CSVParserTests {
    @Test func parsesSimpleRows() {
        let rows = CSVParser.parse("a,b,c\n1,2,3\n")
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test func handlesQuotedFieldsWithEmbeddedCommas() {
        let rows = CSVParser.parse(#"1,"Denver, Colorado",3"#)
        #expect(rows == [["1", "Denver, Colorado", "3"]])
    }

    @Test func handlesEscapedQuotesInsideQuotedFields() {
        let rows = CSVParser.parse(#"1,"say ""hi""",3"#)
        #expect(rows == [["1", "say \"hi\"", "3"]])
    }

    @Test func handlesCRLFLineEndings() {
        let rows = CSVParser.parse("a,b\r\n1,2\r\n")
        #expect(rows == [["a", "b"], ["1", "2"]])
    }

    @Test func handlesFileWithNoTrailingNewline() {
        let rows = CSVParser.parse("a,b\n1,2")
        #expect(rows == [["a", "b"], ["1", "2"]])
    }
}

struct AirportCompilerTests {
    // A small, real-shaped fixture: the actual OurAirports header plus a handful of
    // representative rows (scheduled and non-scheduled, with and without ICAO/IATA,
    // and a name containing a comma to exercise the CSV quoting path).
    private let fixtureCSV = """
    "id","ident","type","name","latitude_deg","longitude_deg","elevation_ft","continent","iso_country","iso_region","municipality","scheduled_service","icao_code","iata_code","gps_code","local_code","home_link","wikipedia_link","keywords"
    3364,"KDEN","large_airport","Denver, Colorado - International Airport",39.861698,-104.673004,5431,"NA","US","US-CO","Denver","yes","KDEN","DEN","KDEN","DEN",,,
    6523,"00A","heliport","Total RF Heliport",40.070985,-74.933689,11,"NA","US","US-PA","Bensalem","no",,,"K00A","00A",,,
    4650,"03N","small_airport","Utirik Airport",11.222219,169.851429,4,"OC","MH","MH-UTI","Utirik Island","yes",,"UTK","03N","03N",,,
    """

    @Test func filtersToScheduledServiceWithAnICAOCode() {
        let records = AirportCompiler.compile(csv: fixtureCSV)
        // Row 2 (00A) is scheduled_service=no -> excluded.
        // Row 3 (03N/Utirik) is scheduled_service=yes but has no icao_code -> excluded.
        // Only KDEN qualifies.
        #expect(records.count == 1)
        #expect(records[0].icao == "KDEN")
    }

    @Test func parsesCommaContainingNameCorrectly() {
        let records = AirportCompiler.compile(csv: fixtureCSV)
        #expect(records[0].name == "Denver, Colorado - International Airport")
    }

    @Test func convertsElevationFeetToMetres() {
        let records = AirportCompiler.compile(csv: fixtureCSV)
        // 5431 ft * 0.3048 = 1655.3688 m (Denver's real elevation, ~1655 m).
        #expect(abs(records[0].elevationMetres - 1655.3688) < 0.01)
    }

    @Test func classifiesAirportKindFromTypeColumn() {
        let records = AirportCompiler.compile(csv: fixtureCSV)
        #expect(records[0].kind == .largeAirport)
    }
}

struct PlaceCompilerTests {
    // The real Ely, Nevada row from GeoNames' cities1000.txt, verified against the
    // live download rather than hand-typed from memory.
    private let fixtureTSV = """
    5503694\tEly\tEly\tELY,Ehlaj,Ehli\t39.24744\t-114.88863\tP\tPPLA2\tUS\t\tNV\t033\t\t\t4134\t1962\t1968\tAmerica/Los_Angeles\t2019-09-19
    5419384\tDenver\tDenver\tDenver\t39.73915\t-104.9847\tP\tPPLA\tUS\t\tCO\t031\t\t\t715522\t1594\t1609\tAmerica/Denver\t2019-09-19
    """

    @Test func parsesRealGeoNamesRowsCorrectly() {
        let records = PlaceCompiler.compile(tsv: fixtureTSV)
        #expect(records.count == 2)

        let ely = records[0]
        #expect(ely.name == "Ely")
        #expect(abs(ely.coordinate.latitude - 39.24744) < 0.00001)
        #expect(abs(ely.coordinate.longitude - (-114.88863)) < 0.00001)
        #expect(ely.countryCode == "US")
        #expect(ely.admin1Code == "NV")
        #expect(ely.population == 4134)
    }

    @Test func handlesEmptyLinesGracefully() {
        let records = PlaceCompiler.compile(tsv: fixtureTSV + "\n\n")
        #expect(records.count == 2)
    }
}
