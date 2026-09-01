import AVFoundation
import Combine
import Foundation
@preconcurrency import WatchConnectivity
import WatchKit
import os

enum WatchAudioProfile: String, CaseIterable, Identifiable, Codable {
    case speech16 = "16 kHz · 32 kbps"
    case speech24 = "24 kHz · 48 kbps"
    case speech32 = "32 kHz · 64 kbps"

    var id: String { rawValue }

    var format: WatchAudioFormat {
        switch self {
        case .speech16: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 16_000, channels: 1, bitrate: 32_000)
        case .speech24: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 24_000, channels: 1, bitrate: 48_000)
        case .speech32: WatchAudioFormat(codec: "AAC-LC", container: "m4a", sampleRate: 32_000, channels: 1, bitrate: 64_000)
        }
    }
}

struct WatchSpikeRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    var startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval
    var profile: WatchAudioProfile
    var state: WatchTransferState
    var lifecycleState: WatchCaptureLifecycleState?
    var byteSize: Int64
    var sha256: String?
    var marks: [WatchCaptureMark]
    var error: String?
    var durableAcknowledgedAt: Date?
    var deviceModel: String?
    var operatingSystem: String?
    var startBatteryLevel: Double?
    var endBatteryLevel: Double?
    var startRoute: String?
    var endRoute: String?
    var routeChanges: [String]?
    var interruptionReason: String?
}

