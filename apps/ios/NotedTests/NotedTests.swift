import XCTest
import Security
@testable import Noted

final class NotedTests: XCTestCase {
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
        XCTAssertEqual(decoded.meetingID, recording.id)
        XCTAssertEqual(decoded.device, .iPhone)
        XCTAssertEqual(decoded.recordingSource.sourceID, recording.id)
    }

    func testLegacyRecordingMigratesToOneIPhoneSourceInOneMeeting() throws {
        let id = UUID()
        let startedAt = Date(timeIntervalSinceReferenceDate: 12_345)
        let endedAt = startedAt.addingTimeInterval(8)
        let recording = LocalRecording(
            id: id,
            localFileURL: URL(fileURLWithPath: "/tmp/legacy.m4a"),
            createdAt: startedAt,
            duration: 8,
            title: "Legacy meeting",
            state: .localOnly,
            uploadAttempts: 0,
            serverSourceId: nil,
            byteSize: 12,
            bookmarks: [],
            lastError: nil,
            consentMode: "meeting",
            consentAcknowledged: true,
            finalizedAt: endedAt
        )

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recording)) as? [String: Any])
        legacyObject["schemaVersion"] = 2
        for key in ["meetingID", "device", "sourceStartedAt", "sourceEndedAt", "sourceTransferState", "clockOffset", "synchronizationQuality"] {
            legacyObject.removeValue(forKey: key)
        }
        let migrated = try JSONDecoder().decode(LocalRecording.self, from: JSONSerialization.data(withJSONObject: legacyObject))

        XCTAssertEqual(migrated.meetingID, id)
        XCTAssertEqual(migrated.sourceID, id)
        XCTAssertEqual(migrated.device, .iPhone)
        XCTAssertEqual(migrated.sourceStartedAt, startedAt)
        XCTAssertEqual(migrated.sourceEndedAt, endedAt)
        XCTAssertEqual(migrated.sourceTransferState, .local)

        let capture = try XCTUnwrap(MeetingCapture.group([migrated]).first)
        XCTAssertEqual(capture.id, id)
        XCTAssertEqual(capture.state, .completed)
        XCTAssertEqual(capture.sources.count, 1)
        XCTAssertEqual(capture.sources[0].sourceID, id)
        XCTAssertEqual(capture.sources[0].device, .iPhone)
        XCTAssertEqual(capture.sources[0].fileName, "legacy.m4a")
    }

    func testMeetingCaptureKeepsIndependentSourceTracksTogether() throws {
        let base = Date(timeIntervalSinceReferenceDate: 42_000)
        let meetingID = UUID()
        let iPhoneID = UUID()
        let watchID = UUID()
        let iPhone = LocalRecording(
            id: iPhoneID,
            localFileURL: URL(fileURLWithPath: "/tmp/iphone.m4a"),
            createdAt: base,
            duration: 10,
            title: "Dual meeting",
            state: .localOnly,
            uploadAttempts: 0,
            serverSourceId: nil,
            byteSize: 10,
            bookmarks: [],
            lastError: nil,
            consentMode: "meeting",
            consentAcknowledged: true,
            finalizedAt: base.addingTimeInterval(10),
            meetingID: meetingID,
            device: .iPhone,
            sourceStartedAt: base,
            sourceEndedAt: base.addingTimeInterval(10)
        )
        let watch = LocalRecording(
            id: watchID,
            localFileURL: URL(fileURLWithPath: "/tmp/watch.m4a"),
            createdAt: base.addingTimeInterval(0.2),
            duration: 9.8,
            title: "Dual meeting",
            state: .localOnly,
            uploadAttempts: 0,
            serverSourceId: nil,
            byteSize: 11,
            bookmarks: [],
            lastError: nil,
            consentMode: "meeting",
            consentAcknowledged: true,
            finalizedAt: base.addingTimeInterval(10),
            meetingID: meetingID,
            device: .appleWatch,
            sourceStartedAt: base.addingTimeInterval(0.2),
            sourceEndedAt: base.addingTimeInterval(10),
            sourceTransferState: .acknowledged,
            synchronizationQuality: .unknown
        )

        let capture = try XCTUnwrap(MeetingCapture.group([iPhone, watch]).first)

        XCTAssertEqual(capture.id, meetingID)
        XCTAssertEqual(capture.state, .completed)
        XCTAssertEqual(capture.sources.map(\.sourceID), [iPhoneID, watchID])
        XCTAssertEqual(capture.sources.map(\.device), [.iPhone, .appleWatch])
        XCTAssertEqual(Set(capture.sources.map(\.fileName)), ["iphone.m4a", "watch.m4a"])
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

    func testWatchTransferManifestRoundTripsThroughFileMetadata() throws {
        let sourceID = UUID()
        let manifest = WatchTransferManifest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: UUID(),
            sourceID: sourceID,
            sequence: 0,
            fileName: "\(sourceID.uuidString).m4a",
            createdAt: Date(),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(12),
            duration: 12,
            byteSize: 42,
            sha256: String(repeating: "a", count: 64),
            format: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 24_000, channels: 1, bitrate: 48_000),
            marks: [WatchCaptureMark(id: UUID(), createdAt: Date(), sourceElapsedTime: 4.5)]
        )

        let decoded = try WatchCaptureProtocol.manifest(from: WatchCaptureProtocol.fileMetadata(for: manifest))

        XCTAssertEqual(decoded, manifest)
    }

    func testWatchTransferAcknowledgementRoundTripsThroughUserInfo() throws {
        let ack = WatchDurableAck(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            sourceID: UUID(),
            sequence: 0,
            sha256: String(repeating: "b", count: 64),
            acknowledgedAt: Date()
        )

        let decoded = try WatchCaptureProtocol.ack(from: WatchCaptureProtocol.ackUserInfo(for: ack))

        XCTAssertEqual(decoded, ack)
    }

    func testWatchAcknowledgementStatusRequestRoundTripsThroughUserInfo() throws {
        let request = WatchAcknowledgementStatusRequest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            sourceID: UUID(),
            sequence: 2,
            sha256: String(repeating: "c", count: 64)
        )

        let decoded = try WatchCaptureProtocol.acknowledgementStatusRequest(from: WatchCaptureProtocol.acknowledgementStatusRequestUserInfo(for: request))

        XCTAssertEqual(decoded, request)
    }

    func testWatchStartCommandRoundTripsAndCarriesMeetingIdentity() throws {
        let meetingID = UUID()
        let request = WatchStartCaptureRequest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: meetingID,
            commandID: UUID(),
            title: "Dual meeting",
            requestedAt: Date()
        )
        let ack = WatchStartCaptureAck(
            protocolVersion: request.protocolVersion,
            meetingID: meetingID,
            commandID: request.commandID,
            accepted: true,
            isRecording: true,
            alreadyHandled: false,
            sourceID: UUID(),
            startedAt: request.requestedAt.addingTimeInterval(0.04),
            error: nil
        )

        XCTAssertEqual(try WatchCaptureProtocol.startRequest(from: WatchCaptureProtocol.startRequestMessage(for: request)), request)
        XCTAssertEqual(try WatchCaptureProtocol.startAck(from: WatchCaptureProtocol.startAckMessage(for: ack)), ack)
    }

    func testWatchStopCommandRoundTripsConfirmationAndCompletion() throws {
        let request = WatchStopCaptureRequest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: UUID(),
            commandID: UUID(),
            requestedAt: Date()
        )
        let pending = WatchStopCaptureAck(
            protocolVersion: request.protocolVersion,
            meetingID: request.meetingID,
            commandID: request.commandID,
            accepted: true,
            completed: false,
            requiresConfirmation: true,
            sourceID: UUID(),
            endedAt: nil,
            error: "Confirm Stop on the Apple Watch to finalize this source."
        )
        let completed = WatchStopCaptureAck(
            protocolVersion: request.protocolVersion,
            meetingID: request.meetingID,
            commandID: request.commandID,
            accepted: true,
            completed: true,
            requiresConfirmation: false,
            sourceID: pending.sourceID,
            endedAt: request.requestedAt.addingTimeInterval(5),
            error: nil
        )

        XCTAssertEqual(try WatchCaptureProtocol.stopRequest(from: WatchCaptureProtocol.stopRequestMessage(for: request)), request)
        XCTAssertEqual(try WatchCaptureProtocol.stopAck(from: WatchCaptureProtocol.stopAckMessage(for: pending)), pending)
        XCTAssertEqual(try WatchCaptureProtocol.stopAck(from: WatchCaptureProtocol.stopAckMessage(for: completed)), completed)
    }

    func testWatchStartAckRejectsAcceptedResponseWithoutSourceIdentity() throws {
        let acknowledgement = WatchStartCaptureAck(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: UUID(),
            commandID: UUID(),
            accepted: true,
            isRecording: true,
            alreadyHandled: false,
            sourceID: nil,
            startedAt: Date(),
            error: nil
        )

        XCTAssertThrowsError(try WatchCaptureProtocol.startAckMessage(for: acknowledgement)) { error in
            XCTAssertEqual(error as? WatchCaptureProtocolError, .invalidStartAcknowledgement)
        }
    }

    func testWatchTransferChecksumAndByteSizeAreStable() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-spike-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("watch spike audio".utf8).write(to: url)

        XCTAssertEqual(try WatchCaptureProtocol.byteSize(of: url), 17)
        XCTAssertEqual(try WatchCaptureProtocol.checksum(of: url).count, 64)
        XCTAssertEqual(try WatchCaptureProtocol.checksum(of: url), try WatchCaptureProtocol.checksum(of: url))
    }

    func testWatchTransferStoreIsIdempotentAndRejectsManifestMismatch() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let input = base.appendingPathComponent("input.m4a")
        let payload = Data("watch transfer payload".utf8)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try payload.write(to: input)

        let sourceID = UUID()
        let manifest = WatchTransferManifest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: nil,
            sourceID: sourceID,
            sequence: 0,
            fileName: input.lastPathComponent,
            createdAt: Date(),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(3),
            duration: 3,
            byteSize: Int64(payload.count),
            sha256: try WatchCaptureProtocol.checksum(of: input),
            format: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 24_000, channels: 1, bitrate: 48_000),
            marks: []
        )
        let store = WatchTransferStore(durableDirectory: base.appendingPathComponent("durable", isDirectory: true))

        let first = try store.ingest(fileURL: input, manifest: manifest)
        let second = try store.ingest(fileURL: input, manifest: manifest)

        let statusRequest = WatchAcknowledgementStatusRequest(
            protocolVersion: manifest.protocolVersion,
            sourceID: manifest.sourceID,
            sequence: manifest.sequence,
            sha256: manifest.sha256
        )
        let durableAck = try XCTUnwrap(store.durableAcknowledgement(for: statusRequest))

        XCTAssertFalse(first.wasExisting)
        XCTAssertTrue(second.wasExisting)
        XCTAssertEqual(durableAck.sourceID, manifest.sourceID)
        XCTAssertEqual(durableAck.sha256, manifest.sha256)
        XCTAssertEqual(try Data(contentsOf: first.destinationURL), payload)
        XCTAssertEqual(first.destinationURL, second.destinationURL)
        XCTAssertEqual(first.manifestURL, second.manifestURL)

        try Data("corrupt durable copy".utf8).write(to: first.destinationURL)
        XCTAssertThrowsError(try store.durableAcknowledgement(for: statusRequest)) { error in
            XCTAssertEqual(error as? WatchCaptureProtocolError, .checksumMismatch)
        }

        let mismatchedManifest = WatchTransferManifest(
            protocolVersion: manifest.protocolVersion,
            meetingID: manifest.meetingID,
            sourceID: manifest.sourceID,
            sequence: manifest.sequence,
            fileName: manifest.fileName,
            createdAt: manifest.createdAt,
            startedAt: manifest.startedAt,
            endedAt: manifest.endedAt.addingTimeInterval(1),
            duration: manifest.duration,
            byteSize: manifest.byteSize,
            sha256: manifest.sha256,
            format: manifest.format,
            marks: manifest.marks
        )
        XCTAssertThrowsError(try store.ingest(fileURL: input, manifest: mismatchedManifest)) { error in
            XCTAssertEqual(error as? WatchCaptureProtocolError, .manifestMismatch)
        }
    }

    func testWatchTransferStoreRepairsCorruptExistingCopyOnRetry() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let input = base.appendingPathComponent("input.m4a")
        let payload = Data("valid watch transfer payload".utf8)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try payload.write(to: input)

        let sourceID = UUID()
        let manifest = WatchTransferManifest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: nil,
            sourceID: sourceID,
            sequence: 0,
            fileName: input.lastPathComponent,
            createdAt: Date(),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(3),
            duration: 3,
            byteSize: Int64(payload.count),
            sha256: try WatchCaptureProtocol.checksum(of: input),
            format: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 24_000, channels: 1, bitrate: 48_000),
            marks: []
        )
        let store = WatchTransferStore(durableDirectory: base.appendingPathComponent("durable", isDirectory: true))
        let first = try store.ingest(fileURL: input, manifest: manifest)
        try Data("corrupt".utf8).write(to: first.destinationURL)

        let retried = try store.ingest(fileURL: input, manifest: manifest)

        XCTAssertTrue(retried.wasExisting)
        XCTAssertEqual(try Data(contentsOf: retried.destinationURL), payload)
    }

    func testWatchTransferImportsIntoTheExistingLocalRecordingLibrary() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let input = base.appendingPathComponent("input.m4a")
        let payload = Data("watch recording payload".utf8)
        try payload.write(to: input)
        let sourceID = UUID()
        let mark = WatchCaptureMark(id: UUID(), createdAt: Date(), sourceElapsedTime: 1.5)
        let manifest = WatchTransferManifest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: nil,
            sourceID: sourceID,
            sequence: 0,
            fileName: input.lastPathComponent,
            createdAt: Date(),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(4),
            duration: 4,
            byteSize: Int64(payload.count),
            sha256: try WatchCaptureProtocol.checksum(of: input),
            format: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 16_000, channels: 1, bitrate: 32_000),
            marks: [mark]
        )

        let transferStore = WatchTransferStore(durableDirectory: base.appendingPathComponent("durable", isDirectory: true))
        let received = try transferStore.ingest(fileURL: input, manifest: manifest)
        let localStore = LocalRecordingStore(baseDirectory: base.appendingPathComponent("local", isDirectory: true))
        let imported = try localStore.importWatchRecording(fileURL: received.destinationURL, manifest: manifest)

        XCTAssertEqual(imported.id, sourceID)
        XCTAssertEqual(imported.title, "Watch Recording")
        XCTAssertEqual(imported.state, .localOnly)
        XCTAssertEqual(imported.duration, manifest.duration)
        XCTAssertEqual(imported.fileName, "\(sourceID.uuidString).m4a")
        XCTAssertEqual(imported.bookmarks.first?.timestamp, mark.sourceElapsedTime)
        XCTAssertEqual(try Data(contentsOf: localStore.resolvedURL(for: imported)), payload)
    }

    func testWatchTransferImportsUseDistinctLocalFiles() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let localStore = LocalRecordingStore(baseDirectory: base.appendingPathComponent("local", isDirectory: true))
        var importedFileNames = Set<String>()
        for _ in 0..<2 {
            let sourceID = UUID()
            let input = base.appendingPathComponent("\(sourceID.uuidString).m4a")
            let payload = Data(sourceID.uuidString.utf8)
            try payload.write(to: input)
            let manifest = WatchTransferManifest(
                protocolVersion: WatchTransferManifest.currentProtocolVersion,
                meetingID: nil,
                sourceID: sourceID,
                sequence: 0,
                fileName: input.lastPathComponent,
                createdAt: Date(),
                startedAt: Date(),
                endedAt: Date().addingTimeInterval(1),
                duration: 1,
                byteSize: Int64(payload.count),
                sha256: try WatchCaptureProtocol.checksum(of: input),
                format: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 16_000, channels: 1, bitrate: 32_000),
                marks: []
            )

            let imported = try localStore.importWatchRecording(fileURL: input, manifest: manifest)
            importedFileNames.insert(imported.fileName)
        }

        XCTAssertEqual(importedFileNames.count, 2)
    }

    func testWatchTransferProtocolRejectsUnsupportedVersions() throws {
        let manifest = WatchTransferManifest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion + 1,
            meetingID: nil,
            sourceID: UUID(),
            sequence: 0,
            fileName: "future.m4a",
            createdAt: Date(),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(1),
            duration: 1,
            byteSize: 1,
            sha256: String(repeating: "a", count: 64),
            format: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 24_000, channels: 1, bitrate: 48_000),
            marks: []
        )
        XCTAssertThrowsError(try WatchCaptureProtocol.manifest(from: WatchCaptureProtocol.fileMetadata(for: manifest))) { error in
            XCTAssertEqual(error as? WatchCaptureProtocolError, .invalidManifest)
        }
    }

    func testWatchTransferProtocolRejectsInvalidManifestValues() throws {
        let manifest = WatchTransferManifest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: nil,
            sourceID: UUID(),
            sequence: 0,
            fileName: "empty.m4a",
            createdAt: Date(),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(1),
            duration: 1,
            byteSize: 0,
            sha256: String(repeating: "z", count: 64),
            format: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 24_000, channels: 1, bitrate: 48_000),
            marks: []
        )

        XCTAssertThrowsError(try WatchCaptureProtocol.fileMetadata(for: manifest)) { error in
            XCTAssertEqual(error as? WatchCaptureProtocolError, .invalidManifest)
        }
    }

    func testWatchTransferStoreRejectsEmptyPayloadBeforeDurableCopy() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let input = base.appendingPathComponent("empty.m4a")
        try Data().write(to: input)

        let manifest = WatchTransferManifest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: nil,
            sourceID: UUID(),
            sequence: 0,
            fileName: input.lastPathComponent,
            createdAt: Date(),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(1),
            duration: 1,
            byteSize: 0,
            sha256: try WatchCaptureProtocol.checksum(of: input),
            format: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 24_000, channels: 1, bitrate: 48_000),
            marks: []
        )
        let durableDirectory = base.appendingPathComponent("durable", isDirectory: true)
        let store = WatchTransferStore(durableDirectory: durableDirectory)

        XCTAssertThrowsError(try store.ingest(fileURL: input, manifest: manifest)) { error in
            XCTAssertEqual(error as? WatchCaptureProtocolError, .invalidManifest)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: durableDirectory.appendingPathComponent("\(manifest.sourceID.uuidString)-0.m4a").path))
    }

    func testWatchControlPayloadsRejectInvalidOutboundValues() throws {
        let sourceID = UUID()
        let invalidAck = WatchDurableAck(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            sourceID: sourceID,
            sequence: -1,
            sha256: String(repeating: "a", count: 64),
            acknowledgedAt: Date()
        )
        XCTAssertThrowsError(try WatchCaptureProtocol.ackUserInfo(for: invalidAck)) { error in
            XCTAssertEqual(error as? WatchCaptureProtocolError, .invalidAcknowledgement)
        }

        let invalidRequest = WatchAcknowledgementStatusRequest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            sourceID: sourceID,
            sequence: 0,
            sha256: String(repeating: "g", count: 64)
        )
        XCTAssertThrowsError(try WatchCaptureProtocol.acknowledgementStatusRequestUserInfo(for: invalidRequest)) { error in
            XCTAssertEqual(error as? WatchCaptureProtocolError, .invalidStatusRequest)
        }
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

    func testCalendarCandidateDateBuilderUsesCurrentYearForMonthDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12)))
        let candidate = CalendarCandidate(
            id: "doctor-follow-up",
            title: "Doctor follow-up",
            dateText: "November 10",
            timeText: "10:45 AM",
            datePrecision: "month_day",
            confidence: 0.82,
            state: .generated,
            needsConfirmation: true,
            evidenceRefs: []
        )

        let date = try XCTUnwrap(CalendarCandidateDateBuilder.startDate(for: candidate, calendar: calendar, now: now))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 45)
    }

    func testCalendarLinkStoreReplacesTheSameCandidateIdempotently() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = CalendarLinkStore(baseDirectory: base)
        let first = CalendarEventLink(
            sourceID: "source-1",
            candidateID: "candidate-1",
            eventIdentifier: "event-1",
            calendarIdentifier: "calendar-1",
            calendarTitle: "Personal",
            title: "Doctor follow-up",
            startDate: Date(timeIntervalSinceReferenceDate: 10),
            endDate: Date(timeIntervalSinceReferenceDate: 1_810),
            createdAt: Date(timeIntervalSinceReferenceDate: 20)
        )
        let replacement = CalendarEventLink(
            sourceID: first.sourceID,
            candidateID: first.candidateID,
            eventIdentifier: "event-2",
            calendarIdentifier: first.calendarIdentifier,
            calendarTitle: first.calendarTitle,
            title: first.title,
            startDate: first.startDate,
            endDate: first.endDate,
            createdAt: Date(timeIntervalSinceReferenceDate: 30)
        )

        try store.save(first)
        XCTAssertEqual(store.link(for: first.sourceID, candidateID: first.candidateID), first)
        try store.save(replacement)
        XCTAssertEqual(store.load(), [replacement])
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
