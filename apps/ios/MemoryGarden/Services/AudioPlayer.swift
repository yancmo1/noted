import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private weak var activePlayer: AudioPlayer?
    private(set) var isRecordingActive = false

    func beginRecording() {
        activePlayer?.stop()
        activePlayer = nil
        isRecordingActive = true
    }

    func endRecording() {
        isRecordingActive = false
    }

    func beginPlayback(for player: AudioPlayer) -> Bool {
        guard !isRecordingActive else { return false }
        if activePlayer !== player {
            activePlayer?.stop()
        }
        activePlayer = player
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            return true
        } catch {
            activePlayer = nil
            return false
        }
    }

    func endPlayback(for player: AudioPlayer) {
        guard activePlayer === player else { return }
        activePlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var player: AVAudioPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var canPlay = false
    @Published private(set) var errorMessage: String?
    private var ticker: Task<Void, Never>?
    private let sessionCoordinator: AudioSessionCoordinator

    init(sessionCoordinator: AudioSessionCoordinator = .shared) {
        self.sessionCoordinator = sessionCoordinator
        super.init()
    }

    func load(url: URL) throws {
        stop()
        player = nil
        canPlay = false
        duration = 0
        guard FileManager.default.fileExists(atPath: url.path) else { throw AudioPlayerError.fileMissing }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw AudioPlayerError.fileEmpty }
        let loadedPlayer = try AVAudioPlayer(contentsOf: url)
        loadedPlayer.delegate = self
        guard loadedPlayer.prepareToPlay() else { throw AudioPlayerError.couldNotPrepare }
        player = loadedPlayer
        duration = loadedPlayer.duration
        currentTime = 0
        canPlay = true
        errorMessage = nil
    }

    @discardableResult
    func toggle() -> Bool {
        guard let player, canPlay else {
            errorMessage = AudioPlayerError.noAudio.errorDescription
            return false
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.cancel()
            sessionCoordinator.endPlayback(for: self)
            return true
        }
        guard sessionCoordinator.beginPlayback(for: self) else {
            errorMessage = AudioPlayerError.recordingInProgress.errorDescription
            isPlaying = false
            return false
        }
        guard player.play() else {
            sessionCoordinator.endPlayback(for: self)
            errorMessage = AudioPlayerError.couldNotPlay.errorDescription
            isPlaying = false
            return false
        }
        errorMessage = nil
        isPlaying = true
        startTicker()
        return true
    }

    func seek(to time: TimeInterval) { guard let player else { return }; player.currentTime = min(max(0, time), player.duration); currentTime = player.currentTime }
    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        ticker?.cancel()
        sessionCoordinator.endPlayback(for: self)
    }

    private func startTicker() { ticker?.cancel(); ticker = Task { [weak self] in while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)); guard let self else { return }; self.currentTime = self.player?.currentTime ?? 0 } } }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor [weak self] in self?.stop() } }
}

enum AudioPlayerError: LocalizedError {
    case fileMissing, fileEmpty, couldNotPrepare, couldNotPlay, noAudio, recordingInProgress

    var errorDescription: String? {
        switch self {
        case .fileMissing: "The audio file is no longer available on this iPhone."
        case .fileEmpty: "The saved audio file is empty and cannot be played."
        case .couldNotPrepare: "The saved audio file could not be prepared for playback."
        case .couldNotPlay: "Playback could not start. Try again."
        case .noAudio: "No playable audio is loaded for this recording."
        case .recordingInProgress: "Stop or pause the active recording before playing audio."
        }
    }
}
