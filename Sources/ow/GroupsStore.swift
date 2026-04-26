import Foundation

struct GroupsData: Codable, Equatable {
    var customGroups: [String: CustomFileTypeGroup] = [:]
    var builtInCustomizations: [String: BuiltInGroupCustomization] = [:]
}

struct CustomFileTypeGroup: Codable, Equatable {
    var extensions: [String]
}

struct BuiltInGroupCustomization: Codable, Equatable {
    var appended: [String] = []
    var removed: [String] = []
}

enum GroupsStoreError: Error, LocalizedError {
    case groupAlreadyExists(String)
    case cannotCreateBuiltInGroup(String)
    case cannotDeleteBuiltInGroup(String)
    case unknownGroup(String)

    var errorDescription: String? {
        switch self {
        case .groupAlreadyExists(let name):
            return "Group already exists: \(name)"
        case .cannotCreateBuiltInGroup(let name):
            return "\(name) is a built-in group. Use append or remove to customize it."
        case .cannotDeleteBuiltInGroup(let name):
            return "\(name) is a built-in group and cannot be deleted."
        case .unknownGroup(let name):
            return "Unknown group: \(name)"
        }
    }
}

/// Persists user-managed group state to ~/Library/Application Support/ow/groups.json.
///
/// Built-in groups are intentionally kept in code so OW can improve them in
/// future releases. This store only records user intent layered over those
/// built-ins: custom groups, extensions appended to built-ins, and extensions
/// removed from built-ins. The effective group is computed at read time.
enum GroupsStore {
    private static var storeURL: URL {
        StorageSupport.appSupportFile("groups.json", envOverride: "OW_GROUPS_STORE")
    }

    static func load() -> GroupsData {
        guard let data = try? Data(contentsOf: storeURL) else {
            return GroupsData()
        }
        return (try? JSONDecoder().decode(GroupsData.self, from: data)) ?? GroupsData()
    }

