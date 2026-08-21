import Foundation
import Testing
import ContrailData
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

struct NavFixCompilerTests {
    // The real FAA NASR FIX_BASE.csv header (28-day cycle effective 2026-08-06)
    // plus two real fix rows, verified against the live download.
    private let fixFixtureCSV = """
    "EFF_DATE","FIX_ID","ICAO_REGION_CODE","STATE_CODE","COUNTRY_CODE","LAT_DEG","LAT_MIN","LAT_SEC","LAT_HEMIS","LAT_DECIMAL","LONG_DEG","LONG_MIN","LONG_SEC","LONG_HEMIS","LONG_DECIMAL","FIX_ID_OLD","CHARTING_REMARK","FIX_USE_CODE","ARTCC_ID_HIGH","ARTCC_ID_LOW","PITCH_FLAG","CATCH_FLAG","SUA_ATCAA_FLAG","MIN_RECEP_ALT","COMPULSORY","CHARTS"
    "2026/08/06","AAALL","K6","MA","US",42,7,12.68,"N",42.12018888,71,8,30.34,"W",-71.14176111,"","","WP   ","ZBW","ZBW","N","N","N",,"","IAP"
    "2026/08/06","AAAME","K2","CA","US",37,46,15.27,"N",37.77090833,122,4,58.12,"W",-122.08281111,"","","WP   ","ZOA","ZOA","N","N","N",,"","STAR"
    """

    // The real NAV_BASE.csv header plus three real rows: two OPERATIONAL navaids
    // (one restricted) and one SHUTDOWN one (EWR DME) to exercise the status filter.
    private let navFixtureCSV = """
    "EFF_DATE","NAV_ID","NAV_TYPE","STATE_CODE","CITY","COUNTRY_CODE","NAV_STATUS","NAME","STATE_NAME","REGION_CODE","COUNTRY_NAME","FAN_MARKER","OWNER","OPERATOR","NAS_USE_FLAG","PUBLIC_USE_FLAG","NDB_CLASS_CODE","OPER_HOURS","HIGH_ALT_ARTCC_ID","HIGH_ARTCC_NAME","LOW_ALT_ARTCC_ID","LOW_ARTCC_NAME","LAT_DEG","LAT_MIN","LAT_SEC","LAT_HEMIS","LAT_DECIMAL","LONG_DEG","LONG_MIN","LONG_SEC","LONG_HEMIS","LONG_DECIMAL","SURVEY_ACCURACY_CODE","TACAN_DME_STATUS","TACAN_DME_LAT_DEG","TACAN_DME_LAT_MIN","TACAN_DME_LAT_SEC","TACAN_DME_LAT_HEMIS","TACAN_DME_LAT_DECIMAL","TACAN_DME_LONG_DEG","TACAN_DME_LONG_MIN","TACAN_DME_LONG_SEC","TACAN_DME_LONG_HEMIS","TACAN_DME_LONG_DECIMAL","ELEV","MAG_VARN","MAG_VARN_HEMIS","MAG_VARN_YEAR","SIMUL_VOICE_FLAG","PWR_OUTPUT","AUTO_VOICE_ID_FLAG","MNT_CAT_CODE","VOICE_CALL","CHAN","FREQ","MKR_IDENT","MKR_SHAPE","MKR_BRG","ALT_CODE","DME_SSV","LOW_NAV_ON_HIGH_CHART_FLAG","Z_MKR_FLAG","FSS_ID","FSS_NAME","FSS_HOURS","NOTAM_ID","QUAD_IDENT","PITCH_FLAG","CATCH_FLAG","SUA_ATCAA_FLAG","RESTRICTION_FLAG","HIWAS_FLAG"
    "2026/08/06","AA","NDB","ND","FARGO","US","OPERATIONAL IFR","KENIE","NORTH DAKOTA","AGL","UNITED STATES","","F-FEDERAL AVIATION ADMIN","F-FEDERAL AVIATION ADMIN","Y","Y","HW/LOM","24","ZMP","MINNEAPOLIS","ZMP","MINNEAPOLIS",47,0,32.5878,"N",47.00905216,96,48,54.6606,"W",-96.8151835,"6","",,,,"",,,,,"",,890.6,4,"E",2005,"N",100,"N","1","NONE","",365,"","",,"","","","N","GFK","GRAND FORKS","24","FAR","","N","N","N","",""
    "2026/08/06","AA","NDB","GA","THOMSON","US","OPERATIONAL RESTRICTED","CEDAR","GEORGIA","ASO","UNITED STATES","","F-FEDERAL AVIATION ADMINISTRATION","F-FEDERAL AVIATION ADMINISTRATION","Y","Y","MHW","24","ZTL","ATLANTA","ZTL","ATLANTA",33,31,59.82,"N",33.53328333,82,36,51.73,"W",-82.61436944,"","",,,,"",,,,,"",,515.2,4,"W",1995,"N",25,"N","3","NONE","",341,"","",,"","","","","MCN","MACON","24","MCN","","N","N","N","",""
    "2026/08/06","EWR","DME","NJ","NEWARK","US","SHUTDOWN","NEWARK","NEW JERSEY","AEA","UNITED STATES","","F-FEDERAL AVIATION ADMINISTRATION","F-FEDERAL AVIATION ADMINISTRATION","Y","Y","","24","ZNY","NEW YORK","ZNY","NEW YORK",40,40,27.64,"N",40.67434444,74,10,40.68,"W",-74.17796666,"","OPERATIONAL IFR",40,40,27.64,"N",40.67434444,74,10,40.68,"W",-74.17796666,9,,"",,"N",,"N","1","NONE","84Y",113.75,"","",,"","T","","","MIV","MILLVILLE","24","EWR","","N","N","N","",""
    """

