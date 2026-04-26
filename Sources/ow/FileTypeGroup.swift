import Foundation

struct FileTypeGroup: Equatable {
    let name: String
    let description: String
    let extensions: [String]

    static let all: [FileTypeGroup] = [
        FileTypeGroup(
            name: "code",
            description: "Source code, scripts, config, and project text files",
            extensions: [
                "c", "cc", "cpp", "cs", "css", "go", "h", "hpp", "html", "java",
                "js", "json", "jsx", "kt", "lua", "m", "md", "php", "pl", "py",
                "rb", "rs", "sh", "swift", "toml", "ts", "tsx", "xml", "yaml", "yml",
            ]
        ),
        FileTypeGroup(
            name: "images",
            description: "Common bitmap, vector, and camera image files",
            extensions: [
                "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png",
                "raw", "svg", "tif", "tiff", "webp",
            ]
        ),
        FileTypeGroup(
            name: "video",
            description: "Common movie and video container files",
            extensions: [
                "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm", "wmv",
            ]
        ),
        FileTypeGroup(
            name: "audio",
            description: "Common audio files",
            extensions: [
                "aac", "aiff", "flac", "m4a", "mp3", "ogg", "opus", "wav",
            ]
        ),
        FileTypeGroup(
            name: "documents",
            description: "Common office, rich text, PDF, and ebook files",
            extensions: [
                "csv", "doc", "docx", "epub", "numbers", "ods", "odt", "pages",
                "pdf", "ppt", "pptx", "rtf", "xls", "xlsx",
            ]
        ),
        FileTypeGroup(
            name: "archives",
            description: "Common compressed files and package archives",
            extensions: [
                "7z", "bz2", "dmg", "gz", "pkg", "rar", "tar", "tgz", "xz", "zip",
            ]
        ),
    ]

    static func builtInOrAlias(named name: String) -> FileTypeGroup? {
        let normalizedName = normalizedGroupName(name)
        return all.first { group in
            group.name == normalizedName || aliases[normalizedName] == group.name
        }
    }

    static func named(_ name: String) -> FileTypeGroup? {
        builtInOrAlias(named: name)
    }

    static func normalizedGroupName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let aliases = [
        "archive": "archives",
        "document": "documents",
        "image": "images",
        "movie": "video",
        "movies": "video",
        "music": "audio",
        "picture": "images",
        "pictures": "images",
        "source": "code",
        "text": "code",
    ]
}
