import Combine
import Foundation

@MainActor
final class UploadManager: ObservableObject {
    @Published private(set) var activeRecordingID: UUID?
    @Published private(set) var lastError: String?

    private let api: APIClient
    private let store: LocalRecordingStore

    init(api: APIClient, store: LocalRecordingStore) {
        self.api = api
        self.store = store
    }

    func sync(_ recordings: [LocalRecording], force: Bool = false) async -> [LocalRecording] {
        var updated = recordings
        for index in updated.indices {
            let state = updated[index].state
            if state == .uploading {
                updated[index].state = .queued
            }
            let retryable: Set<LocalRecordingState> = [.localOnly, .queued, .failed, .recovering]
            guard retryable.contains(updated[index].state) else { continue }
            if !force, let nextRetryAt = updated[index].nextRetryAt, nextRetryAt > Date() { continue }
            guard FileManager.default.fileExists(atPath: updated[index].localFileURL.path) else {
                updated[index].state = .missingFile
                updated[index].lastError = "The saved audio file is missing from this iPhone."
                continue
            }

            let id = updated[index].id
            activeRecordingID = id
            lastError = nil
            updated[index].state = .uploading
            updated[index].uploadAttempts += 1
            updated[index].lastError = nil
            updated[index].nextRetryAt = nil
            try? store.save(updated)

            do {
                let response: UploadResponse
                do {
                    response = try await api.recordingByClientID(id)
                } catch {
                    response = try await api.uploadRecording(updated[index])
                }
                updated[index].serverSourceId = response.id
                updated[index].state = localState(for: response.processingStatus)
                updated[index].lastError = nil
                updated[index].nextRetryAt = nil
            } catch {
                updated[index].state = .failed
                updated[index].lastError = error.localizedDescription
                updated[index].nextRetryAt = Date().addingTimeInterval(retryDelay(attempts: updated[index].uploadAttempts))
                lastError = error.localizedDescription
            }
            try? store.save(updated)
        }
        activeRecordingID = nil
        return updated
    }

    private func localState(for processingStatus: ProcessingStatus) -> LocalRecordingState {
        switch processingStatus {
        case .pending, .processing: .processing
        case .ready: .ready
        case .partial: .partial
        case .failed: .failed
        }
    }

    private func retryDelay(attempts: Int) -> TimeInterval {
        min(300, pow(2, Double(max(0, attempts - 1))) * 2)
    }
}
