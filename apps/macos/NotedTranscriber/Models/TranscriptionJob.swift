import Foundation

enum TranscriptionState: String, Codable, Sendable {
    case queued
    case transcribing
    case ready
    case failed

    var title: String {
        switch self {
        case .queued: "Waiting"
        case .transcribing: "Transcribing"
        case .ready: "Ready"
        case .failed: "Needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .queued: "clock"
        case .transcribing: "waveform"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

struct TranscriptSegment: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let startMilliseconds: Int
    let endMilliseconds: Int
    var text: String

    init(id: UUID = UUID(), startMilliseconds: Int, endMilliseconds: Int, text: String) {
        self.id = id
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.text = text
    }

    var timestamp: String {
        let totalSeconds = startMilliseconds / 1_000
        return String(format: "%02d:%02d:%02d", totalSeconds / 3_600, (totalSeconds / 60) % 60, totalSeconds % 60)
    }
}

struct TranscriptionJob: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    let sourcePath: String
    let sourceFingerprint: String
    let createdAt: Date
    var updatedAt: Date
    var state: TranscriptionState
    var transcript: String
    var segments: [TranscriptSegment]
    var detectedLanguage: String?
    var errorMessage: String?
    let outputPath: String

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var outputURL: URL { URL(fileURLWithPath: outputPath, isDirectory: true) }
    var fileDetails: String {
        let ext = sourceURL.pathExtension.uppercased()
        return ext.isEmpty ? "Recording" : "\(ext) recording"
    }

    var timestampedTranscript: String {
        guard !segments.isEmpty else { return transcript }
        return segments
            .map { "[\($0.timestamp)] \($0.text)" }
            .joined(separator: "\n")
    }
}

struct WhisperDocument: Decodable, Sendable {
    struct Result: Decodable, Sendable { let language: String? }
    struct Entry: Decodable, Sendable {
        struct Offsets: Decodable, Sendable { let from: Int; let to: Int }
        let offsets: Offsets
        let text: String
    }

    let result: Result
    let transcription: [Entry]
}
