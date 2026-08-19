import XCTest
@testable import MemoryGarden

final class MemoryGardenTests: XCTestCase {
    func testTranscriptSegmentConvertsMillisecondsToSeekTime() {
        let segment = TranscriptSegment(id: "1", sourceId: "source", segmentIndex: 0, startMs: 18_420, endMs: 20_000, text: "A decision", speaker: nil, confidence: nil, words: nil, chunkIndex: 2, chunkStartMs: 18_000)
        XCTAssertEqual(segment.seekTime, 18.42, accuracy: 0.001)
    }

    func testLocalRecordingStateIsCodable() throws {
        let recording = LocalRecording(id: UUID(), localFileURL: URL(fileURLWithPath: "/tmp/example.m4a"), createdAt: Date(), duration: 62, title: "Example", state: .queued, uploadAttempts: 1, serverSourceId: nil, byteSize: 123, bookmarks: [LocalBookmark(id: UUID(), timestamp: 12, createdAt: Date())], lastError: nil, consentMode: "private_thought")
        let data = try JSONEncoder().encode(recording)
        let decoded = try JSONDecoder().decode(LocalRecording.self, from: data)
        XCTAssertEqual(decoded.id, recording.id)
        XCTAssertEqual(decoded.fileName, "example.m4a")
        XCTAssertEqual(decoded.localFileURL.lastPathComponent, "example.m4a")
        XCTAssertEqual(decoded.state, recording.state)
    }

    func testStoreRecoversInterruptedDraftAndKeepsMissingMetadataVisible() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = LocalRecordingStore(baseDirectory: base)
        let draftID = UUID()
        let draft = LocalRecording(id: draftID, localFileURL: store.newAudioURL(for: draftID), createdAt: Date(), duration: 4, title: "Recovered", state: .recording, uploadAttempts: 0, serverSourceId: nil, byteSize: 4, bookmarks: [], lastError: nil, consentMode: "meeting", consentAcknowledged: true)
        try Data("audio".utf8).write(to: draft.localFileURL)
        let missingID = UUID()
        let missing = LocalRecording(id: missingID, localFileURL: store.newAudioURL(for: missingID), createdAt: Date().addingTimeInterval(-10), duration: 2, title: "Missing", state: .localOnly, uploadAttempts: 0, serverSourceId: nil, byteSize: 0, bookmarks: [], lastError: nil, consentMode: "private_thought")
        try store.save([draft, missing])

        let loaded = store.load()
        XCTAssertEqual(loaded.first(where: { $0.id == draftID })?.state, .recovering)
        XCTAssertEqual(loaded.first(where: { $0.id == draftID })?.localFileURL, draft.localFileURL)
        XCTAssertEqual(loaded.first(where: { $0.id == missingID })?.state, .missingFile)
    }
}