@MainActor
final class WatchSpikeRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, WatchConnectivityCoordinatorDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var records: [WatchSpikeRecord] = []
    @Published private(set) var message: String?
    @Published private(set) var resourceWarnings: [String] = []
    // 16 kHz AAC is the documented Watch speech profile and is the safest
    // default across physical watchOS audio routes. The higher-rate profiles
    // remain available for comparison, with startup fallback below if a route
    // rejects their recorder settings.
    @Published var selectedProfile: WatchAudioProfile = .speech16
    @Published var isStopConfirmationPresented = false
    @Published var isDeleteConfirmationPresented = false

    private let logger = Logger(subsystem: "com.shepswork.noted.watchkitapp", category: "WatchRecorder")
    private let fileManager = FileManager.default
    private let recordsURL: URL
    private let recordsBackupURL: URL
    private let recordingsDirectory: URL
    private var recorder: AVAudioRecorder?
    private var activeID: UUID?
    private var startedAt: Date?
    private var startedUptime: TimeInterval?
    private var ticker: Task<Void, Never>?
    private var marks: [WatchCaptureMark] = []
    private var stoppingForStorage = false
    private var pendingDeletionID: UUID?

    private let storageWarningBytes: Int64 = 256 * 1024 * 1024
    private let storageCriticalBytes: Int64 = 16 * 1024 * 1024
    private let lowBatteryThreshold = 0.20

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("NotedWatchSpike", isDirectory: true)
        recordingsDirectory = root.appendingPathComponent("Recordings", isDirectory: true)
        recordsURL = root.appendingPathComponent("records.json")
        recordsBackupURL = root.appendingPathComponent("records.json.bak")
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        records = loadRecords()
        WatchConnectivityCoordinator.shared.delegate = self
        WatchConnectivityCoordinator.shared.activate()
        recoverOrphanedAudioFiles()
        recoverInterruptedRecord()
        reconcilePersistedFiles()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        ticker?.cancel()
    }

    func start() async {
        guard !isRecording else { return }
        message = nil
        stoppingForStorage = false
        updateResourceWarnings()
        if let available = availableStorageBytes(), available < storageCriticalBytes {
            message = "Not enough Watch storage to start safely. Free space before recording."
            return
        }
        guard await requestMicrophonePermission() else {
            message = "Microphone access is denied. Enable it in Watch Settings to run the spike."
            return
        }

        let id = UUID()
        let startDate = Date()
        let fileURL = recordingsDirectory.appendingPathComponent("\(id.uuidString).m4a")
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .spokenAudio, options: [])
            try await activateAudioSession(session)
            let (recorder, recordingProfile) = try makePreparedRecorder(at: fileURL)
            recorder.delegate = self

            let record = WatchSpikeRecord(
                id: id,
                fileName: fileURL.lastPathComponent,
                createdAt: startDate,
                startedAt: startDate,
                endedAt: nil,
                duration: 0,
                profile: recordingProfile,
                state: .local,
                lifecycleState: .preparing,
                byteSize: 0,
                sha256: nil,
                marks: [],
                error: nil,
                durableAcknowledgedAt: nil,
                deviceModel: WKInterfaceDevice.current().model,
                operatingSystem: WKInterfaceDevice.current().systemVersion,
                startBatteryLevel: currentBatteryLevel(),
                endBatteryLevel: nil,
                startRoute: currentAudioRoute(),
                endRoute: nil,
                routeChanges: [],
                interruptionReason: nil
            )
            records.insert(record, at: 0)
            try saveRecords()
            guard recorder.record() else { throw WatchSpikeError.couldNotStart }
            self.recorder = recorder
            activeID = id
            startedAt = startDate
            startedUptime = ProcessInfo.processInfo.systemUptime
            marks = []
            elapsed = 0
            if let index = records.firstIndex(where: { $0.id == id }) {
                records[index].lifecycleState = .recording
                persistRecords(context: "recording started")
            }
            isRecording = true
            WKInterfaceDevice.current().play(.start)
            startTicker()
            logger.info("Recording started source=\(id.uuidString, privacy: .public) profile=\(recordingProfile.rawValue, privacy: .public) sessionSampleRate=\(session.sampleRate, privacy: .public)")
        } catch {
            try? session.setActive(false)
            if let index = records.firstIndex(where: { $0.id == id }) {
                let size = (try? WatchCaptureProtocol.byteSize(of: fileURL)) ?? 0
                if size == 0 {
                    records.remove(at: index)
                    try? fileManager.removeItem(at: fileURL)
                } else {
                    records[index].state = .interrupted
                    records[index].lifecycleState = .recordingFailed
                    records[index].endedAt = Date()
                    records[index].byteSize = size
                    records[index].error = error.localizedDescription
                    records[index].interruptionReason = error.localizedDescription
                }
                persistRecords(context: "recording start failure")
            }
            message = error.localizedDescription
            logger.error("Recording start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func mark() {
        guard isRecording, let startedAt else { return }
        let mark = WatchCaptureMark(id: UUID(), createdAt: Date(), sourceElapsedTime: currentElapsedTime(from: startedAt))
        marks.append(mark)
        if let activeID, let index = records.firstIndex(where: { $0.id == activeID }) {
            records[index].marks = marks
            persistRecords(context: "mark")
        }
        WKInterfaceDevice.current().play(.click)
    }

    func requestStop() {
        guard isRecording else { return }
        isStopConfirmationPresented = true
        if let activeID, let index = records.firstIndex(where: { $0.id == activeID }) {
            records[index].lifecycleState = .stopConfirmation
            persistRecords(context: "stop confirmation")
        }
    }

    func cancelStop() {
        isStopConfirmationPresented = false
        guard isRecording,
              let activeID,
              let index = records.firstIndex(where: { $0.id == activeID }) else { return }
        records[index].lifecycleState = .recording
        persistRecords(context: "stop cancelled")
    }

    func confirmStop() {
        isStopConfirmationPresented = false
        guard isRecording else { return }
        if let activeID, let index = records.firstIndex(where: { $0.id == activeID }) {
            records[index].lifecycleState = .stopping
            persistRecords(context: "stop requested")
        }
        WKInterfaceDevice.current().play(.stop)
        recorder?.stop()
    }

    func retry(_ record: WatchSpikeRecord) {
        guard record.state != .acknowledged else { return }
        let fileURL = recordingsDirectory.appendingPathComponent(record.fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            message = "The local Watch audio file is missing."
            return
        }
        do {
            let manifest = try manifest(for: record, fileURL: fileURL)
            try queueTransfer(manifest: manifest, fileURL: fileURL, recordID: record.id)
            message = "Transfer queued. The Watch copy stays until iPhone acknowledgement."
        } catch {
            message = error.localizedDescription
        }
    }

    var deleteConfirmationMessage: String {
        guard let pendingDeletionID,
              let record = records.first(where: { $0.id == pendingDeletionID }) else {
            return "This recording will be removed from the Watch."
        }
        if record.state != .acknowledged {
            return "This recording has not been copied to your iPhone. Delete it anyway?"
        }
        return "This recording will be removed from the Watch."
    }

    func requestDelete(_ record: WatchSpikeRecord) {
        guard !isRecording || record.id != activeID else {
            message = "Stop the active recording before deleting it."
            return
        }
        pendingDeletionID = record.id
        isDeleteConfirmationPresented = true
    }

    func cancelDelete() {
        isDeleteConfirmationPresented = false
        pendingDeletionID = nil
    }

    func confirmDelete() {
        isDeleteConfirmationPresented = false
        guard let pendingDeletionID,
              let index = records.firstIndex(where: { $0.id == pendingDeletionID }) else {
            self.pendingDeletionID = nil
            return
        }

        let record = records[index]
        let fileURL = recordingsDirectory.appendingPathComponent(record.fileName)
        let previousRecords = records
        records.remove(at: index)
        do {
            try saveRecords()
        } catch {
            records = previousRecords
            self.pendingDeletionID = nil
            message = "The recording could not be deleted. The Watch audio was retained."
            logger.error("Could not persist manual Watch deletion source=\(record.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            self.pendingDeletionID = nil
            message = "Recording deleted from the Watch."
            logger.info("Manually deleted Watch recording source=\(record.id.uuidString, privacy: .public)")
        } catch {
            records = previousRecords
            do {
                try saveRecords()
            } catch {
                logger.error("Could not restore Watch metadata after deletion cleanup failure source=\(record.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            self.pendingDeletionID = nil
            message = "The recording could not be deleted. The Watch audio was retained."
            logger.error("Could not remove manually deleted Watch audio source=\(record.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func format(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.finalize(successfully: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.finalize(successfully: false, error: error?.localizedDescription)
        }
    }

    func watchConnectivityDidActivate(_ activationState: WCSessionActivationState, error: Error?) {
        if let error {
            logger.error("WatchConnectivity activation failed: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.info("WatchConnectivity activated: \(String(describing: activationState), privacy: .public)")
            reconcileOutstandingTransfers()
        }
    }

    func watchConnectivityDidReceive(_ acknowledgement: WatchDurableAck) {
        apply(ack: acknowledgement)
    }

    func watchConnectivityDidFinishFileTransfer(fileName: String, error: Error?) {
        guard let index = records.firstIndex(where: { $0.fileName == fileName }) else { return }
        if let error {
            records[index].state = .failed
            records[index].lifecycleState = .transferFailed
            records[index].error = "WatchConnectivity transfer failed: \(error.localizedDescription)"
            persistRecords(context: "native transfer failure")
            message = "The Watch transfer failed. The local audio was retained for retry."
            logger.error("Watch transfer failed source=\(self.records[index].id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        guard records[index].state != .acknowledged else { return }
        records[index].state = .awaitingAck
        records[index].lifecycleState = .awaitingDurableAck
        records[index].error = nil
        persistRecords(context: "native transfer completed")
        message = "iPhone received the Watch transfer. Waiting for durable acknowledgement."
        logger.info("Watch transfer delivered source=\(self.records[index].id.uuidString, privacy: .public); awaiting durable acknowledgement")
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard isRecording,
              let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }

        if type == .began {
            recorder?.pause()
            ticker?.cancel()
            persistActiveDuration()
            if let activeID, let index = records.firstIndex(where: { $0.id == activeID }) {
                records[index].state = .interrupted
                records[index].lifecycleState = .interrupted
                records[index].error = "The Watch audio session was interrupted."
                records[index].interruptionReason = "AVAudioSession interruption began"
                persistRecords(context: "audio interruption")
            }
            message = "Recording interrupted. Stop to preserve the captured audio."
            logger.error("Recording interrupted source=\(self.activeID?.uuidString ?? "unknown", privacy: .public)")
            return
        }

        guard type == .ended else { return }
        let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
        guard shouldResume else {
            message = "The microphone is still unavailable. Stop to preserve the captured audio."
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.resumeAfterInterruption()
        }
    }

    private func resumeAfterInterruption() async {
        do {
            try await activateAudioSession(AVAudioSession.sharedInstance())
            guard recorder?.record() == true else { throw WatchSpikeError.couldNotResume }
            if let activeID, let index = records.firstIndex(where: { $0.id == activeID }) {
                records[index].state = .local
                records[index].lifecycleState = .recording
                records[index].error = nil
                persistRecords(context: "audio interruption resume")
            }
            message = "Recording resumed after the audio interruption."
            startTicker()
            logger.info("Recording resumed after interruption source=\(self.activeID?.uuidString ?? "unknown", privacy: .public)")
        } catch {
            message = "The microphone could not resume. Stop to preserve the captured audio."
            logger.error("Recording could not resume after interruption: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard isRecording else { return }
        let route = currentAudioRoute() ?? "unknown"
        if let activeID, let index = records.firstIndex(where: { $0.id == activeID }) {
            records[index].routeChanges = (records[index].routeChanges ?? []) + [route]
            persistRecords(context: "audio route change")
        }
        message = "Audio route changed. Capturing the new route in spike evidence."
        logger.info("Audio route changed source=\(self.activeID?.uuidString ?? "unknown", privacy: .public) route=\(route, privacy: .public)")
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func activateAudioSession(_ session: AVAudioSession) async throws {
        if #available(watchOS 5.0, *) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.activate(options: []) { activated, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if activated {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: WatchSpikeError.audioSessionActivationFailed)
                    }
                }
            }
        } else {
            try session.setActive(true)
        }
    }

    private func makePreparedRecorder(at fileURL: URL) throws -> (AVAudioRecorder, WatchAudioProfile) {
        let requestedProfile = selectedProfile
        var candidates = [requestedProfile]
        if requestedProfile != .speech16 {
            candidates.append(.speech16)
        }

        var lastError: Error?
        for profile in candidates {
            do {
                let format = profile.format
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channels,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                    AVEncoderBitRateKey: format.bitrate
                ]
                let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
                guard recorder.prepareToRecord() else {
                    throw WatchSpikeError.couldNotPrepare(profile)
                }
                if profile != requestedProfile {
                    logger.error("Selected Watch audio profile was rejected; using fallback profile=\(profile.rawValue, privacy: .public) requested=\(requestedProfile.rawValue, privacy: .public)")
                }
                return (recorder, profile)
            } catch {
                lastError = error
                try? fileManager.removeItem(at: fileURL)
                logger.error("Watch audio profile setup failed profile=\(profile.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        throw lastError ?? WatchSpikeError.couldNotStart
    }

    private func reconcileOutstandingTransfers() {
        let connectivity = WatchConnectivityCoordinator.shared
        guard connectivity.isSupported else { return }
        let outstandingFileNames = connectivity.outstandingFileNames
        let pendingRecords = records.filter { $0.state == .queued || $0.state == .transferring || $0.state == .awaitingAck }

        for record in pendingRecords {
            requestAcknowledgementStatus(for: record, connectivity: connectivity)
            guard !outstandingFileNames.contains(record.fileName) else { continue }
            let fileURL = recordingsDirectory.appendingPathComponent(record.fileName)
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }
            do {
                let manifest = try manifest(for: record, fileURL: fileURL)
                try queueTransfer(manifest: manifest, fileURL: fileURL, recordID: record.id)
                logger.info("Requeued pending Watch transfer source=\(record.id.uuidString, privacy: .public)")
            } catch {
                message = "A pending Watch transfer could not be requeued."
                logger.error("Could not requeue pending Watch transfer source=\(record.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func requestAcknowledgementStatus(for record: WatchSpikeRecord, connectivity: WatchConnectivityCoordinator) {
        guard let sha256 = record.sha256 else { return }
        let request = WatchAcknowledgementStatusRequest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            sourceID: record.id,
            sequence: 0,
            sha256: sha256
        )
        do {
            try connectivity.queueUserInfo(try WatchCaptureProtocol.acknowledgementStatusRequestUserInfo(for: request))
            logger.info("Requested durable acknowledgement status source=\(record.id.uuidString, privacy: .public)")
        } catch {
            message = "A pending acknowledgement could not be reconciled yet."
            logger.error("Could not request durable acknowledgement status source=\(record.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if let startedAt = self.startedAt, self.isRecording {
                    self.elapsed = self.currentElapsedTime(from: startedAt)
                    self.persistActiveDuration()
                    self.updateResourceWarnings()
                    if let available = self.availableStorageBytes(), available < self.storageCriticalBytes, !self.stoppingForStorage {
                        self.stoppingForStorage = true
                        if let activeID = self.activeID, let index = self.records.firstIndex(where: { $0.id == activeID }) {
                            self.records[index].lifecycleState = .storageWarning
                            self.persistRecords(context: "critical storage warning")
                        }
                        self.message = "Watch storage is critically low. Finalizing the captured audio now."
                        self.recorder?.stop()
                    }
                }
            }
        }
    }

    private func persistActiveDuration() {
        guard let activeID, let index = records.firstIndex(where: { $0.id == activeID }) else { return }
        if let startedAt {
            elapsed = currentElapsedTime(from: startedAt)
        }
        records[index].duration = elapsed
        records[index].byteSize = byteSize(for: records[index])
        persistRecords(context: "recording duration checkpoint")
    }

    private func finalize(successfully: Bool, error: String? = nil) async {
        guard let activeID,
              let index = records.firstIndex(where: { $0.id == activeID }) else { return }
        ticker?.cancel()
        records[index].lifecycleState = .finalizing
        persistRecords(context: "finalization started")
        let record = records[index]
        let fileURL = recordingsDirectory.appendingPathComponent(record.fileName)
        let endedAt = Date()
        let duration = max(startedAt.map { currentElapsedTime(from: $0) } ?? elapsed, recorder?.currentTime ?? 0)
        records[index].endedAt = endedAt
        records[index].duration = duration
        records[index].byteSize = byteSize(for: records[index])
        records[index].marks = marks
        records[index].error = successfully ? nil : (error ?? "The recorder stopped before finalization completed.")
        records[index].endBatteryLevel = currentBatteryLevel()
        records[index].endRoute = currentAudioRoute()
        if !successfully {
            records[index].interruptionReason = records[index].error
        }

        self.recorder = nil
        self.activeID = nil
        self.startedAt = nil
        self.startedUptime = nil
        self.marks = []
        self.elapsed = 0
        self.isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)

        guard successfully else {
            records[index].state = .interrupted
            records[index].lifecycleState = .interrupted
            persistRecords(context: "interrupted finalization")
            message = records[index].error
            return
        }

        do {
            let manifest = try manifest(for: records[index], fileURL: fileURL)
            records[index].sha256 = manifest.sha256
            records[index].state = .queued
            records[index].lifecycleState = .queuedForTransfer
            try saveRecords()
            try queueTransfer(manifest: manifest, fileURL: fileURL, recordID: activeID)
            message = "Recording finalized. Transfer is queued; audio remains on Watch until acknowledgement."
            logger.info("Recording finalized source=\(activeID.uuidString, privacy: .public) duration=\(duration, privacy: .public) bytes=\(manifest.byteSize, privacy: .public) checksum=\(manifest.sha256, privacy: .public)")
        } catch {
            records[index].state = .failed
            records[index].lifecycleState = .transferFailed
            records[index].error = error.localizedDescription
            persistRecords(context: "transfer setup failure")
            message = error.localizedDescription
        }
    }

    private func manifest(for record: WatchSpikeRecord, fileURL: URL) throws -> WatchTransferManifest {
        guard let endedAt = record.endedAt else { throw WatchSpikeError.recordNotFinalized }
        let byteSize = try WatchCaptureProtocol.byteSize(of: fileURL)
        guard byteSize > 0 else { throw WatchSpikeError.emptyRecording }
        return WatchTransferManifest(
            protocolVersion: WatchTransferManifest.currentProtocolVersion,
            meetingID: nil,
            sourceID: record.id,
            sequence: 0,
            fileName: record.fileName,
            createdAt: record.createdAt,
            startedAt: record.startedAt,
            endedAt: endedAt,
            duration: record.duration,
            byteSize: byteSize,
            sha256: try WatchCaptureProtocol.checksum(of: fileURL),
            format: record.profile.format,
            marks: record.marks
        )
    }

    private func queueTransfer(manifest: WatchTransferManifest, fileURL: URL, recordID: UUID) throws {
        let connectivity = WatchConnectivityCoordinator.shared
        guard connectivity.isSupported else { throw WatchSpikeError.connectivityUnavailable }
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index].state = .transferring
            records[index].lifecycleState = .transferring
            records[index].sha256 = manifest.sha256
            records[index].byteSize = manifest.byteSize
            try saveRecords()
        }
        try connectivity.queueFile(fileURL: fileURL, metadata: try WatchCaptureProtocol.fileMetadata(for: manifest))
    }

    private func apply(ack: WatchDurableAck) {
        guard ack.sequence == 0,
              let index = records.firstIndex(where: { $0.id == ack.sourceID }),
              records[index].sha256 == ack.sha256 else { return }
        let fileURL = recordingsDirectory.appendingPathComponent(records[index].fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            message = "The acknowledgement arrived, but the local Watch audio is missing."
            logger.error("Ignoring acknowledgement because local audio is missing source=\(ack.sourceID.uuidString, privacy: .public)")
            return
        }
        let previousState = records[index].state
        records[index].state = .acknowledged
        records[index].lifecycleState = .transferred
        records[index].durableAcknowledgedAt = ack.acknowledgedAt
        records[index].error = nil
        do {
            try saveRecords()
        } catch {
            records[index].state = previousState
            records[index].lifecycleState = .awaitingDurableAck
            records[index].durableAcknowledgedAt = nil
            records[index].error = "The acknowledgement could not be persisted; audio was retained."
            message = records[index].error
            persistRecords(context: "acknowledgement rollback")
            logger.error("Could not persist durable acknowledgement source=\(ack.sourceID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            message = "Recording acknowledged. Watch cleanup will retry later."
            logger.error("Could not remove acknowledged Watch audio source=\(ack.sourceID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        message = "iPhone durably acknowledged the recording. The Watch audio was removed."
        logger.info("Durable acknowledgement applied source=\(ack.sourceID.uuidString, privacy: .public)")
    }

    private func recoverInterruptedRecord() {
        var changed = false
        for index in records.indices where (records[index].state == .local || records[index].state == .interrupted) && records[index].endedAt == nil {
            let fileURL = recordingsDirectory.appendingPathComponent(records[index].fileName)
            records[index].state = .interrupted
            records[index].lifecycleState = .interrupted
            records[index].error = "Recovered after the Watch recorder stopped without a normal stop."
            records[index].endedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            records[index].byteSize = (try? WatchCaptureProtocol.byteSize(of: fileURL)) ?? 0
            records[index].sha256 = try? WatchCaptureProtocol.checksum(of: fileURL)
            records[index].endBatteryLevel = currentBatteryLevel()
            records[index].endRoute = currentAudioRoute()
            records[index].interruptionReason = records[index].error
            changed = true
        }
        if changed {
            persistRecords(context: "interrupted recording recovery")
        }
    }

    private func recoverOrphanedAudioFiles() {
        let indexedFileNames = Set(records.map(\.fileName))
        let candidates = (try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var changed = false

        for fileURL in candidates where fileURL.pathExtension.lowercased() == "m4a" && !indexedFileNames.contains(fileURL.lastPathComponent) {
            let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let createdAt = values?.creationDate ?? Date()
            let modifiedAt = values?.contentModificationDate ?? createdAt
            let endedAt = max(modifiedAt, createdAt)
            let size = (try? WatchCaptureProtocol.byteSize(of: fileURL)) ?? 0
            let recoveredID = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) ?? UUID()
            let recovered = WatchSpikeRecord(
                id: recoveredID,
                fileName: fileURL.lastPathComponent,
                createdAt: createdAt,
                startedAt: createdAt,
                endedAt: endedAt,
                duration: audioDuration(for: fileURL),
                profile: inferredProfile(for: fileURL),
                state: .interrupted,
                lifecycleState: .interrupted,
                byteSize: size,
                sha256: size > 0 ? try? WatchCaptureProtocol.checksum(of: fileURL) : nil,
                marks: [],
                error: "Recovered a Watch audio file whose metadata was not fully saved. Audio was retained for retry.",
                durableAcknowledgedAt: nil,
                deviceModel: WKInterfaceDevice.current().model,
                operatingSystem: WKInterfaceDevice.current().systemVersion,
                startBatteryLevel: nil,
                endBatteryLevel: currentBatteryLevel(),
                startRoute: nil,
                endRoute: currentAudioRoute(),
                routeChanges: [],
                interruptionReason: "Watch metadata recovery found an unindexed audio file"
            )
            records.append(recovered)
            changed = true
            logger.error("Recovered unindexed Watch audio file (fileURL.lastPathComponent, privacy: .public)")
        }

        if changed {
            records.sort { $0.createdAt > $1.createdAt }
            persistRecords(context: "orphaned audio recovery")
        }
    }

    private func reconcilePersistedFiles() {
        var changed = false
        for index in records.indices {
            let record = records[index]
            let fileURL = recordingsDirectory.appendingPathComponent(record.fileName)
            let exists = fileManager.fileExists(atPath: fileURL.path)

            if record.state == .acknowledged {
                guard exists else { continue }
                do {
                    try fileManager.removeItem(at: fileURL)
                    logger.info("Removed acknowledged Watch audio during launch reconciliation source=\(record.id.uuidString, privacy: .public)")
                } catch {
                    message = "An acknowledged Watch recording is waiting for cleanup."
                    logger.error("Could not clean up acknowledged Watch audio source=\(record.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                continue
            }

            guard !exists,
                  record.state == .queued || record.state == .transferring || record.state == .awaitingAck || record.state == .local || record.state == .interrupted else {
                continue
            }
            records[index].state = .failed
            records[index].lifecycleState = .transferFailed
            records[index].error = "The local Watch audio file is missing; no transfer was acknowledged."
            records[index].interruptionReason = records[index].error
            changed = true
        }
        if changed {
            persistRecords(context: "missing local file reconciliation")
        }
    }

    private func persistRecords(context: String) {
        do {
            try saveRecords()
        } catch {
            message = "Watch capture status could not be saved. Audio was retained."
            logger.error("Could not persist Watch records context=\(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadRecords() -> [WatchSpikeRecord] {
        for url in [recordsURL, recordsBackupURL] {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([WatchSpikeRecord].self, from: data) else { continue }
            if url == recordsBackupURL {
                logger.error("Primary Watch record index was unavailable; restored the backup index")
            }
            return decoded
        }
        if fileManager.fileExists(atPath: recordsURL.path) || fileManager.fileExists(atPath: recordsBackupURL.path) {
            logger.error("Watch record indexes could not be decoded; retained audio will be scanned for recovery")
        }
        return []
    }

    private func saveRecords() throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: recordsURL, options: .atomic)
        do {
            try data.write(to: recordsBackupURL, options: .atomic)
        } catch {
            logger.error("Could not refresh the Watch record index backup: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func byteSize(for record: WatchSpikeRecord) -> Int64 {
        let url = recordingsDirectory.appendingPathComponent(record.fileName)
        return (try? WatchCaptureProtocol.byteSize(of: url)) ?? 0
    }

    private func audioDuration(for url: URL) -> TimeInterval {
        guard let audioFile = try? AVAudioFile(forReading: url),
              audioFile.processingFormat.sampleRate > 0 else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    private func inferredProfile(for url: URL) -> WatchAudioProfile {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return .speech24 }
        switch audioFile.processingFormat.sampleRate {
        case ..<20_000: return .speech16
        case ..<28_000: return .speech24
        default: return .speech32
        }
    }

    private func currentElapsedTime(from startedAt: Date) -> TimeInterval {
        if let startedUptime {
            return max(0, ProcessInfo.processInfo.systemUptime - startedUptime)
        }
        return max(0, Date().timeIntervalSince(startedAt))
    }

    private func currentBatteryLevel() -> Double? {
        let level = WKInterfaceDevice.current().batteryLevel
        return level >= 0 ? Double(level) : nil
    }

    private func currentAudioRoute() -> String? {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map { "in:\($0.portType.rawValue):\($0.portName)" }
        let outputs = route.outputs.map { "out:\($0.portType.rawValue):\($0.portName)" }
        let description = (inputs + outputs).joined(separator: ",")
        return description.isEmpty ? nil : description
    }

    private func updateResourceWarnings() {
        var warnings: [String] = []
        if let available = availableStorageBytes() {
            let minutes = estimatedMinutesRemaining(for: available)
            if available < storageCriticalBytes {
                warnings.append("Critical storage: about \(minutes) minutes remain.")
            } else if available < storageWarningBytes {
                warnings.append("Low storage: about \(minutes) minutes remain.")
            }
        }
        if let batteryLevel = currentBatteryLevel(), batteryLevel < lowBatteryThreshold {
            warnings.append("Battery low: long recordings may end early.")
        }
        resourceWarnings = warnings
    }

    private func availableStorageBytes() -> Int64? {
        guard let available = try? recordingsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity else {
            return nil
        }
        return Int64(available)
    }

    private func estimatedMinutesRemaining(for bytes: Int64) -> Int {
        let bytesPerSecond = max(1, Double(selectedProfile.format.bitrate) / 8.0 * 1.10)
        return max(0, Int((Double(bytes) / bytesPerSecond / 60.0).rounded(.down)))
    }
}

enum WatchSpikeError: LocalizedError {
    case couldNotStart
    case couldNotResume
    case couldNotPrepare(WatchAudioProfile)
    case audioSessionActivationFailed
    case recordNotFinalized
    case emptyRecording
    case connectivityUnavailable

    var errorDescription: String? {
        switch self {
        case .couldNotStart: "The Watch recorder could not start."
        case .couldNotResume: "The Watch recorder could not resume after an interruption."
        case .couldNotPrepare(let profile): "The Watch audio profile \(profile.rawValue) is not supported on the current audio route."
        case .audioSessionActivationFailed: "The Watch microphone session could not be activated."
        case .recordNotFinalized: "The Watch recording is not finalized yet."
        case .emptyRecording: "The Watch recording contains no audio to transfer."
        case .connectivityUnavailable: "WatchConnectivity is unavailable on this device."
        }
    }
}
