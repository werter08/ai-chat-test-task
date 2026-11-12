import Foundation

/// Local, user-editable personalization. Stored in UserDefaults (also bound via @AppStorage in Settings).
struct UserProfile: Equatable {
    static let nameKey = "profileName"
    static let instructionsKey = "profileInstructions"
    static let maxInstructionsLength = 500

    var name = ""
    var instructions = ""

    static var current: UserProfile {
        let defaults = UserDefaults.standard
        return UserProfile(
            name: defaults.string(forKey: nameKey) ?? "",
            instructions: defaults.string(forKey: instructionsKey) ?? ""
        )
    }
}
