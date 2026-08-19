import Foundation

enum ProcessingStatus: String, Codable {
    case pending, processing, ready, partial, failed
}

enum TranscriptStatus: String, Codable {
    case notApplicable = "not_applicable"
    case pending, processing, ready, partial, failed
}

enum ClaimState: String, Codable {
    case generated, confirmed, edited
}

struct InferredValue: Codable, Hashable {
    let value: String
    let confidence: Double
    let state: ClaimState
}

struct MeetingClaim: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let confidence: Double
    let state: ClaimState
    let evidenceRefs: [EvidenceRef]
}

struct MeetingActionItem: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let confidence: Double
    let state: ClaimState
    let evidenceRefs: [EvidenceRef]
    let owner: InferredValue?
    let dueAt: InferredValue?
    var status: String
}

struct MeetingBrief: Codable, Hashable {
    let schemaVersion: Int
    let generatedAt: String
    let summary: String
    let keyPoints: [MeetingClaim]
    let decisions: [MeetingClaim]
    var actionItems: [MeetingActionItem]
    let suggestedFollowUps: [MeetingClaim]
    let unresolvedQuestions: [MeetingClaim]
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
    let meetingBrief: MeetingBrief?

    enum CodingKeys: String, CodingKey {
        case id, type, title, originalText, extractedText, createdAt, updatedAt, capturedAt
        case processingStatus, processingError, summary, transcriptText, transcriptStatus
        case durationMs, audioMimeType, consentMode, recordingSessionId, metadata
        case meetingBrief
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
        meetingBrief = try c.decodeIfPresent(MeetingBrief.self, forKey: .meetingBrief)
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
        try c.encodeIfPresent(meetingBrief, forKey: .meetingBrief)
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

enum LocalRecordingState: String, Codable, CaseIterable, Hashable {
    case draft, recording, paused, interrupted, recovering, localOnly, queued, uploading, uploaded, processing, ready, partial, failed, missingFile

    var title: String {
        switch self {
        case .draft: "Preparing"
        case .recording: "Recording"
        case .paused: "Paused"
        case .interrupted: "Interrupted"
        case .recovering: "Recovered"
        case .localOnly: "On Device"
        case .queued: "Waiting for Connection"
        case .uploading: "Uploading"
        case .uploaded: "Uploaded"
        case .processing: "Processing"
        case .ready: "Ready"
        case .partial: "Partial"
        case .failed: "Needs Retry"
        case .missingFile: "Missing Audio"
        }
    }
}

struct LocalBookmark: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: TimeInterval
    let createdAt: Date
}

struct LocalRecording: Codable, Identifiable, Hashable {
    static let currentSchemaVersion = 2

    let id: UUID
    var localFileURL: URL
    var fileName: String
    var createdAt: Date
    var finalizedAt: Date?
    var duration: TimeInterval
    var title: String
    var state: LocalRecordingState
    var uploadAttempts: Int
    var serverSourceId: String?
    var byteSize: Int64
    var bookmarks: [LocalBookmark]
    var lastError: String?
    var consentMode: String
    var consentAcknowledged: Bool
    var nextRetryAt: Date?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, fileName, legacyLocalFileURL = "localFileURL", createdAt, finalizedAt, duration, title, state
        case uploadAttempts, nextRetryAt, serverSourceId, byteSize, bookmarks, lastError, consentMode
        case consentAcknowledgedKey = "consentAcknowledged"
    }

    init(
        id: UUID,
        localFileURL: URL,
        createdAt: Date,
        duration: TimeInterval,
        title: String,
        state: LocalRecordingState,
        uploadAttempts: Int,
        serverSourceId: String?,
        byteSize: Int64,
        bookmarks: [LocalBookmark],
        lastError: String?,
        consentMode: String,
        consentAcknowledged: Bool = false,
        finalizedAt: Date? = nil,
        nextRetryAt: Date? = nil
    ) {
        self.id = id
        self.localFileURL = localFileURL
        self.fileName = localFileURL.lastPathComponent
        self.createdAt = createdAt
        self.finalizedAt = finalizedAt
        self.duration = duration
        self.title = title
        self.state = state
        self.uploadAttempts = uploadAttempts
        self.serverSourceId = serverSourceId
        self.byteSize = byteSize
        self.bookmarks = bookmarks
        self.lastError = lastError
        self.consentMode = consentMode
        self.consentAcknowledged = consentAcknowledged
        self.nextRetryAt = nextRetryAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let storedFileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        let legacyURL = try container.decodeIfPresent(URL.self, forKey: .legacyLocalFileURL)
        fileName = storedFileName ?? legacyURL?.lastPathComponent ?? "\(id.uuidString).m4a"
        localFileURL = legacyURL ?? URL(fileURLWithPath: fileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        finalizedAt = try container.decodeIfPresent(Date.self, forKey: .finalizedAt)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Recording"
        state = try container.decodeIfPresent(LocalRecordingState.self, forKey: .state) ?? .localOnly
        uploadAttempts = try container.decodeIfPresent(Int.self, forKey: .uploadAttempts) ?? 0
        serverSourceId = try container.decodeIfPresent(String.self, forKey: .serverSourceId)
        byteSize = try container.decodeIfPresent(Int64.self, forKey: .byteSize) ?? 0
        bookmarks = try container.decodeIfPresent([LocalBookmark].self, forKey: .bookmarks) ?? []
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        consentMode = try container.decodeIfPresent(String.self, forKey: .consentMode) ?? "private_thought"
        let consentKey = CodingKeys(rawValue: "consentAcknowledged")!
        let decodedConsent: Swift.Bool? = try? container.decodeIfPresent(Swift.Bool.self, forKey: consentKey)
        consentAcknowledged = decodedConsent ?? (consentMode == "private_thought")
        nextRetryAt = try container.decodeIfPresent(Date.self, forKey: .nextRetryAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(fileName.isEmpty ? localFileURL.lastPathComponent : fileName, forKey: .fileName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(finalizedAt, forKey: .finalizedAt)
        try container.encode(duration, forKey: .duration)
        try container.encode(title, forKey: .title)
        try container.encode(state, forKey: .state)
        try container.encode(uploadAttempts, forKey: .uploadAttempts)
        try container.encodeIfPresent(nextRetryAt, forKey: .nextRetryAt)
        try container.encodeIfPresent(serverSourceId, forKey: .serverSourceId)
        try container.encode(byteSize, forKey: .byteSize)
        try container.encode(bookmarks, forKey: .bookmarks)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(consentMode, forKey: .consentMode)
        try container.encode(consentAcknowledged, forKey: .consentAcknowledgedKey)
    }

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
