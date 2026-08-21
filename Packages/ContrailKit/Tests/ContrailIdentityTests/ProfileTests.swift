import Foundation
import Testing
@testable import ContrailIdentity

struct ProfileStoreTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("contrail-identity-test-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func missingFileLoadsAsEmpty() {
        let store = ProfileStore(directory: tempDirectory())
        #expect(store.load() == .empty)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)

        let profile = UserProfile(displayName: "Tom", homeBaseICAO: "KDEN", bio: "Window seat, always.")
        try store.save(profile)

        #expect(store.load() == profile)
    }

    @Test func savingTwiceOverwritesRatherThanAppends() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)

        try store.save(UserProfile(displayName: "First"))
        try store.save(UserProfile(displayName: "Second"))

        #expect(store.load().displayName == "Second")
    }

    @Test func corruptFileLoadsAsEmptyRatherThanThrowing() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("profile.json"))

        let store = ProfileStore(directory: directory)
        #expect(store.load() == .empty)
    }
}