    @Test func parsesRealFixRowsWithDecimalCoordinatesAndARTCC() {
        let records = NavFixCompiler.compileFixes(csv: fixFixtureCSV)
        #expect(records.count == 2)
        let aaall = records[0]
        #expect(aaall.id == "AAALL")
        #expect(aaall.kind == .fix)
        #expect(abs(aaall.coordinate.latitude - 42.12018888) < 0.00001)
        #expect(abs(aaall.coordinate.longitude - (-71.14176111)) < 0.00001)
        #expect(aaall.artccHigh == "ZBW")
        #expect(aaall.artccLow == "ZBW")
    }

    @Test func excludesShutdownNavaidsButKeepsRestrictedOnes() {
        let records = NavFixCompiler.compileNavaids(csv: navFixtureCSV)
        // Two "AA" NDBs (IFR + restricted) kept; the SHUTDOWN "EWR" DME excluded.
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.id != "EWR" })
    }

    @Test func parsesNavaidTypeNameAndFrequency() throws {
        let records = NavFixCompiler.compileNavaids(csv: navFixtureCSV)
        let kenie = try #require(records.first { $0.name == "KENIE" })
        #expect(kenie.kind == .navaid)
        #expect(kenie.navaidType == "NDB")
        #expect(kenie.frequency == 365) // NDB frequency, kHz -- not MHz
        #expect(kenie.artccHigh == "ZMP")
        #expect(kenie.artccLow == "ZMP")
    }
}

struct ARTCCBoundaryCompilerTests {
    // Real ARB_BASE.csv/ARB_SEG.csv rows for ZAB (Albuquerque) -- a real, if
    // deliberately truncated to 4 vertices, HIGH-altitude boundary fragment. Four
    // points is enough to exercise ordering-by-POINT_SEQ and polygon assembly
    // without embedding all 67 real vertices in a test fixture.
    private let baseFixtureCSV = """
    "EFF_DATE","LOCATION_ID","LOCATION_NAME","COMPUTER_ID","ICAO_ID","LOCATION_TYPE","CITY","STATE","COUNTRY_CODE","LAT_DEG","LAT_MIN","LAT_SEC","LAT_HEMIS","LAT_DECIMAL","LONG_DEG","LONG_MIN","LONG_SEC","LONG_HEMIS","LONG_DECIMAL","CROSS_REF"
    "2026/07/09","ZAB","ALBUQUERQUE","ZAB","KZAB","ARTCC","ALBUQUERQUE","NM","US",35,2,0,"N",35.03333333,106,37,0,"W",-106.61666666,""
    """

    private let segFixtureCSV = """
    "EFF_DATE","REC_ID","LOCATION_ID","LOCATION_NAME","ALTITUDE","TYPE","POINT_SEQ","LAT_DEG","LAT_MIN","LAT_SEC","LAT_HEMIS","LAT_DECIMAL","LONG_DEG","LONG_MIN","LONG_SEC","LONG_HEMIS","LONG_DECIMAL","BNDRY_PT_DESCRIP","NAS_DESCRIP_FLAG"
    "2026/07/09","ZAB*H*53855","ZAB","ALBUQUERQUE","HIGH","ARTCC",10,35,46,0,"N",35.76666666,111,50,30,"W",-111.84166666,"/COMMON ZAB-ZDV-ZLA/TO",""
    "2026/07/09","ZAB*H*53866","ZAB","ALBUQUERQUE","HIGH","ARTCC",40,36,12,0,"N",36.2,107,28,0,"W",-107.46666666,"TO",""
    "2026/07/09","ZAB*H*53877","ZAB","ALBUQUERQUE","HIGH","ARTCC",20,35,42,0,"N",35.7,110,14,0,"W",-110.23333333,"/COMMON ZAB-ZDV/ TO",""
    "2026/07/09","ZAB*H*53462","ZAB","ALBUQUERQUE","HIGH","ARTCC",30,36,2,0,"N",36.03333333,108,13,0,"W",-108.21666666,"/COMMON ZAB-ZDV/ TO",""
    """

    @Test func assemblesPolygonOrderedByPointSeqNotFileOrder() {
        // Rows above are deliberately out of POINT_SEQ order (10, 40, 20, 30) to
        // verify the compiler sorts rather than trusting file order.
        let boundaries = ARTCCBoundaryCompiler.compile(baseCSV: baseFixtureCSV, segmentsCSV: segFixtureCSV)
        #expect(boundaries.count == 1)
        let zab = boundaries[0]
        #expect(zab.id == "ZAB")
        #expect(zab.name == "ALBUQUERQUE")
        #expect(zab.altitudeTier == .high)
        #expect(zab.vertices.count == 4)
        // Sequence 10, 20, 30, 40 in order -- longitudes -111.84, -110.23, -108.22, -107.47.
        #expect(abs(zab.vertices[0].longitude - (-111.84166666)) < 0.0001)
        #expect(abs(zab.vertices[1].longitude - (-110.23333333)) < 0.0001)
        #expect(abs(zab.vertices[2].longitude - (-108.21666666)) < 0.0001)
        #expect(abs(zab.vertices[3].longitude - (-107.46666666)) < 0.0001)
    }
}
