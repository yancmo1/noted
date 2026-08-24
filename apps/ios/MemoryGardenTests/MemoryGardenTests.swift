import XCTest
import Security
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

    func testStoreNormalizesDuplicateIDsAndKeepsMostCompleteAudioMetadata() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = LocalRecordingStore(baseDirectory: base)
        let id = UUID()
        let firstURL = store.newAudioURL(for: id)
        let secondURL = store.recordingsDirectory.appendingPathComponent("alternate-\(id.uuidString).m4a")
        try Data(repeating: 1, count: 4).write(to: firstURL)
        try Data(repeating: 2, count: 32).write(to: secondURL)
        let first = LocalRecording(id: id, localFileURL: firstURL, createdAt: Date(), duration: 2, title: "Draft", state: .localOnly, uploadAttempts: 0, serverSourceId: nil, byteSize: 4, bookmarks: [], lastError: nil, consentMode: "private_thought")
        let bookmark = LocalBookmark(id: UUID(), timestamp: 1.5, createdAt: Date())
        let second = LocalRecording(id: id, localFileURL: secondURL, createdAt: Date(), duration: 12, title: "Important meeting", state: .ready, uploadAttempts: 2, serverSourceId: "source-1", byteSize: 32, bookmarks: [bookmark], lastError: nil, consentMode: "meeting", consentAcknowledged: true, finalizedAt: Date())
        try store.save([first, second])

        let loaded = store.load()
        XCTAssertEqual(loaded.filter { $0.id == id }.count, 1)
        XCTAssertEqual(loaded.first?.title, "Important meeting")
        XCTAssertEqual(loaded.first?.duration, 12)
        XCTAssertEqual(loaded.first?.serverSourceId, "source-1")
        XCTAssertEqual(loaded.first?.bookmarks, [bookmark])
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path), "Normalization must not delete an alternate valid audio file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testStoreDeletionTombstoneHidesRecordingAcrossReload() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = LocalRecordingStore(baseDirectory: base)
        let id = UUID()
        let url = store.newAudioURL(for: id)
        try Data("audio".utf8).write(to: url)
        let recording = LocalRecording(id: id, localFileURL: url, createdAt: Date(), duration: 1, title: "Delete me", state: .localOnly, uploadAttempts: 0, serverSourceId: nil, byteSize: 5, bookmarks: [], lastError: nil, consentMode: "private_thought")
        try store.save([recording])
        try store.markDeleted(recording)
        try store.save([])

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertTrue(store.deletedRecordingIDs().contains(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "The store tombstone does not remove audio before the confirmed delete path does so")
    }

    func testResolvedRecordingURLUsesStoreManifestPath() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = LocalRecordingStore(baseDirectory: base)
        let id = UUID()
        let recording = LocalRecording(
            id: id,
            localFileURL: URL(fileURLWithPath: "/stale/old-location.m4a"),
            createdAt: Date(),
            duration: 1,
            title: "Playback",
            state: .localOnly,
            uploadAttempts: 0,
            serverSourceId: nil,
            byteSize: 1,
            bookmarks: [],
            lastError: nil,
            consentMode: "private_thought"
        )

        XCTAssertEqual(store.resolvedURL(for: recording), store.recordingsDirectory.appendingPathComponent("old-location.m4a"))
    }

    func testLocalAudioValidatorRejectsEmptyFileForUploadGating() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)

        XCTAssertThrowsError(try LocalAudioValidator.validate(url: url)) { error in
            XCTAssertEqual(error as? LocalAudioValidationError, .empty)
        }
    }

    func testTimeLabelIsFormattedForBannerAndControls() {
        XCTAssertEqual(timeLabel(17), "00:00:17")
        XCTAssertEqual(timeLabel(3661), "01:01:01")
    }

    func testKeychainSaveUpdatesExistingItemWithDeviceOnlyProtection() throws {
        let operations = StubKeychainOperations(updateStatuses: [errSecSuccess])
        let store = KeychainStore(operations: operations)

        try store.savePassword("secret-value")

        XCTAssertEqual(operations.addCalls.count, 0)
        XCTAssertEqual(operations.updateCalls.count, 1)
        guard let itemClass = operations.updateCalls[0].query[kSecClass as String] else {
            return XCTFail("Expected a generic-password query")
        }
        XCTAssertEqual(String(describing: itemClass), String(describing: kSecClassGenericPassword))
        guard let protection = operations.updateCalls[0].attributes[kSecAttrAccessible as String] else {
            return XCTFail("Expected device-only Keychain protection")
        }
        XCTAssertEqual(String(describing: protection), String(describing: kSecAttrAccessibleWhenUnlockedThisDeviceOnly))
    }

    func testKeychainSaveHandlesDuplicateAddByUpdating() throws {
        let operations = StubKeychainOperations(
            updateStatuses: [errSecItemNotFound, errSecSuccess],
            addStatuses: [errSecDuplicateItem]
        )
        let store = KeychainStore(operations: operations)

        try store.savePassword("secret-value")

        XCTAssertEqual(operations.addCalls.count, 1)
        XCTAssertEqual(operations.updateCalls.count, 2)
    }

    func testKeychainSaveReportsActualStatusWithoutPassword() {
        let operations = StubKeychainOperations(
            updateStatuses: [errSecParam],
            addStatuses: [errSecAuthFailed],
            deleteStatuses: [errSecSuccess]
        )
        let store = KeychainStore(operations: operations)

        XCTAssertThrowsError(try store.savePassword("secret-value")) { error in
            guard case KeychainError.unableToSave(let status) = error else {
                return XCTFail("Expected a status-bearing Keychain error")
            }
            XCTAssertEqual(status, errSecAuthFailed)
            XCTAssertTrue(error.localizedDescription.contains(String(errSecAuthFailed)))
            XCTAssertFalse(error.localizedDescription.contains("secret-value"))
        }
    }
}

private final class StubKeychainOperations: KeychainOperations {
    struct UpdateCall {
        let query: [String: Any]
        let attributes: [String: Any]
    }

    var updateCalls: [UpdateCall] = []
    var addCalls: [[String: Any]] = []
    private var updateStatuses: [OSStatus]
    private var addStatuses: [OSStatus]
    private var deleteStatuses: [OSStatus]

    init(updateStatuses: [OSStatus] = [], addStatuses: [OSStatus] = [], deleteStatuses: [OSStatus] = []) {
        self.updateStatuses = updateStatuses
        self.addStatuses = addStatuses
        self.deleteStatuses = deleteStatuses
    }

    func add(_ item: [String: Any]) -> OSStatus {
        addCalls.append(item)
        return addStatuses.isEmpty ? errSecSuccess : addStatuses.removeFirst()
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updateCalls.append(UpdateCall(query: query, attributes: attributes))
        return updateStatuses.isEmpty ? errSecSuccess : updateStatuses.removeFirst()
    }

    func copyData(matching query: [String: Any]) -> (status: OSStatus, data: Data?) {
        (errSecItemNotFound, nil)
    }

    func delete(matching query: [String: Any]) -> OSStatus {
        deleteStatuses.isEmpty ? errSecSuccess : deleteStatuses.removeFirst()
    }
}
