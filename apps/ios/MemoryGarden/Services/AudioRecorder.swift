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
        guard state == .idle else { return }

        let permission = AVAudioApplication.shared.recordPermission
        if permission == .undetermined {
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard granted else { throw RecorderError.microphoneDenied }
        } else if permission != .granted {
            throw RecorderError.microphoneDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

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

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64_000
        ]
        do {
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
            state = .failed(error.localizedDescription)
            interruptionMessage = "The recording could not start. The saved draft remains available for recovery."
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

    func stop() -> LocalRecording? {
        guard recorder != nil, activeRecordingID != nil else { return nil }
        isFinishing = true
        recorder?.stop()
        return finalizeCurrentRecording(error: nil)
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
        let duration = max(elapsed, recorder?.currentTime ?? 0)
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
            byteSize: store.byteSize(of: url),
            bookmarks: [],
            lastError: error,
            consentMode: "private_thought",
            consentAcknowledged: true
        )
        result.localFileURL = url
        result.fileName = url.lastPathComponent
        result.finalizedAt = Date()
        result.duration = duration
        result.state = .localOnly
        result.byteSize = store.byteSize(of: url)
        result.lastError = error
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return result
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .began {
            accumulatedDuration = elapsed
            recorder?.pause()
            ticker?.cancel()
            state = .interrupted
            interruptionMessage = "Recording was interrupted. Resume when the microphone is available."
            checkpointDraft(state: .interrupted)
        } else if type == .ended,
                  let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
            interruptionMessage = "Recording can resume."
        }
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
                return
            }
            let error = flag ? nil : "The recorder stopped before the recording was complete."
            _ = self.finalizeCurrentRecording(error: error)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = self.finalizeCurrentRecording(error: error?.localizedDescription ?? "The audio file could not be finalized.")
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
