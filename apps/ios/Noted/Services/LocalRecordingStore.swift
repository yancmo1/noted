import Foundation

final class LocalRecordingStore {
    let recordingsDirectory: URL
    private let indexURL: URL
    private let backupURL: URL
    private let tombstoneURL: URL
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
        tombstoneURL = metadataDirectory.appendingPathComponent("recording-deletions.json")
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
            lastLoadWarning = "The primary recording index was damaged, so Noted restored the last known-good copy."
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

        let normalized = normalizeDuplicates(recordings)
        if normalized.count != recordings.count {
            recordings = normalized
            try? save(recordings)
        } else {
            recordings = normalized
        }

        let deletedIDs = deletedRecordingIDs()
        recordings.removeAll { deletedIDs.contains($0.id) }
        let indexedNames = Set(recordings.map(\.fileName))
        let indexedIDs = Set(recordings.map(\.id))
        let orphanFiles = (try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in orphanFiles where isAudioFile(url) && !indexedNames.contains(url.lastPathComponent) {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), !deletedIDs.contains(id), !indexedIDs.contains(id) else { continue }
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

    /// Removes duplicate metadata records without ever deleting an audio file.
    /// The most complete record wins, while bookmarks and useful metadata are merged.
    private func normalizeDuplicates(_ recordings: [LocalRecording]) -> [LocalRecording] {
        var grouped: [UUID: [LocalRecording]] = [:]
        for recording in recordings { grouped[recording.id, default: []].append(recording) }

        return grouped.values.compactMap { candidates in
            let ranked = candidates.sorted {
                let leftScore = completeness(of: $0)
                let rightScore = completeness(of: $1)
                if leftScore != rightScore { return leftScore > rightScore }
                if $0.finalizedAt != $1.finalizedAt { return ($0.finalizedAt ?? .distantPast) > ($1.finalizedAt ?? .distantPast) }
                return $0.fileName < $1.fileName
            }
            guard var best = ranked.first else { return nil }
            for candidate in ranked.dropFirst() {
                if candidate.duration > best.duration { best.duration = candidate.duration }
                if candidate.byteSize > best.byteSize { best.byteSize = candidate.byteSize }
                if best.title.isEmpty || best.title == "Untitled Recording", !candidate.title.isEmpty { best.title = candidate.title }
                if best.consentMode == "private_thought", candidate.consentMode != "private_thought" { best.consentMode = candidate.consentMode }
                best.consentAcknowledged = best.consentAcknowledged || candidate.consentAcknowledged
                best.uploadAttempts = max(best.uploadAttempts, candidate.uploadAttempts)
                if best.serverSourceId == nil { best.serverSourceId = candidate.serverSourceId }
                if best.finalizedAt == nil { best.finalizedAt = candidate.finalizedAt }
                if best.lastError == nil { best.lastError = candidate.lastError }
                if best.nextRetryAt == nil { best.nextRetryAt = candidate.nextRetryAt }
                best.bookmarks = mergeBookmarks(best.bookmarks, candidate.bookmarks)
            }
            best.bookmarks = mergeBookmarks([], best.bookmarks)
            return best
        }
    }

    private func completeness(of recording: LocalRecording) -> Int {
        var score = 0
        if fileManager.fileExists(atPath: recording.localFileURL.path) { score += 1000 }
        if recording.byteSize > 0 { score += 500 }
        if recording.finalizedAt != nil { score += 100 }
        if recording.serverSourceId != nil { score += 80 }
        if recording.duration > 0 { score += 40 }
        score += recording.bookmarks.count * 2
        if recording.title != "Untitled Recording" && recording.title != "Untitled Meeting" { score += 10 }
        score += recording.stateRank
        return score
    }

    private func mergeBookmarks(_ left: [LocalBookmark], _ right: [LocalBookmark]) -> [LocalBookmark] {
        var result: [UUID: LocalBookmark] = [:]
        for bookmark in left + right { result[bookmark.id] = bookmark }
        return result.values.sorted { $0.timestamp < $1.timestamp }
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

    func removeMetadata(for id: UUID) throws {
        let remaining = load().filter { $0.id != id }
        try save(remaining)
    }

    func markDeleted(_ recording: LocalRecording) throws {
        var tombstones = loadTombstones()
        let tombstone = RecordingDeletion(id: recording.id, serverSourceId: recording.serverSourceId)
        if !tombstones.contains(tombstone) { tombstones.append(tombstone) }
        try saveTombstones(tombstones)
    }

    func markDeleted(id: UUID, serverSourceId: String? = nil) throws {
        var tombstones = loadTombstones()
        let tombstone = RecordingDeletion(id: id, serverSourceId: serverSourceId)
        if !tombstones.contains(tombstone) { tombstones.append(tombstone) }
        try saveTombstones(tombstones)
    }

    func clearDeletion(for id: UUID) throws {
        try saveTombstones(loadTombstones().filter { $0.id != id })
    }

    func clearDeletion(forServerSourceID sourceID: String) throws {
        try saveTombstones(loadTombstones().filter { $0.serverSourceId != sourceID })
    }

    func deletionTombstones() -> [RecordingDeletion] { loadTombstones() }

    func deletedRecordingIDs() -> Set<UUID> { Set(loadTombstones().map(\.id)) }

    func deletedServerSourceIDs() -> Set<String> { Set(loadTombstones().compactMap(\.serverSourceId)) }

    private func loadTombstones() -> [RecordingDeletion] {
        guard let data = try? Data(contentsOf: tombstoneURL), let values = try? JSONDecoder().decode([RecordingDeletion].self, from: data) else { return [] }
        return values
    }

    private func saveTombstones(_ values: [RecordingDeletion]) throws {
        let directory = tombstoneURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: tombstoneURL, options: .atomic)
    }

    func newAudioURL(for id: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func importSharedRecording(_ manifest: SharedImportManifest) throws -> LocalRecording {
        guard let sourceURL = SharedImportInbox.fileURL(for: manifest, fileManager: fileManager),
              fileManager.fileExists(atPath: sourceURL.path) else {
            throw SharedImportInboxError.fileUnavailable
        }

        let validated = try LocalAudioValidator.validate(url: sourceURL)
        let fileName = safeFileName(manifest.fileName, fallback: manifest.id)
        let destination = recordingsDirectory.appendingPathComponent(fileName)
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: sourceURL, to: destination)
        }

        return LocalRecording(
            id: manifest.id,
            localFileURL: destination,
            createdAt: manifest.createdAt,
            duration: validated.duration,
            title: manifest.title,
            state: .localOnly,
            uploadAttempts: 0,
            serverSourceId: nil,
            byteSize: validated.byteSize,
            bookmarks: [],
            lastError: nil,
            consentMode: "conversation",
            consentAcknowledged: true,
            finalizedAt: manifest.createdAt
        )
    }