    static func save(_ groups: GroupsData) throws {
        try StorageSupport.ensureParentDirectory(for: storeURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(groups)
        try data.write(to: storeURL, options: .atomic)
    }

    static func allGroups() -> [ResolvedFileTypeGroup] {
        let data = load()
        let builtIns = FileTypeGroup.all.map { resolveBuiltIn($0, customization: data.builtInCustomizations[$0.name]) }
        let custom = data.customGroups
            .map { name, group in
                ResolvedFileTypeGroup(
                    name: name,
                    description: "Custom file type group",
                    extensions: normalizedUnique(group.extensions),
                    source: .custom
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return builtIns + custom
    }

    static func group(named name: String) -> ResolvedFileTypeGroup? {
        let data = load()
        let normalizedName = FileTypeGroup.normalizedGroupName(name)

        if let builtIn = FileTypeGroup.builtInOrAlias(named: normalizedName) {
            return resolveBuiltIn(builtIn, customization: data.builtInCustomizations[builtIn.name])
        }

        guard let custom = data.customGroups[normalizedName] else {
            return nil
        }
        return ResolvedFileTypeGroup(
            name: normalizedName,
            description: "Custom file type group",
            extensions: normalizedUnique(custom.extensions),
            source: .custom
        )
    }

    static func createGroup(named name: String, extensions: [String]) throws -> ResolvedFileTypeGroup {
        let normalizedName = FileTypeGroup.normalizedGroupName(name)
        var data = load()

        if FileTypeGroup.builtInOrAlias(named: normalizedName) != nil {
            throw GroupsStoreError.cannotCreateBuiltInGroup(normalizedName)
        }
        if data.customGroups[normalizedName] != nil {
            throw GroupsStoreError.groupAlreadyExists(normalizedName)
        }

        data.customGroups[normalizedName] = CustomFileTypeGroup(extensions: normalizedUnique(extensions))
        try save(data)
        return try resolvedExistingGroup(named: normalizedName)
    }

    static func deleteGroup(named name: String) throws {
        let normalizedName = FileTypeGroup.normalizedGroupName(name)
        var data = load()

        if FileTypeGroup.builtInOrAlias(named: normalizedName) != nil {
            throw GroupsStoreError.cannotDeleteBuiltInGroup(normalizedName)
        }
        guard data.customGroups.removeValue(forKey: normalizedName) != nil else {
            throw GroupsStoreError.unknownGroup(normalizedName)
        }
        try save(data)
    }

    static func append(_ extensions: [String], toGroupNamed name: String) throws -> ResolvedFileTypeGroup {
        let normalizedName = FileTypeGroup.normalizedGroupName(name)
        let extensions = normalizedUnique(extensions)
        var data = load()

        if let builtIn = FileTypeGroup.builtInOrAlias(named: normalizedName) {
            var customization = data.builtInCustomizations[builtIn.name] ?? BuiltInGroupCustomization()
            let builtInExtensions = Swift.Set(builtIn.extensions)

            // Appending an extension that had been removed means "include it
            // again". If it is already built in, no appended entry is needed.
            customization.removed.removeAll { extensions.contains($0) }
            for ext in extensions where !builtInExtensions.contains(ext) && !customization.appended.contains(ext) {
                customization.appended.append(ext)
            }
            data.builtInCustomizations[builtIn.name] = customization
            try save(data)
            return try resolvedExistingGroup(named: builtIn.name)
        }

        guard var custom = data.customGroups[normalizedName] else {
            throw GroupsStoreError.unknownGroup(normalizedName)
        }
        for ext in extensions where !custom.extensions.contains(ext) {
            custom.extensions.append(ext)
        }
        data.customGroups[normalizedName] = custom
        try save(data)
        return try resolvedExistingGroup(named: normalizedName)
    }

    static func remove(_ extensions: [String], fromGroupNamed name: String) throws -> ResolvedFileTypeGroup {
        let normalizedName = FileTypeGroup.normalizedGroupName(name)
        let extensions = normalizedUnique(extensions)
        var data = load()

        if let builtIn = FileTypeGroup.builtInOrAlias(named: normalizedName) {
            var customization = data.builtInCustomizations[builtIn.name] ?? BuiltInGroupCustomization()
            let builtInExtensions = Swift.Set(builtIn.extensions)

            // Built-in removals are filters. They do not edit the shipped
            // group; they record extensions to subtract when resolving it.
            customization.appended.removeAll { extensions.contains($0) }
            for ext in extensions where builtInExtensions.contains(ext) && !customization.removed.contains(ext) {
                customization.removed.append(ext)
            }
            data.builtInCustomizations[builtIn.name] = customization
            try save(data)
            return try resolvedExistingGroup(named: builtIn.name)
        }

        guard var custom = data.customGroups[normalizedName] else {
            throw GroupsStoreError.unknownGroup(normalizedName)
        }
        custom.extensions.removeAll { extensions.contains($0) }
        data.customGroups[normalizedName] = custom
        try save(data)
        return try resolvedExistingGroup(named: normalizedName)
    }

    static func customization(forBuiltInGroup name: String) -> BuiltInGroupCustomization? {
        let normalizedName = FileTypeGroup.normalizedGroupName(name)
        guard let builtIn = FileTypeGroup.builtInOrAlias(named: normalizedName) else {
            return nil
        }
        return load().builtInCustomizations[builtIn.name]
    }

    private static func resolvedExistingGroup(named name: String) throws -> ResolvedFileTypeGroup {
        guard let group = group(named: name) else {
            throw GroupsStoreError.unknownGroup(name)
        }
        return group
    }

    private static func resolveBuiltIn(
        _ group: FileTypeGroup,
        customization: BuiltInGroupCustomization?
    ) -> ResolvedFileTypeGroup {
        let customization = customization ?? BuiltInGroupCustomization()
        let removed = Swift.Set(normalizedUnique(customization.removed))
        let extensions = normalizedUnique(group.extensions + customization.appended)
            .filter { !removed.contains($0) }

        return ResolvedFileTypeGroup(
            name: group.name,
            description: group.description,
            extensions: extensions,
            source: .builtIn
        )
    }

    private static func normalizedUnique(_ extensions: [String]) -> [String] {
        var seen: Swift.Set<String> = []
        var result: [String] = []

        for ext in extensions {
            let normalized = LaunchServicesClient.normalizedExtension(ext)
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }
}

struct ResolvedFileTypeGroup: Equatable {
    enum Source: Equatable {
        case builtIn
        case custom
    }

    let name: String
    let description: String
    let extensions: [String]
    let source: Source
}
