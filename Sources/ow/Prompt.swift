import Foundation

/// Simple helpers for reading y/N and typed-phrase confirmations from the user.
enum Prompt {

    /// Prompts the user with `question [y/N]` and returns true only for a
    /// clear affirmative answer.
    static func confirm(_ question: String) -> Bool {
        print("\(question) [y/N] ", terminator: "")
        guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        let answer = line.lowercased()
        return answer == "y" || answer == "yes"
    }

    /// Prompts the user to type an exact phrase before a destructive action
    /// proceeds. Returns true only if the typed input matches `phrase` exactly.
    static func requirePhrase(_ message: String, phrase: String) -> Bool {
        print(message)
        print("Type \u{1B}[1m\(phrase)\u{1B}[0m to continue: ", terminator: "")
        guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return line == phrase
    }
}