    func importWatchRecording(fileURL: URL, manifest: WatchTransferManifest) throws -> LocalRecording {
        guard byteSize(of: fileURL) == manifest.byteSize,
              try WatchCaptureProtocol.checksum(of: fileURL) == manifest.sha256 else {
            throw WatchCaptureProtocolError.checksumMismatch
        }

        let fileName = "\(manifest.sourceID.uuidString).m4a"
        let destination = recordingsDirectory.appendingPathComponent(fileName)
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: fileURL, to: destination)
        }

        return LocalRecording(
            id: manifest.sourceID,
            localFileURL: destination,
            createdAt: manifest.createdAt,
            duration: manifest.duration,
            title: "Watch Recording",
            state: .localOnly,
            uploadAttempts: 0,
            serverSourceId: nil,
            byteSize: manifest.byteSize,
            bookmarks: manifest.marks.map { LocalBookmark(id: $0.id, timestamp: $0.sourceElapsedTime, createdAt: $0.createdAt) },
            lastError: nil,
            consentMode: "private_thought",
            consentAcknowledged: true,
            finalizedAt: manifest.endedAt
        )
    }

    func needsWatchRecordingRepair(_ recording: LocalRecording, manifest: WatchTransferManifest) -> Bool {
        guard recording.id == manifest.sourceID,
              recording.fileName == "\(manifest.sourceID.uuidString).m4a",
              fileManager.fileExists(atPath: recording.localFileURL.path),
              byteSize(of: recording.localFileURL) == manifest.byteSize else {
            return true
        }

        return (try? WatchCaptureProtocol.checksum(of: recording.localFileURL)) != manifest.sha256
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

struct RecordingDeletion: Codable, Hashable {
    let id: UUID
    let serverSourceId: String?
}

private extension LocalRecording {
    var stateRank: Int {
        switch state {
        case .draft: 1
        case .recording, .paused, .interrupted: 2
        case .recovering, .localOnly, .queued: 3
        case .uploading, .uploaded: 4
        case .processing: 5
        case .partial, .failed, .needsRepair: 6
        case .ready: 7
        case .missingFile: 0
        }
    }
}
