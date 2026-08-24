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

    func sync(_ recordings: [LocalRecording], recordingID: UUID) async -> [LocalRecording] {
        var updated = recordings
        for index in updated.indices {
            guard updated[index].id == recordingID else { continue }
            let state = updated[index].state
            if state == .uploading {
                updated[index].state = .queued
            }
            let retryable: Set<LocalRecordingState> = [.localOnly, .queued, .failed, .recovering]
            guard retryable.contains(updated[index].state) else { continue }
            let resolvedURL = store.resolvedURL(for: updated[index])
            do {
                let validated = try LocalAudioValidator.validate(url: resolvedURL)
                updated[index].duration = validated.duration
                updated[index].byteSize = validated.byteSize
            } catch {
                let isMissing = (error as? LocalAudioValidationError) == .missing
                updated[index].state = isMissing ? .missingFile : .needsRepair
                updated[index].lastError = "Needs repair: \(error.localizedDescription)"
                try? store.save(updated)
                continue
            }
            updated[index].localFileURL = resolvedURL

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
