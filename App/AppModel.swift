import Foundation
import CryptoKit
import ContrailCore
import ContrailGeo
import ContrailData
import ContrailLog
import ContrailForecast
import ContrailIdentity
import ContrailIFE
import ContrailDiscovery

/// The app's single source of UI-facing state. Owns pre-flight asset verification,
/// the active flight's `FlightPlan` and live `EstimatorOutput` stream, and the NDJSON
/// log for the current flight. Everything expensive (sensor ingestion, estimation)
/// happens off this actor via `FlightEstimationEngine`; this type only ever holds the
/// throttled, `Sendable` result.
@MainActor
@Observable
final class AppModel {
    enum AssetStatus: Equatable {
        case pending
        case verified(recordCount: Int)
        case failed(String)
    }

    // MARK: - Pre-flight readiness (§5: "per-asset verified state, not a hopeful one")

    private(set) var airportAssetStatus: AssetStatus = .pending
    private(set) var placeAssetStatus: AssetStatus = .pending
    private(set) var navFixAssetStatus: AssetStatus = .pending
    private(set) var artccAssetStatus: AssetStatus = .pending

    private var airportIndex: AirportIndex?
    private var placeIndex: PlaceIndex?
    private var navFixIndex: NavFixIndex?
    private var artccIndex: ARTCCBoundaryIndex?

    // MARK: - Active flight

    private(set) var flightPlan: FlightPlan?
    private(set) var originAirport: AirportRecord?
    private(set) var destinationAirport: AirportRecord?
    private(set) var currentFlightDirectory: URL?
    private(set) var latestOutput: EstimatorOutput?
    private(set) var latestStatistics: FlightStatisticsSnapshot?
    private(set) var isFlightActive = false
    private(set) var lastLogError: String?

    // MARK: - Camera (§7)

    let photoRingBuffer = PhotoRingBuffer()

    // MARK: - GTG turbulence forecast (§4.2/§4.3)

    enum ForecastFetchStatus: Equatable {
        case idle
        case fetching
        case succeeded(sampleCount: Int)
        case failed(String)
    }

    private(set) var forecastFetchStatus: ForecastFetchStatus = .idle
    private var forecastCacheBox: ForecastCacheBox?

