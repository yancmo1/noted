import Foundation

final class LocalRecordingStore {
    let recordingsDirectory: URL
    private let indexURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingsDirectory = base.appendingPathComponent("MemoryGarden/Recordings", isDirectory: true)
        indexURL = base.appendingPathComponent("MemoryGarden/recordings.json")
        try? fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    }

    func load() -> [LocalRecording] {
        guard let data = try? Data(contentsOf: indexURL), let values = try? JSONDecoder().decode([LocalRecording].self, from: data) else { return [] }
        return values.filter { FileManager.default.fileExists(atPath: $0.localFileURL.path) || $0.serverSourceId != nil }
    }

    func save(_ recordings: [LocalRecording]) throws {
        let data = try JSONEncoder().encode(recordings)
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: indexURL, options: .atomic)
    }

    func newAudioURL(for id: UUID) -> URL { recordingsDirectory.appendingPathComponent("\(id.uuidString).m4a") }

    func byteSize(of url: URL) -> Int64 { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0 }
}
