import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var player: AVAudioPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    private var ticker: Task<Void, Never>?

    func load(url: URL) throws { player = try AVAudioPlayer(contentsOf: url); player?.delegate = self; player?.prepareToPlay(); duration = player?.duration ?? 0; currentTime = 0 }
    func toggle() { guard let player else { return }; if player.isPlaying { player.pause(); isPlaying = false; ticker?.cancel() } else { player.play(); isPlaying = true; startTicker() } }
    func seek(to time: TimeInterval) { guard let player else { return }; player.currentTime = min(max(0, time), player.duration); currentTime = player.currentTime }
    func stop() { player?.stop(); player?.currentTime = 0; currentTime = 0; isPlaying = false; ticker?.cancel() }
    private func startTicker() { ticker?.cancel(); ticker = Task { [weak self] in while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)); guard let self else { return }; self.currentTime = self.player?.currentTime ?? 0 } } }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor [weak self] in self?.isPlaying = false; self?.currentTime = 0 } }
}
