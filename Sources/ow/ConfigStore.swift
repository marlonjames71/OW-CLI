import Foundation

enum QuarantinePolicy: String, Codable, CaseIterable {
    case warn
    case clear
    case ignore

    var description: String {
        switch self {
        case .warn:
            return "warn about quarantined files"
        case .clear:
            return "remove quarantine from files"
        case .ignore:
            return "do not warn or remove quarantine"
        }
    }
}

struct OWConfig: Codable, Equatable {
    var quarantine: QuarantinePolicy = .warn
}

/// Persists OW user preferences to ~/Library/Application Support/ow/config.json.
enum ConfigStore {

    static var storeURL: URL {
        StorageSupport.appSupportFile("config.json", envOverride: "OW_CONFIG_STORE")
    }

    static func load() -> OWConfig {
        guard
            let data = try? Data(contentsOf: storeURL),
            let config = try? JSONDecoder().decode(OWConfig.self, from: data)
        else {
            return OWConfig()
        }
        return config
    }

    static func save(_ config: OWConfig) throws {
        try StorageSupport.ensureParentDirectory(for: storeURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: storeURL, options: .atomic)
    }
}
