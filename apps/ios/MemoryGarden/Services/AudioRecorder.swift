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
    private var startedAt: Date?
    private var accumulatedDuration: TimeInterval = 0

    init(store: LocalRecordingStore) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func start() async throws {
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .undetermined {
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard granted else { throw RecorderError.microphoneDenied }
        } else if permission != .granted { throw RecorderError.microphoneDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let id = UUID()
        let url = store.newAudioURL(for: id)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64_000
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder; activeFileURL = url; startedAt = Date(); accumulatedDuration = 0; elapsed = 0; interruptionMessage = nil; state = .recording
        startTicker()
    }

    func pause() {
        guard state == .recording else { return }
        recorder?.pause(); accumulatedDuration = elapsed; ticker?.cancel(); state = .paused
    }

    func resume() {
        guard state == .paused || state == .interrupted else { return }
        recorder?.record(); startedAt = Date().addingTimeInterval(-accumulatedDuration); interruptionMessage = nil; state = .recording; startTicker()
    }

    func stop() -> LocalRecording? {
        guard let recorder, let url = activeFileURL, let startedAt else { return nil }
        recorder.stop(); ticker?.cancel(); let duration = max(elapsed, recorder.currentTime); let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
        let result = LocalRecording(id: id, localFileURL: url, createdAt: startedAt, duration: duration, title: "Untitled Recording", state: .localOnly, uploadAttempts: 0, serverSourceId: nil, byteSize: store.byteSize(of: url), bookmarks: [], lastError: nil, consentMode: "private_thought")
        self.recorder = nil; activeFileURL = nil; self.startedAt = nil; elapsed = 0; accumulatedDuration = 0; state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return result
    }

    func markMoment() -> TimeInterval? { guard state == .recording || state == .paused else { return nil }; return elapsed }

    private func startTicker() { ticker?.cancel(); ticker = Task { [weak self] in while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)); guard let self else { return }; if self.state == .recording, let startedAt = self.startedAt { self.elapsed = Date().timeIntervalSince(startedAt) } } } }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo, let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .began { accumulatedDuration = elapsed; ticker?.cancel(); state = .interrupted; interruptionMessage = "Recording interrupted by another audio event. Tap Resume to continue." }
        if type == .ended, let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt, AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) { interruptionMessage = "Recording can resume." }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard state == .recording, let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable { interruptionMessage = "The audio route changed. Check the microphone and continue when ready." }
    }
}

enum RecorderError: LocalizedError { case microphoneDenied, couldNotStart
    var errorDescription: String? { switch self { case .microphoneDenied: "Microphone access is denied. Enable it in Settings to record."; case .couldNotStart: "The recording could not start." } }
}
