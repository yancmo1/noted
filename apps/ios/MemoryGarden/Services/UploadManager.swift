import Foundation
import Combine

@MainActor
final class UploadManager: ObservableObject {
    @Published private(set) var activeRecordingID: UUID?
    @Published private(set) var lastError: String?

    private let api: APIClient
    private let store: LocalRecordingStore

    init(api: APIClient, store: LocalRecordingStore) { self.api = api; self.store = store }

    func sync(_ recordings: [LocalRecording]) async -> [LocalRecording] {
        var updated = recordings
        for index in updated.indices {
            guard [.localOnly, .queued, .failed].contains(updated[index].state) else { continue }
            let id = updated[index].id; activeRecordingID = id; lastError = nil
            updated[index].state = .uploading; updated[index].uploadAttempts += 1; updated[index].lastError = nil
            try? store.save(updated)
            do {
                let response = try await api.uploadRecording(updated[index])
                updated[index].serverSourceId = response.id
                updated[index].state = response.processingStatus == .ready ? .ready : .processing
                updated[index].lastError = nil
            } catch {
                updated[index].state = .failed; updated[index].lastError = error.localizedDescription; lastError = error.localizedDescription
            }
            try? store.save(updated)
        }
        activeRecordingID = nil
        return updated
    }
}
