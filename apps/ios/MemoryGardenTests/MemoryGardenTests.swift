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
        XCTAssertEqual(decoded, recording)
    }
}
