import Foundation

struct AppInfo: Sendable, Equatable {
    let name: String
    let bundleID: String
    let url: URL
}

enum OWError: Error, CustomStringConvertible {
    case unknownExtension(String)
    case appNotFound(String)
    case launchServicesError(OSStatus)
    case defaultChangeNotApplied(ext: String, expected: String, actual: String?)
    case xattrReadError(Int32)
    case xattrWriteError(Int32)
    case noTarget

    var description: String {
        switch self {
        case .unknownExtension(let ext):
            return "Unknown file extension: .\(ext)"
        case .appNotFound(let name):
            return "Could not find app: \(name)"
        case .launchServicesError(let status):
            return "Launch Services error (OSStatus \(status))"
        case .defaultChangeNotApplied(let ext, let expected, let actual):
            let actualDescription = actual ?? "none"
            return "Default for .\(ext) did not change to \(expected) (Launch Services reports \(actualDescription))"
        case .xattrReadError(let code):
            return "Could not read file association (errno \(code))"
        case .xattrWriteError(let code):
            if code == EPERM || code == EACCES {
                return "Permission denied — grant Full Disk Access to Terminal in System Settings → Privacy & Security"
            }
            return "Could not write file association (errno \(code))"
        case .noTarget:
            return "No file extension or path provided"
        }
    }
}

extension OWError: LocalizedError {
    var errorDescription: String? { description }
}
