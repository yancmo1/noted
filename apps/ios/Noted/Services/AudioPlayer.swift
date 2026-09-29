import AVFoundation
import Combine
import Foundation

private enum AudioSessionActivationError: Error, Sendable {
    case activationFailed
    case deactivationFailed
}

enum AudioSessionActivation {
    static func activate(_ session: AVAudioSession, options: AVAudioSession.SetActiveOptions = []) async throws {
        if #available(iOS 27.0, *) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.activate(options: AVAudioSessionActivationOptions()) { activated, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if activated {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AudioSessionActivationError.activationFailed)
                    }
                }
            }
            return
        }

        let rawOptions = options.rawValue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try session.setActive(true, options: AVAudioSession.SetActiveOptions(rawValue: rawOptions))
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func deactivate(_ session: AVAudioSession, options: AVAudioSession.SetActiveOptions = []) async throws {
        if #available(iOS 27.0, *) {
            let asyncOptions: AVAudioSessionDeactivationOptions = options.contains(.notifyOthersOnDeactivation)
                ? .notifyOthersOnDeactivation
                : []
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.deactivate(options: asyncOptions) { deactivated, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if deactivated {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AudioSessionActivationError.deactivationFailed)
                    }
                }
            }
            return
        }

        let rawOptions = options.rawValue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try session.setActive(false, options: AVAudioSession.SetActiveOptions(rawValue: rawOptions))
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private weak var activePlayer: AudioPlayer?
    private(set) var isRecordingActive = false

    func beginRecording() async {
        if let activePlayer {
            await activePlayer.stop()
        }
        activePlayer = nil
        isRecordingActive = true
    }

    func endRecording() {
        isRecordingActive = false
    }

    func beginPlayback(for player: AudioPlayer) async -> Bool {
        guard !isRecordingActive else { return false }
        if activePlayer !== player {
            if let activePlayer {
                await activePlayer.stop()
            }
        }
        activePlayer = player
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try await AudioSessionActivation.activate(session)
            return true
        } catch {
            activePlayer = nil
            return false
        }
    }

    func endPlayback(for player: AudioPlayer) async {
        guard activePlayer === player else { return }
        activePlayer = nil
        try? await AudioSessionActivation.deactivate(
            AVAudioSession.sharedInstance(),
            options: .notifyOthersOnDeactivation
        )
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

    func load(url: URL) async throws {
        await stop()
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
    func toggle() async -> Bool {
        guard let player, canPlay else {
            errorMessage = AudioPlayerError.noAudio.errorDescription
            return false
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.cancel()
            await sessionCoordinator.endPlayback(for: self)
            return true
        }
        guard await sessionCoordinator.beginPlayback(for: self) else {
            errorMessage = AudioPlayerError.recordingInProgress.errorDescription
            isPlaying = false
            return false
        }
        guard player.play() else {
            await sessionCoordinator.endPlayback(for: self)
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
    func stop() async {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        ticker?.cancel()
        await sessionCoordinator.endPlayback(for: self)
    }

    private func startTicker() { ticker?.cancel(); ticker = Task { [weak self] in while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)); guard let self else { return }; self.currentTime = self.player?.currentTime ?? 0 } } }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor [weak self] in await self?.stop() } }
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