    /// Persisted directly to `UserDefaults` -- a GribStream account/API token is the
    /// user's own to create (see `GTGForecastClient`'s own doc comment on why this
    /// build never creates or embeds one), entered once and reused every flight.
    var gribStreamAPIToken: String {
        get { UserDefaults.standard.string(forKey: "gribStreamAPIToken") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "gribStreamAPIToken") }
    }

    // MARK: - Route intelligence (§5.3–§5.5)

    private var routeIntelligence: RouteIntelligenceEngine?
    /// Computed once at flight start -- the filed route doesn't move, so this
    /// doesn't need recomputing on every estimator update the way ARTCC/divert do.
    private(set) var onRouteFixes: [RouteIntelligenceEngine.OnRouteFix] = []
    private(set) var currentARTCC: ARTCCBoundary?
    private(set) var divertCandidates: [RouteIntelligenceEngine.DivertCandidate] = []

    private var engine: FlightEstimationEngine?
    private var runTask: Task<Void, Never>?

    // MARK: - Aircraft data endpoint (Phase 3b)

    private var ifeDataBox: IFEDataBox?
    private var ifePollingTask: Task<Void, Never>?

    /// Starts a background probe loop and returns the box `Estimator`'s
    /// `ifeLookup` closure reads from. ROADMAP 3b: "failure costs nothing" -- a
    /// probe cycle that finds nothing just leaves the box at whatever it last held
    /// (or `nil`), and the next sample's `outsideAir` reports `.unavailable`
    /// exactly like any other channel with no producer, never a stale value passed
    /// off as current.
    private func startIFEPolling() -> IFEDataBox {
        let box = IFEDataBox()
        let prober = IFEProber(fetch: { target in
            var request = URLRequest(url: target.url)
            // Short and non-negotiable: most of these targets won't exist on most
            // flights, and the default 60s URLSession timeout would make a full
            // probe cycle (four targets) take minutes instead of seconds.
            request.timeoutInterval = 3
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        })
        ifePollingTask = Task {
            while !Task.isCancelled {
                let reading = await prober.probe()
                box.set(reading?.asOutsideAirData())
                try? await Task.sleep(for: .seconds(15))
            }
        }
        return box
    }

    private func stopIFEPolling() {
        ifePollingTask?.cancel()
        ifePollingTask = nil
        ifeDataBox = nil
    }

    // MARK: - Passenger discovery (Phase 3a)

    private var discoveryEngine: PassengerDiscoveryEngine?
    private var bleController: BLEDiscoveryController?
    private var multipeerTransport: MultipeerAvatarTransport?

    /// ROADMAP 3a: "entirely opt-in and user-initiated. A dedicated screen the
    /// user deliberately opens." Called only from `DiscoverySurface`'s `onAppear`
    /// -- nothing else in the app starts advertising or scanning.
    func startDiscovery() {
        guard discoveryEngine == nil else { return }

        let sessionID = BeaconPayload.freshSessionID()
        let ble = BLEDiscoveryController()
        let multipeer = MultipeerAvatarTransport(mySessionID: sessionID)
        ble.updateLocalRecord(currentHandshakeRecord())
        ble.onExchangeRequestReceived = { [weak self] peerID in
            Task { @MainActor in
                try? await self?.discoveryEngine?.receiveExchangeRequest(from: peerID)
            }
        }

        let engine = PassengerDiscoveryEngine(
            advertiser: ble, scanner: ble, handshakeTransport: ble, bulkTransport: multipeer,
            myPayload: BeaconPayload(sessionID: sessionID)
        )
        bleController = ble
        multipeerTransport = multipeer
        discoveryEngine = engine

        Task {
            await engine.start()
            multipeer.start()
        }
    }

    func stopDiscovery() {
        let engine = discoveryEngine
        let multipeer = multipeerTransport
        discoveryEngine = nil
        bleController = nil
        multipeerTransport = nil
        Task {
            await engine?.stop()
            multipeer?.stop()
        }
    }

    func discoveredPeers() async -> [DiscoveredPeer] {
        await discoveryEngine?.discoveredPeers ?? []
    }

    func requestProfileExchange(with peerID: UInt64) async throws {
        try await discoveryEngine?.requestProfileExchange(with: peerID)
    }

    /// No avatar picker exists yet (Phase 2's `UserProfile` has no image field), so
    /// `avatarHash` is always `nil` here -- honest absence, not a stub. The
    /// hash-keyed fetch-once mechanism (`AvatarCache`) is fully built and tested;
    /// only the "attach a photo to your profile" UI is the missing piece, and it's
    /// a natural next addition, not a redesign.
    private func currentHandshakeRecord() -> HandshakeRecord {
        HandshakeRecord(
            displayName: profile.displayName.isEmpty ? "Contrail user" : profile.displayName,
            flightsLogged: generatedProfileStats.flightsLogged,
            homeBaseICAO: profile.homeBaseICAO,
            avatarHash: nil
        )
    }

    // MARK: - Identity (Phase 2)

    /// The freeform half of a profile -- what the pilot writes about themselves.
    /// `loadProfile()` populates this at launch; `updateProfile(_:)` is the only
    /// writer, so every edit is persisted the same way the log/manifest are: to
    /// local storage, immediately, with no separate "save" step to forget.
    private(set) var profile: UserProfile = .empty
    private let profileStore = ProfileStore(directory: AppModel.profileDirectory())

    /// The generated half -- computed from every logged flight, never user-edited.
    /// Not kept continuously up to date: recomputing means reading every flight's
    /// full NDJSON log, which is cheap for the handful of flights an early user has
    /// but not something to redo on every view update, so it's an explicit refresh
    /// like `FlightLogSurface`'s own `refresh()`.
    private(set) var generatedProfileStats: GeneratedProfileStats = .empty

    func loadProfile() {
        profile = profileStore.load()
    }

    func updateProfile(_ profile: UserProfile) {
        self.profile = profile
        try? profileStore.save(profile)
    }

    func refreshGeneratedProfileStats() {
        let flights: [GeneratedProfileCompiler.FlightData] = FlightLogStore.listFlights().compactMap { summary in
            guard let manifest = summary.manifest,
                  let records = try? FlightLogStore.loadRecords(in: summary.directory) else { return nil }
            return GeneratedProfileCompiler.FlightData(manifest: manifest, records: records)
        }
        generatedProfileStats = GeneratedProfileCompiler.compile(from: flights)
    }

    private static func profileDirectory() -> URL {
        let documents = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("Profile", isDirectory: true)
    }

    // MARK: - Offline basemap (§5.2)

    /// The XYZ tile URL template MapSurface's style JSON points at, once the local
    /// PMTiles-serving HTTP server is up. `nil` until `startMapServer()` completes --
    /// MapSurface shows a loading state rather than pointing MapLibre at a dead port.
    private(set) var mapTileURLTemplate: String?
    private var mapServer: PMTilesHTTPServer?

    /// Starts the loopback-only HTTP server that serves the bundled PMTiles basemap
    /// (see `PMTilesHTTPServer`'s own doc comment for why this exists instead of the
    /// `pmtiles://` custom URL scheme). Called once at launch, same as
    /// `verifyBundledAssets()` -- this is itself a bundled-asset verification: if the
    /// file is missing or the server can't bind loopback, the map surface reports that
    /// honestly instead of showing a blank tile grid.
    func startMapServer() async {
        do {
            let url = try BundledDatasets.basemapURL()
            let server = try PMTilesHTTPServer(pmtilesFileURL: url)
            try await server.start()
            guard let port = await server.port else {
                lastLogError = "Map server started but reported no port."
                return
            }
            mapServer = server
            mapTileURLTemplate = "http://127.0.0.1:\(port)/tiles/{z}/{x}/{y}.pbf"
        } catch {
            lastLogError = "Could not start the offline basemap server: \(error)"
        }
    }

    /// Loads and verifies the bundled datasets. Called once at launch — the
    /// pre-flight screen reads `airportAssetStatus`/`placeAssetStatus` directly
    /// rather than re-triggering verification itself.
    func verifyBundledAssets() {
        do {
            let index = try BundledDatasets.loadAirportIndex()
            airportIndex = index
            airportAssetStatus = .verified(recordCount: index.count)
        } catch {
            airportAssetStatus = .failed(String(describing: error))
        }

        do {
            let index = try BundledDatasets.loadPlaceIndex()
            placeIndex = index
            placeAssetStatus = .verified(recordCount: index.count)
        } catch {
            placeAssetStatus = .failed(String(describing: error))
        }

        do {
            let index = try BundledDatasets.loadNavFixIndex()
            navFixIndex = index
            navFixAssetStatus = .verified(recordCount: index.count)
        } catch {
            navFixAssetStatus = .failed(String(describing: error))
        }

        do {
            let index = try BundledDatasets.loadARTCCBoundaryIndex()
            artccIndex = index
            artccAssetStatus = .verified(recordCount: index.count)
        } catch {
            artccAssetStatus = .failed(String(describing: error))
        }
    }

    /// Resolves an ICAO code against the bundled airport index, for the pre-flight
    /// form's origin/destination fields.
    func airport(icao: String) -> AirportRecord? {
        airportIndex?.airport(icao: icao)
    }

    /// The same bundled ARTCC boundary index `RouteIntelligenceEngine` uses live,
    /// exposed read-only for `InsightsSurface`'s `AirspaceHistoryCompiler` call --
    /// Phase 4 reuses the dataset rather than loading a second copy of it.
    func artccBoundaryIndex() -> ARTCCBoundaryIndex? {
        artccIndex
    }

    /// `origin`/`destination` are the resolved `AirportRecord`s the pre-flight form
    /// looked up, not just the `Coordinate`s `FlightPlan` carries -- the manifest
    /// (§6: "fully self-describing years later with no network") needs the ICAO/IATA
    /// codes and elevation that `FlightPlan` deliberately doesn't retain.
    func startFlight(
        _ plan: FlightPlan, origin: AirportRecord, destination: AirportRecord,
        seatPosition: SeatPosition? = nil
    ) {
        stopFlight()

        flightPlan = plan
        originAirport = origin
        destinationAirport = destination
        isFlightActive = true
        lastLogError = nil
        photoRingBuffer.reset()

        let noPlaceLookup: @Sendable (Coordinate) -> BearingToPlace? = { _ in nil }
        let nearestPlace = placeIndex?.nearestPlaceLookup() ?? noPlaceLookup
        let source = LiveSensorSource()

        let directory = try? flightDirectory(for: plan)
        currentFlightDirectory = directory

        // Constructed here, handed off once, and never touched by AppModel again --
        // the engine owns its full lifecycle (see FlightEstimationEngine.run's own
        // doc comment on why two isolation domains must not share this instance).
        let writer = directory.flatMap { try? makeLogWriter(for: plan, flightDirectory: $0) }
        if writer == nil {
            lastLogError = "Could not open a log file for this flight."
        }

        if let directory {
            writeManifest(
                flightID: Self.flightID(for: plan), flightDirectory: directory,
                plan: plan, origin: origin, destination: destination, seatPosition: seatPosition
            )
        }

        if let airportIndex, let navFixIndex, let artccIndex {
            let intelligence = RouteIntelligenceEngine(
                airportIndex: airportIndex, navFixIndex: navFixIndex, artccIndex: artccIndex, flightPlan: plan
            )
            routeIntelligence = intelligence
            onRouteFixes = intelligence.onRouteFixes()
        }

        let forecastBox = ForecastCacheBox()
        forecastCacheBox = forecastBox
        if !gribStreamAPIToken.isEmpty {
            Task { await fetchForecast(for: plan, into: forecastBox) }
        }

        let ifeBox = startIFEPolling()
        ifeDataBox = ifeBox

        let engine = FlightEstimationEngine(
            flightPlan: plan, source: source, nearestPlace: nearestPlace,
            forecastLookup: { [forecastBox] alongTrackFlown, altitudeMetres, time in
                forecastBox.value(alongTrackFlown: alongTrackFlown, altitudeMetres: altitudeMetres, time: time)
            },
            ifeLookup: { [ifeBox] in ifeBox.value() },
            logWriter: writer
        )
        self.engine = engine

        runTask = Task {
            await engine.run(
                onUpdate: { [weak self] output, statistics in
                    self?.handle(output, statistics)
                },
                onLogError: { [weak self] message in
                    self?.lastLogError = message
                }
            )
        }
    }

    func stopFlight() {
        runTask?.cancel()
        runTask = nil
        engine = nil
        isFlightActive = false
        originAirport = nil
        destinationAirport = nil
        currentFlightDirectory = nil
        routeIntelligence = nil
        onRouteFixes = []
        currentARTCC = nil
        divertCandidates = []
        forecastCacheBox = nil
        forecastFetchStatus = .idle
        stopIFEPolling()
    }

    /// §4.2's "pre-flight-side slice," fetched once at flight start while there's
    /// still connectivity to reach GribStream at all -- the result populates
    /// `into` (read continuously from `FlightEstimationEngine`'s own actor), not a
    /// stored property this method returns synchronously, since the whole point is
    /// that a flight already in progress by the time this completes must not block
    /// on it.
    private func fetchForecast(for plan: FlightPlan, into box: ForecastCacheBox) async {
        forecastFetchStatus = .fetching
        do {
            // No actual cruise-altitude input exists in 1.0's manual pre-flight
            // form -- a fixed, generously-high assumption (FL380) keeps the
            // fetched level range covering a typical narrow-body cruise without
            // needing a new form field for this one subphase.
            let forecastPlan = try RouteForecastPlan(
                flightPlan: plan, cruiseAltitudeMetres: 11_582,
                times: [plan.scheduledDeparture, plan.scheduledArrival]
            )
            let request = try GTGForecastClient.buildRequest(for: forecastPlan, apiToken: gribStreamAPIToken)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                forecastFetchStatus = .failed("Forecast request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
                return
            }
            let samples = try GTGForecastClient.parse(data, plan: forecastPlan)
            box.set(RouteForecastCache(plan: forecastPlan, samples: samples))
            forecastFetchStatus = .succeeded(sampleCount: samples.count)
        } catch {
            forecastFetchStatus = .failed("Could not fetch the turbulence forecast: \(error)")
        }
    }

    private func handle(_ output: EstimatorOutput, _ statistics: FlightStatisticsSnapshot) {
        latestOutput = output
        latestStatistics = statistics
        photoRingBuffer.append(output)

        guard let routeIntelligence, let position = output.position.fused.value else { return }
        let altitudeMSL = output.position.altitudeGPS.value
        currentARTCC = routeIntelligence.currentARTCC(at: position, altitudeMSL: altitudeMSL)
        divertCandidates = altitudeMSL.map {
            routeIntelligence.divertCandidates(at: position, altitudeMSL: $0)
        } ?? []
    }

    /// §6: `Flights/<flightID>/`, one directory per flight, in the app's Documents
    /// directory -- `manifest.json` and `samples.ndjson` both live here. iCloud
    /// replication (§6's "local storage is the source of truth, iCloud is
    /// replication") is 1.0's own scope but not built in this pass — see the
    /// session's own deferral notes; local storage alone is still complete and
    /// crash-safe on its own.
    private func flightDirectory(for plan: FlightPlan) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return documents
            .appendingPathComponent("Flights", isDirectory: true)
            .appendingPathComponent(Self.flightID(for: plan), isDirectory: true)
    }

    private func makeLogWriter(for plan: FlightPlan, flightDirectory: URL) throws -> NDJSONLogWriter {
        try FileManager.default.createDirectory(at: flightDirectory, withIntermediateDirectories: true)
        return try NDJSONLogWriter(fileURL: flightDirectory.appendingPathComponent("samples.ndjson"))
    }

    private static func flightID(for plan: FlightPlan) -> String {
        "\(plan.flightNumber)-\(dateStamp(for: plan.scheduledDeparture))"
    }

    /// Device-local, not `ISO8601DateFormatter`'s UTC default -- there's no airport
    /// timezone dataset yet (that's 1.4's job), but the phone's own clock at the gate
    /// *is* the origin's local time at the moment a flight is started, which is a
    /// closer match to the manifest's documented "local to origin" than UTC would be.
    private static func dateStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Best-effort: a missing or unwritable manifest doesn't stop the flight from
    /// being logged (`samples.ndjson` is the load-bearing artifact), it just leaves
    /// that flight's log less self-describing later. Surfaced via `lastLogError`
    /// like any other non-fatal logging problem.
    private func writeManifest(
        flightID: String, flightDirectory: URL, plan: FlightPlan,
        origin: AirportRecord, destination: AirportRecord, seatPosition: SeatPosition?
    ) {
        do {
            let manifest = FlightManifest(
                flightID: flightID,
                app: .init(version: appVersion, build: appBuild, phase: "1.0"),
                device: .init(model: Self.deviceModelIdentifier(), os: Self.osVersionString()),
                resolution: .init(provider: "manual", resolvedAt: Date()),
                flight: .init(
                    number: plan.flightNumber,
                    date: Self.dateStamp(for: plan.scheduledDeparture),
                    origin: Self.airportInfo(from: origin),
                    destination: Self.airportInfo(from: destination),
                    scheduled: .init(
                        departure: plan.scheduledDeparture, arrival: plan.scheduledArrival,
                        blockTime: plan.scheduledBlockTime
                    ),
                    aircraft: .init(icaoType: plan.aircraftICAOType, registration: plan.aircraftRegistration),
                    filedRoute: nil,
                    seatPosition: seatPosition
                ),
                assets: try bundledAssetInfos(),
                forecast: nil,
                sensorSource: "live"
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: flightDirectory.appendingPathComponent("manifest.json"), options: .atomic
            )
        } catch {
            lastLogError = "Could not write flight manifest: \(error)"
        }
    }

    /// No timezone dataset exists yet (that's 1.4's job) -- `timezone: nil` is
    /// honest absence, not a placeholder.
    private static func airportInfo(from record: AirportRecord) -> FlightManifest.AirportInfo {
        .init(
            icao: record.icao, iata: record.iata, coordinate: record.coordinate,
            elevation: record.elevationMetres, timezone: nil
        )
    }

    private func bundledAssetInfos() throws -> [FlightManifest.AssetInfo] {
        let files: [(kind: String, id: String, name: String, ext: String)] = [
            ("airports", "ourairports-bundled", "airports", "bin"),
            ("places", "geonames-bundled", "places", "bin"),
            ("basemap", "contrail-world-z0-6", "basemap-z0-6", "pmtiles"),
            ("navfixes", "nasr-navfixes-2026-08-06", "navfixes", "bin"),
            ("artcc", "nasr-artcc-2026-08-06", "artcc", "bin"),
        ]
        return try files.map { file in
            let data = try Data(contentsOf: BundledDatasets.assetURL(named: file.name, extension: file.ext))
            return FlightManifest.AssetInfo(
                kind: file.kind, id: file.id, bytes: data.count,
                sha256: Self.sha256Hex(of: data), verified: true
            )
        }
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    private static func osVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// The hardware identifier (e.g. `"iPhone17,1"`), not `UIDevice.current.model`'s
    /// generic `"iPhone"` -- `uname()`'s `machine` field is the only way to get it
    /// without importing UIKit. On the Simulator, `uname()` reports the *host Mac's*
    /// architecture (`"arm64"`) instead, since the simulated app is a native macOS
    /// process -- confirmed by inspecting a real manifest written from the
    /// simulator during this session. `SIMULATOR_MODEL_IDENTIFIER` is the
    /// environment variable Simulator.app sets with the actually-simulated device's
    /// real hardware identifier, and takes priority when present.
    private static func deviceModelIdentifier() -> String {
        if let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulatorModel
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            let nullIndex = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[..<nullIndex], as: UTF8.self)
        }
    }
}
