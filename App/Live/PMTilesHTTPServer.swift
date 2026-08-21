import Foundation
import Network
import ContrailMap

/// Serves the bundled PMTiles basemap over plain HTTP on loopback only
/// (127.0.0.1) — the reliable, standard XYZ tile URL path MapLibre has always
/// supported, chosen specifically to sidestep a documented, unresolved-as-of-this-
/// session iOS bug where MapLibre's `pmtiles://` custom URL scheme is rejected by
/// `NSURL` ("unsupported URL"). See this session's own build notes for the decision.
///
/// A minimal, single-purpose HTTP/1.1 server — enough to serve `GET
/// /tiles/{z}/{x}/{y}.pbf` correctly, nothing more. Never binds to a non-loopback
/// address, so it's not reachable from outside the device regardless of network
/// state.
actor PMTilesHTTPServer {
    enum ServerError: Error {
        case malformedRequest
    }

    /// `NWListener.stateUpdateHandler` fires on the listener's own dispatch queue,
    /// which Swift 6 can't statically prove never races with the actor -- so the
    /// "did we already resume this continuation" flag can't be a plain captured
    /// `var`. A lock-guarded box is the standard escape hatch for exactly this
    /// one-time handoff, same justification as `NDJSONLogWriter`'s
    /// `@unchecked Sendable`.
    private final class ResumeGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false
        func tryResume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if didResume { return false }
            didResume = true
            return true
        }
    }

    private let reader: PMTilesReader
    private var listener: NWListener?
    private(set) var port: UInt16?

    init(pmtilesFileURL: URL) throws {
        self.reader = try PMTilesReader(fileURL: pmtilesFileURL)
    }

    /// Starts listening and returns once a port is bound. Safe to call once per
    /// server instance.
    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        // Loopback only -- MapLibre's own process is the only intended client.
        parameters.prohibitedInterfaceTypes = [.cellular, .wifi, .wiredEthernet]

        let listener = try NWListener(using: parameters)
        self.listener = listener

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumeGuard = ResumeGuard()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    Task { await self?.recordPort(listener.port?.rawValue) }
                    continuation.resume()
                case .failed(let error):
                    guard resumeGuard.tryResume() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.handle(connection) }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func recordPort(_ value: UInt16?) {
        port = value
    }

    private func handle(_ connection: NWConnection) async {
        connection.start(queue: .main)
        do {
            let request = try await receiveRequestLine(connection)
            guard let (z, x, y) = Self.parseTilePath(request) else {
                try await send(status: "404 Not Found", body: Data(), contentType: "text/plain", on: connection)
                connection.cancel()
                return
            }
            let tile = try await reader.tile(z: z, x: x, y: y)
            if let tile {
                try await send(status: "200 OK", body: tile, contentType: "application/x-protobuf", on: connection)
            } else {
                try await send(status: "404 Not Found", body: Data(), contentType: "text/plain", on: connection)
            }
        } catch {
            connection.cancel()
        }
        connection.cancel()
    }

    /// Reads just enough to get the HTTP request line (`GET /path HTTP/1.1`) —
    /// this server never needs request headers or a body, so it doesn't parse them.
    private func receiveRequestLine(_ connection: NWConnection) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let text = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: ServerError.malformedRequest)
                    return
                }
                let firstLine = text.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first
                continuation.resume(returning: String(firstLine ?? ""))
            }
        }
    }

    /// Parses `GET /tiles/{z}/{x}/{y}.pbf HTTP/1.1` -> (z, x, y).
    private static func parseTilePath(_ requestLine: String) -> (UInt8, UInt64, UInt64)? {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        let path = parts[1]
        guard path.hasPrefix("/tiles/"), path.hasSuffix(".pbf") else { return nil }
        let trimmed = path.dropFirst("/tiles/".count).dropLast(".pbf".count)
        let components = trimmed.split(separator: "/")
        guard components.count == 3,
              let z = UInt8(components[0]), let x = UInt64(components[1]), let y = UInt64(components[2])
        else { return nil }
        return (z, x, y)
    }

    private func send(status: String, body: Data, contentType: String, on connection: NWConnection) async throws {
        var headerText = "HTTP/1.1 \(status)\r\n"
        headerText += "Content-Type: \(contentType)\r\n"
        headerText += "Content-Length: \(body.count)\r\n"
        headerText += "Access-Control-Allow-Origin: *\r\n"
        headerText += "Connection: close\r\n\r\n"

        var responseData = Data(headerText.utf8)
        responseData.append(body)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: responseData, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
