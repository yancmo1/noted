import AVFoundation
import Combine
import Foundation

enum RecorderState: Equatable {
    case idle, recording, paused, interrupted, failed(String)
}

@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var activeFileURL: URL?
    @Published private(set) var interruptionMessage: String?

    private let store: LocalRecordingStore
    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void, Never>?
    private var sessionStartedAt: Date?
    private var elapsedAnchor: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var activeRecordingID: UUID?
    private var isFinishing = false
    private var stopContinuation: CheckedContinuation<LocalRecording?, Never>?
    @Published private(set) var isStarting = false
    @Published private(set) var isSaving = false
    var activeRecordingIDForDeletion: UUID? { activeRecordingID }

    init(store: LocalRecordingStore) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start(title: String = "Untitled Recording", consentMode: String = "private_thought", consentAcknowledged: Bool = true) async throws {
        guard state == .idle, !isStarting, !isFinishing else { return }
        isStarting = true
        defer { isStarting = false }

        let permission = AVAudioApplication.shared.recordPermission
        if permission == .undetermined {
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard granted else { throw RecorderError.microphoneDenied }
        } else if permission != .granted {
            throw RecorderError.microphoneDenied
        }

        let id = UUID()
        let url = store.newAudioURL(for: id)
        let createdAt = Date()
        let draft = LocalRecording(
            id: id,
            localFileURL: url,
            createdAt: createdAt,
            duration: 0,
            title: title.isEmpty ? "Untitled Recording" : title,
            state: .draft,
            uploadAttempts: 0,
            serverSourceId: nil,
            byteSize: 0,
            bookmarks: [],
            lastError: nil,
            consentMode: consentMode,
            consentAcknowledged: consentAcknowledged
        )

        var recordings = store.load()
        recordings.removeAll { $0.id == id }
        recordings.append(draft)
        try store.save(recordings)

        AudioSessionCoordinator.shared.beginRecording()
        var sessionClaimed = true
        let session = AVAudioSession.sharedInstance()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64_000
        ]
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            guard recorder.prepareToRecord(), recorder.record() else {
                throw RecorderError.couldNotStart
            }
            self.recorder = recorder
            activeFileURL = url
            activeRecordingID = id
            sessionStartedAt = createdAt
            elapsedAnchor = createdAt
            accumulatedDuration = 0
            elapsed = 0
            interruptionMessage = nil
            isFinishing = false
            state = .recording
            checkpointDraft(state: .recording)
            startTicker()
        } catch {
            if sessionClaimed {
                AudioSessionCoordinator.shared.endRecording()
                sessionClaimed = false
            }
            if store.byteSize(of: url) == 0 {
                try? store.removeMetadata(for: id)
            } else {
                state = .failed(error.localizedDescription)
                interruptionMessage = "The recording could not start. The saved draft remains available for recovery."
            }
            throw error
        }
    }

    func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        accumulatedDuration = elapsed
        ticker?.cancel()
        state = .paused
        checkpointDraft(state: .paused)
    }

    func resume() {
        guard state == .paused || state == .interrupted else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            interruptionMessage = "The microphone is still unavailable. Try Resume again when it is ready."
            return
        }
        guard recorder?.record() == true else {
            state = .failed("The microphone could not resume recording.")
            checkpointDraft(state: .failed)
            return
        }
        elapsedAnchor = Date().addingTimeInterval(-accumulatedDuration)
        interruptionMessage = nil
        state = .recording
        checkpointDraft(state: .recording)
        startTicker()
    }

    func stop() async -> LocalRecording? {
        guard recorder != nil, activeRecordingID != nil, !isFinishing else { return nil }
        isFinishing = true
        isSaving = true
        return await withCheckedContinuation { continuation in
            stopContinuation = continuation
            recorder?.stop()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isFinishing else { return }
                self.completeFinalization(error: "The recorder did not finish closing cleanly. The saved audio needs repair.")
            }
        }
    }

    func markMoment() -> TimeInterval? {
        guard state == .recording || state == .paused else { return nil }
        return elapsed
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var lastCheckpoint = Date.distantPast
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                if self.state == .recording, let elapsedAnchor = self.elapsedAnchor {
                    self.elapsed = Date().timeIntervalSince(elapsedAnchor)
                    if Date().timeIntervalSince(lastCheckpoint) >= 5 {
                        self.checkpointDraft(state: .recording)
                        lastCheckpoint = Date()
                    }
                }
            }
        }
    }

    private func checkpointDraft(state: LocalRecordingState) {
        guard let activeRecordingID else { return }
        var recordings = store.load()
        guard let index = recordings.firstIndex(where: { $0.id == activeRecordingID }) else { return }
        recordings[index].state = state
        recordings[index].duration = max(elapsed, recorder?.currentTime ?? 0)
        recordings[index].byteSize = store.byteSize(of: recordings[index].localFileURL)
        try? store.save(recordings)
    }

    private func finalizeCurrentRecording(error: String?) -> LocalRecording? {
        guard let id = activeRecordingID, let url = activeFileURL else { return nil }
        ticker?.cancel()
        let validation = try? LocalAudioValidator.validate(url: url)
        let duration = validation?.duration ?? 0
        var recordings = store.load()
        let existingIndex = recordings.firstIndex(where: { $0.id == id })
        let existing = existingIndex.map { recordings[$0] }
        var result = existing ?? LocalRecording(
            id: id,
            localFileURL: url,
            createdAt: sessionStartedAt ?? Date(),
            duration: duration,
            title: "Untitled Recording",
            state: .localOnly,
            uploadAttempts: 0,
            serverSourceId: nil,
            byteSize: validation?.byteSize ?? store.byteSize(of: url),
            bookmarks: [],
            lastError: error,
            consentMode: "private_thought",
            consentAcknowledged: true
        )
        result.localFileURL = url
        result.fileName = url.lastPathComponent
        result.finalizedAt = Date()
        result.duration = duration
        result.state = validation == nil ? .needsRepair : .localOnly
        result.byteSize = validation?.byteSize ?? store.byteSize(of: url)
        result.lastError = validation == nil ? "Needs repair: \(error ?? "The saved audio file is incomplete or unreadable.")" : error
        if let existingIndex {
            recordings[existingIndex] = result
        } else {
            recordings.append(result)
        }
        try? store.save(recordings)

        recorder = nil
        activeFileURL = nil
        activeRecordingID = nil
        sessionStartedAt = nil
        elapsedAnchor = nil
        elapsed = 0
        accumulatedDuration = 0
        state = .idle
        isFinishing = false
        isSaving = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        AudioSessionCoordinator.shared.endRecording()
        return result
    }

    private func completeFinalization(error: String?) {
        let result = finalizeCurrentRecording(error: error)
        let continuation = stopContinuation
        stopContinuation = nil
        continuation?.resume(returning: result)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .began {
            accumulatedDuration = elapsed
            recorder?.pause()
            ticker?.cancel()
            if elapsed <= 0.01 {
                let hasViableAudio = activeFileURL.flatMap { try? LocalAudioValidator.validate(url: $0) } != nil
                if !hasViableAudio {
                    discardEmptyInterruption()
                    return
                }
            }
            state = .interrupted
            interruptionMessage = "Recording was interrupted. Resume when the microphone is available."
            checkpointDraft(state: .interrupted)
        } else if type == .ended,
                  let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
            interruptionMessage = "Recording can resume."
        }
    }

    private func discardEmptyInterruption() {
        recorder?.stop()
        recorder = nil
        ticker?.cancel()
        if let id = activeRecordingID, let url = activeFileURL {
            if (try? LocalAudioValidator.validate(url: url)) == nil {
                try? store.removeMetadata(for: id)
                try? FileManager.default.removeItem(at: url)
            }
        }
        activeFileURL = nil
        activeRecordingID = nil
        sessionStartedAt = nil
        elapsedAnchor = nil
        elapsed = 0
        accumulatedDuration = 0
        isFinishing = false
        isSaving = false
        state = .idle
        interruptionMessage = "No audio was captured before the interruption. You can start again."
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        AudioSessionCoordinator.shared.endRecording()
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard state == .recording,
              let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            interruptionMessage = "The audio route changed. Check the microphone and continue when ready."
            checkpointDraft(state: .recording)
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder != nil else { return }
            if self.isFinishing {
                self.completeFinalization(error: flag ? nil : "The recorder stopped before the recording was complete.")
                return
            }
            let error = flag ? nil : "The recorder stopped before the recording was complete."
            _ = self.finalizeCurrentRecording(error: error)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.completeFinalization(error: error?.localizedDescription ?? "The audio file could not be finalized.")
        }
    }
}

enum RecorderError: LocalizedError {
    case microphoneDenied
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is denied. Enable it in Settings to record."
        case .couldNotStart: "The recording could not start."
        }
    }
}
