import Darwin
import Foundation

/// A single pattern-to-app rule stored in the rules file.
struct Rule: Codable, Equatable {
    var pattern: String   // e.g. "Makefile" or "*.env"
    var appName: String
    var bundleID: String
    var appPath: String

    var appInfo: AppInfo {
        AppInfo(name: appName, bundleID: bundleID, url: URL(fileURLWithPath: appPath))
    }

    /// True if the pattern contains wildcard characters.
    var isGlob: Bool {
        pattern.contains("*") || pattern.contains("?") || pattern.contains("[")
    }

    /// Returns true if the given filename matches this rule.
    func matches(filename: String) -> Bool {
        if isGlob {
            return fnmatch(pattern, filename, 0) == 0
        } else {
            return pattern == filename
        }
    }
}

/// Persists rules to ~/Library/Application Support/ow/rules.json.
enum RulesStore {

    static var storeURL: URL {
        StorageSupport.appSupportFile("rules.json")
    }

    static func load() -> [Rule] {
        guard
            let data = try? Data(contentsOf: storeURL),
            let rules = try? JSONDecoder().decode([Rule].self, from: data)
        else { return [] }
        return rules
    }

    static func save(_ rules: [Rule]) throws {
        try StorageSupport.ensureParentDirectory(for: storeURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rules)
        try data.write(to: storeURL, options: .atomic)
    }

    /// Adds or replaces the rule for the given pattern.
    static func add(_ rule: Rule) throws {
        var rules = load()
        rules.removeAll { $0.pattern == rule.pattern }
        rules.append(rule)
        try save(rules)
    }

    /// Removes the rule for the given pattern. Returns true if one was removed.
    @discardableResult
    static func remove(pattern: String) throws -> Bool {
        var rules = load()
        let before = rules.count
        rules.removeAll { $0.pattern == pattern }
        guard rules.count < before else { return false }
        try save(rules)
        return true
    }
}
