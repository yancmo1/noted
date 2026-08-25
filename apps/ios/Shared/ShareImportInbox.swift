import Foundation
import UniformTypeIdentifiers

struct SharedImportManifest: Codable, Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let title: String
    let createdAt: Date
    let mimeType: String
    let byteSize: Int64
}

enum SharedImportInbox {
    static let appGroupID = "group.com.memorygarden.ios"

    static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func inboxURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?.appendingPathComponent("Noted/ShareInbox", isDirectory: true)
    }

    @discardableResult
    static func enqueue(
        fileURL: URL,
        title: String? = nil,
        mimeType: String? = nil,
        fileManager: FileManager = .default
    ) throws -> SharedImportManifest {
        guard let inbox = inboxURL(fileManager: fileManager) else { throw SharedImportInboxError.containerUnavailable }
        try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)

        let id = UUID()
        let extensionName = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension.lowercased()
        let storedFileName = "\(id.uuidString).\(extensionName)"
        let destination = inbox.appendingPathComponent(storedFileName)
        let temporary = inbox.appendingPathComponent(".\(id.uuidString).tmp")
        try fileManager.copyItem(at: fileURL, to: temporary)
        try fileManager.moveItem(at: temporary, to: destination)

        let manifest = SharedImportManifest(
            id: id,
            fileName: storedFileName,
            title: normalizedTitle(title, fileName: fileURL.lastPathComponent),
            createdAt: Date(),
            mimeType: mimeType ?? preferredMimeType(for: fileURL) ?? "audio/mp4",
            byteSize: byteSize(of: destination, fileManager: fileManager)
        )
        let manifestURL = inbox.appendingPathComponent("\(id.uuidString).json")
        do {
            try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        return manifest
    }

    static func pending(fileManager: FileManager = .default) -> [SharedImportManifest] {
        guard let inbox = inboxURL(fileManager: fileManager),
              let urls = try? fileManager.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { try? JSONDecoder().decode(SharedImportManifest.self, from: (try? Data(contentsOf: $0)) ?? Data()) }
            .filter { fileManager.fileExists(atPath: fileURL(for: $0, fileManager: fileManager)?.path ?? "") }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func fileURL(for manifest: SharedImportManifest, fileManager: FileManager = .default) -> URL? {
        inboxURL(fileManager: fileManager)?.appendingPathComponent(manifest.fileName)
    }

    static func remove(_ manifest: SharedImportManifest, fileManager: FileManager = .default) {
        guard let inbox = inboxURL(fileManager: fileManager) else { return }
        try? fileManager.removeItem(at: inbox.appendingPathComponent(manifest.fileName))
        try? fileManager.removeItem(at: inbox.appendingPathComponent("\(manifest.id.uuidString).json"))
    }

    private static func normalizedTitle(_ title: String?, fileName: String) -> String {
        let supplied = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !supplied.isEmpty { return supplied }
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "Imported recording" : stem
    }

    private static func preferredMimeType(for url: URL) -> String? {
        return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }

    private static func byteSize(of url: URL, fileManager: FileManager) -> Int64 {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}

enum SharedImportInboxError: LocalizedError {
    case containerUnavailable
    case fileUnavailable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable: "Noted could not access its shared import inbox. Open Noted once, then try sharing the recording again."
        case .fileUnavailable: "The shared recording is no longer available. Share it to Noted again from the source app."
        }
    }
}
