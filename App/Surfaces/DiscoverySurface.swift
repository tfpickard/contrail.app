import SwiftUI
import ContrailDiscovery

/// ROADMAP 3a: "entirely opt-in and user-initiated. A dedicated screen the user
/// deliberately opens." This is that screen -- `AppModel.startDiscovery()`/
/// `stopDiscovery()` are called only from `onAppear`/`onDisappear` here, nowhere
/// else in the app.
struct DiscoverySurface: View {
    @Environment(AppModel.self) private var model

    @State private var peers: [DiscoveredPeer] = []
    @State private var refreshTask: Task<Void, Never>?
    @State private var actionError: String?

    var body: some View {
        List {
            Section {
                Label(
                    "Advertising your presence reveals only that you run Contrail. "
                    + "Nobody sees your name, stats, or photo until you and they "
                    + "both choose to exchange profiles.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if peers.isEmpty {
                ContentUnavailableView(
                    "Looking For Fellow Passengers", systemImage: "person.2.wave.2",
                    description: Text("Nearby Contrail users appear here automatically.")
                )
            } else {
                ForEach(peers) { peer in
                    peerRow(peer)
                }
            }

            if let actionError {
                Section {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(ContrailSignal.amber)
                }
            }
        }
        .navigationTitle("Nearby Passengers")
        .onAppear {
            model.startDiscovery()
            startPolling()
        }
        .onDisappear {
            refreshTask?.cancel()
            model.stopDiscovery()
        }
    }

    @ViewBuilder
    private func peerRow(_ peer: DiscoveredPeer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let record = peer.handshakeRecord {
                Text(record.displayName).font(.headline)
                Text(
                    "\(record.flightsLogged) flights logged"
                    + (record.homeBaseICAO.map { " · based at \($0)" } ?? "")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fellow passenger").font(.headline)
                        statusLabel(peer.disclosure)
                    }
                    Spacer()
                    if peer.disclosure != .mutuallyAccepted {
                        Button(peer.disclosure == .requestedByThem ? "Accept" : "Request") {
                            Task { await requestExchange(peer.id) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(peer.disclosure == .requestedByMe)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusLabel(_ state: DisclosureState) -> some View {
        switch state {
        case .presenceOnly:
            Text("Nearby").font(.caption).foregroundStyle(.secondary)
        case .requestedByMe:
            Text("Waiting for them to accept…").font(.caption).foregroundStyle(.secondary)
        case .requestedByThem:
            Text("Wants to exchange profiles").font(.caption).foregroundStyle(ContrailSignal.cyan)
        case .mutuallyAccepted:
            Text("Exchanged").font(.caption).foregroundStyle(ContrailSignal.green)
        }
    }

    private func requestExchange(_ peerID: UInt64) async {
        do {
            try await model.requestProfileExchange(with: peerID)
            await refreshPeers()
        } catch {
            actionError = "Could not reach that passenger: \(error)"
        }
    }

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshPeers()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refreshPeers() async {
        peers = await model.discoveredPeers()
    }
}
