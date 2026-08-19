import Foundation

final class LocalRecordingStore {
    let recordingsDirectory: URL
    private let indexURL: URL
    private let backupURL: URL
    private let fileManager: FileManager
    private(set) var lastLoadWarning: String?

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        let base: URL
        if let baseDirectory {
            base = baseDirectory
        } else {
            base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        recordingsDirectory = base.appendingPathComponent("MemoryGarden/Recordings", isDirectory: true)
        let metadataDirectory = base.appendingPathComponent("MemoryGarden", isDirectory: true)
        indexURL = metadataDirectory.appendingPathComponent("recordings.json")
        backupURL = metadataDirectory.appendingPathComponent("recordings.json.bak")
        try? fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    }

    func load() -> [LocalRecording] {
        lastLoadWarning = nil
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let values: [LocalRecording]

        if let data = try? Data(contentsOf: indexURL), let decoded = try? decoder.decode([LocalRecording].self, from: data) {
            values = decoded
        } else if let data = try? Data(contentsOf: backupURL), let decoded = try? decoder.decode([LocalRecording].self, from: data) {
            values = decoded
            lastLoadWarning = "The primary recording index was damaged, so Memory Garden restored the last known-good copy."
        } else {
            values = []
            if fileManager.fileExists(atPath: indexURL.path) || fileManager.fileExists(atPath: backupURL.path) {
                lastLoadWarning = "The recording index could not be read. Audio files were preserved for recovery."
            }
        }

        var recordings = values.map { recording in
            var migrated = recording
            migrated.fileName = safeFileName(recording.fileName, fallback: recording.id)
            migrated.localFileURL = recordingsDirectory.appendingPathComponent(migrated.fileName)
            if !fileManager.fileExists(atPath: migrated.localFileURL.path), migrated.serverSourceId == nil {
                migrated.state = .missingFile
                migrated.lastError = migrated.lastError ?? "The saved audio file is missing from this iPhone."
            } else if migrated.serverSourceId == nil && [.draft, .recording, .paused, .interrupted].contains(migrated.state) {
                migrated.state = .recovering
                migrated.lastError = migrated.lastError ?? "Recovered a recording after the app stopped unexpectedly."
            }
            return migrated
        }

        let indexedNames = Set(recordings.map(\.fileName))
        let orphanFiles = (try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in orphanFiles where isAudioFile(url) && !indexedNames.contains(url.lastPathComponent) {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            let recovered = LocalRecording(
                id: id,
                localFileURL: url,
                createdAt: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(),
                duration: 0,
                title: "Recovered Recording",
                state: .recovering,
                uploadAttempts: 0,
                serverSourceId: nil,
                byteSize: byteSize(of: url),
                bookmarks: [],
                lastError: "Recovered audio needs review before upload.",
                consentMode: "private_thought",
                consentAcknowledged: true
            )
            recordings.append(recovered)
        }

        return recordings.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ recordings: [LocalRecording]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        let data = try encoder.encode(recordings)
        let metadataDirectory = indexURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: indexURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: indexURL, to: backupURL)
        }

        let temporary = metadataDirectory.appendingPathComponent("recordings.json.tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        try? fileManager.removeItem(at: indexURL)
        try fileManager.moveItem(at: temporary, to: indexURL)
    }

    func newAudioURL(for id: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func byteSize(of url: URL) -> Int64 {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    func resolvedURL(for recording: LocalRecording) -> URL {
        recordingsDirectory.appendingPathComponent(safeFileName(recording.fileName, fallback: recording.id))
    }

    private func safeFileName(_ fileName: String, fallback id: UUID) -> String {
        let candidate = URL(fileURLWithPath: fileName).lastPathComponent
        guard !candidate.isEmpty, candidate != "." else { return "\(id.uuidString).m4a" }
        return candidate
    }

    private func isAudioFile(_ url: URL) -> Bool {
        ["m4a", "caf", "wav", "webm"].contains(url.pathExtension.lowercased())
    }
}
