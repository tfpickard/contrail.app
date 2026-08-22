import Foundation
import Testing
@testable import ContrailIFE

private struct FailingParser: IFEPayloadParser {
    func parse(_ data: Data) -> IFEReading? { nil }
}

private struct FixedParser: IFEPayloadParser {
    let reading: IFEReading
    func parse(_ data: Data) -> IFEReading? { reading }
}

private enum FakeFetchError: Error { case unreachable }

struct IFEProberTests {
    @Test func triesTargetsInOrderAndStopsAtFirstSuccess() async {
        let attempted = Attempted()
        let targets = [
            IFEProbeTarget(name: "first", url: URL(string: "http://10.0.0.1/a")!),
            IFEProbeTarget(name: "second", url: URL(string: "http://10.0.0.2/b")!),
            IFEProbeTarget(name: "third", url: URL(string: "http://10.0.0.3/c")!),
        ]
        let expected = IFEReading(staticAirTemperatureC: -55)

        let prober = IFEProber(
            targets: targets, parsers: [FixedParser(reading: expected)],
            fetch: { target in
                await attempted.record(target.name)
                if target.name == "second" { return Data() }
                throw FakeFetchError.unreachable
            }
        )

        let result = await prober.probe()
        #expect(result == expected)
        #expect(await attempted.names == ["first", "second"])
    }

    @Test func returnsNilWhenEveryTargetFails() async {
        let targets = [IFEProbeTarget(name: "only", url: URL(string: "http://10.0.0.1/a")!)]
        let prober = IFEProber(
            targets: targets, parsers: [FailingParser()],
            fetch: { _ in throw FakeFetchError.unreachable }
        )
        #expect(await prober.probe() == nil)
    }

    @Test func fallsThroughToASecondParserIfTheFirstDoesNotRecognizeTheShape() async {
        let expected = IFEReading(trueAirspeedMS: 230)
        let targets = [IFEProbeTarget(name: "only", url: URL(string: "http://10.0.0.1/a")!)]
        let prober = IFEProber(
            targets: targets, parsers: [FailingParser(), FixedParser(reading: expected)],
            fetch: { _ in Data() }
        )
        #expect(await prober.probe() == expected)
    }
}

private actor Attempted {
    private(set) var names: [String] = []
    func record(_ name: String) { names.append(name) }
}
