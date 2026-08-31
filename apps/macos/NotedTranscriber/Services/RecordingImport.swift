import Foundation

enum RecordingImport {
    static let supportedExtensions: Set<String> = [
        "aac", "aiff", "aif", "caf", "flac", "m4a", "mp3", "ogg", "opus", "wav", "wma",
        "3gp", "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm"
    ]

    static func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func fingerprint(for url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(url.standardizedFileURL.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }
}
