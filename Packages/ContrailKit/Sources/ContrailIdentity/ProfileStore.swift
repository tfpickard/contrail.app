import Foundation

/// Reads/writes a single `UserProfile` as JSON. The directory is injected rather than
/// hardcoded to the app's Documents folder -- same reasoning as everything else in
/// ContrailKit staying Foundation-only and host-agnostic: this makes the store
/// testable against a temp directory with no app target involved.
public struct ProfileStore: Sendable {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("profile.json")
    }

    /// Missing or corrupt state both resolve to `.empty` -- a profile the user hasn't
    /// filled in yet and a profile file that failed to parse are indistinguishable
    /// from the caller's point of view, and both should show an editable blank form
    /// rather than throw.
    public func load() -> UserProfile {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        return (try? JSONDecoder().decode(UserProfile.self, from: data)) ?? .empty
    }

    public func save(_ profile: UserProfile) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: fileURL, options: .atomic)
    }
}
