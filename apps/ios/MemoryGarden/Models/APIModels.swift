import Foundation

enum ProcessingStatus: String, Codable {
    case pending, processing, ready, partial, failed
}

enum TranscriptStatus: String, Codable {
    case notApplicable = "not_applicable"
    case pending, processing, ready, partial, failed
}

struct Source: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let title: String
    let originalText: String
    let extractedText: String
    let createdAt: String
    let updatedAt: String
    let capturedAt: String
    let processingStatus: ProcessingStatus
    let processingError: String?
    let summary: String?
    let transcriptText: String?
    let transcriptStatus: TranscriptStatus?
    let durationMs: Int?
    let audioMimeType: String?
    let consentMode: String?
    let recordingSessionId: String?
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, type, title, originalText, extractedText, createdAt, updatedAt, capturedAt
        case processingStatus, processingError, summary, transcriptText, transcriptStatus
        case durationMs, audioMimeType, consentMode, recordingSessionId, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        originalText = try c.decodeIfPresent(String.self, forKey: .originalText) ?? ""
        extractedText = try c.decodeIfPresent(String.self, forKey: .extractedText) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        capturedAt = try c.decodeIfPresent(String.self, forKey: .capturedAt) ?? ""
        processingStatus = try c.decodeIfPresent(ProcessingStatus.self, forKey: .processingStatus) ?? .pending
        processingError = try c.decodeIfPresent(String.self, forKey: .processingError)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        transcriptText = try c.decodeIfPresent(String.self, forKey: .transcriptText)
        transcriptStatus = try c.decodeIfPresent(TranscriptStatus.self, forKey: .transcriptStatus)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        audioMimeType = try c.decodeIfPresent(String.self, forKey: .audioMimeType)
        consentMode = try c.decodeIfPresent(String.self, forKey: .consentMode)
        recordingSessionId = try c.decodeIfPresent(String.self, forKey: .recordingSessionId)
        metadata = (try? c.decode([String: String].self, forKey: .metadata)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(type, forKey: .type); try c.encode(title, forKey: .title)
        try c.encode(originalText, forKey: .originalText); try c.encode(extractedText, forKey: .extractedText)
        try c.encode(createdAt, forKey: .createdAt); try c.encode(updatedAt, forKey: .updatedAt); try c.encode(capturedAt, forKey: .capturedAt)
        try c.encode(processingStatus, forKey: .processingStatus); try c.encodeIfPresent(processingError, forKey: .processingError)
        try c.encodeIfPresent(summary, forKey: .summary); try c.encodeIfPresent(transcriptText, forKey: .transcriptText)
        try c.encodeIfPresent(transcriptStatus, forKey: .transcriptStatus); try c.encodeIfPresent(durationMs, forKey: .durationMs)
        try c.encodeIfPresent(audioMimeType, forKey: .audioMimeType); try c.encodeIfPresent(consentMode, forKey: .consentMode)
        try c.encodeIfPresent(recordingSessionId, forKey: .recordingSessionId); try c.encode(metadata, forKey: .metadata)
    }
}

struct RecordingSession: Codable, Identifiable, Hashable {
    let id: String
    let sourceId: String
    let status: String
    let startedAt: String
    let endedAt: String?
    let durationMs: Int?
    let mimeType: String?
    let client: String
    let consentMode: String
    let consentAcknowledged: Bool
}

struct TranscriptWord: Codable, Hashable {
    let word: String
    let startMs: Int?
    let endMs: Int?
    let confidence: Double?
}

struct TranscriptSegment: Codable, Identifiable, Hashable {
    let id: String
    let sourceId: String
    let segmentIndex: Int
    let startMs: Int?
    let endMs: Int?
    let text: String
    let speaker: String?
    let confidence: Double?
    let words: [TranscriptWord]?
    let chunkIndex: Int?
    let chunkStartMs: Int?

    var seekTime: TimeInterval { TimeInterval(startMs ?? 0) / 1000 }
}

struct Memory: Codable, Identifiable, Hashable {
    let id: String
    let sourceId: String
    let memoryType: String
    let content: String
    let summary: String
    let confidence: Double
    let supersededBy: String?
    let evidenceRefs: [EvidenceRef]?
}

struct EvidenceRef: Codable, Hashable {
    let sourceId: String
    let segmentId: String?
    let startMs: Int?
    let endMs: Int?
    let quote: String?
}

struct OpenLoop: Codable, Identifiable, Hashable {
    let id: String
    let memoryId: String
    let description: String
    let status: String
    let confidence: Double
    let dueAt: String?
    let evidenceRefs: [EvidenceRef]?
}

struct SourceBundle: Codable {
    let source: Source
    let recordingSession: RecordingSession?
    let transcript: TranscriptPayload
    let memories: [Memory]
    let entities: [[String: String]]
    let openLoops: [OpenLoop]
}

struct TranscriptPayload: Codable {
    let text: String
    let segments: [TranscriptSegment]
}

struct Citation: Codable, Hashable, Identifiable {
    let memoryId: String
    let sourceId: String
    let sourceTitle: String?
    let sourceType: String?
    let capturedAt: String?
    let content: String
    let superseded: Bool
    let segmentId: String?
    let startMs: Int?
    let endMs: Int?
    let quote: String?

    var id: String { memoryId }
}

struct AskResponse: Codable {
    let answer: String
    let citations: [Citation]
}

enum LocalRecordingState: String, Codable, CaseIterable {
    case recording, paused, localOnly, queued, uploading, uploaded, processing, ready, partial, failed

    var title: String {
        switch self {
        case .recording: "Recording"
        case .paused: "Paused"
        case .localOnly: "On Device"
        case .queued: "Queued"
        case .uploading: "Uploading"
        case .uploaded: "Uploaded"
        case .processing: "Processing"
        case .ready: "Ready"
        case .partial: "Partial"
        case .failed: "Failed"
        }
    }
}

struct LocalBookmark: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: TimeInterval
    let createdAt: Date
}

struct LocalRecording: Codable, Identifiable, Hashable {
    let id: UUID
    var localFileURL: URL
    var createdAt: Date
    var duration: TimeInterval
    var title: String
    var state: LocalRecordingState
    var uploadAttempts: Int
    var serverSourceId: String?
    var byteSize: Int64
    var bookmarks: [LocalBookmark]
    var lastError: String?
    var consentMode: String

    var durationLabel: String {
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

struct UploadResponse: Codable {
    let id: String
    let processingStatus: ProcessingStatus
    let recordingSession: RecordingSession?
    let deduplicated: Bool?
}
