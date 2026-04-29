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
    case launchServicesDatabaseInvalid(String)
    case launchServicesRestoreFailed(writeError: String, restoreError: String)
    case notARegularFile(String)
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
        case .launchServicesDatabaseInvalid(let path):
            return "Launch Services database is invalid: \(path)"
        case .launchServicesRestoreFailed(let writeError, let restoreError):
            return "Launch Services write failed (\(writeError)), and restoring the backup also failed (\(restoreError))"
        case .notARegularFile(let path):
            return "Expected a file path, not a folder or missing path: \(path)"
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
