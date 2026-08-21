import Foundation

/// ROADMAP Phase 2 -- Identity: "Freeform profile section -- what you write about
/// yourself." Kept strictly separate from `GeneratedProfileStats` (the derived half)
/// so the two can never be confused: this one is self-reported and user-editable,
/// the other is computed from flight history and never is.
public struct UserProfile: Sendable, Codable, Equatable {
    public var displayName: String
    public var homeBaseICAO: String?
    public var bio: String

    public init(displayName: String = "", homeBaseICAO: String? = nil, bio: String = "") {
        self.displayName = displayName
        self.homeBaseICAO = homeBaseICAO
        self.bio = bio
    }

    public static let empty = UserProfile()
}
