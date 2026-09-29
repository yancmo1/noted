import Foundation
import Combine

enum WatchCaptureStatus: Equatable {
    case idle
    case starting(meetingID: UUID)
    case recording(meetingID: UUID, sourceID: UUID)
    case unavailable(meetingID: UUID, message: String)
    case stopNeedsConfirmation(meetingID: UUID)
    case stopped(meetingID: UUID)
    case failed(meetingID: UUID, message: String)

    var meetingID: UUID? {
        switch self {
        case .idle: nil
        case .starting(let meetingID), .recording(let meetingID, _), .unavailable(let meetingID, _), .stopNeedsConfirmation(let meetingID), .stopped(let meetingID), .failed(let meetingID, _): meetingID
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let api: APIClient
    let localStore: LocalRecordingStore
    let audioRecorder: AudioRecorder
    let keychain = KeychainStore()
    let uploadManager: UploadManager
    let connectivity: ConnectivityMonitor

    @Published var authenticated = false
    @Published var isLoading = true
    @Published var localRecordings: [LocalRecording] = []
    @Published var serverRecordings: [Source] = []
    @Published var today: TodayPayload?
    @Published var errorMessage: String?
    @Published var password = ""
    @Published var isLoggingIn = false
    @Published var isRestoringSession = false
    @Published private(set) var watchCaptureStatus: WatchCaptureStatus = .idle

    var meetingCaptures: [MeetingCapture] {
        MeetingCapture.group(localRecordings)
    }

    private var pendingShareUploadIDs = Set<UUID>()
    private var watchTransferObserver: NSObjectProtocol?
    private var watchStopAcknowledgementObserver: NSObjectProtocol?

    var watchCaptureSupported: Bool { WatchTransferReceiver.shared.isSupported }

    init() {
        let baseString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? "http://127.0.0.1:3333"
        let baseURL = URL(string: baseString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "http://127.0.0.1:3333")!
        localStore = LocalRecordingStore(); api = APIClient(baseURL: baseURL); audioRecorder = AudioRecorder(store: localStore); uploadManager = UploadManager(api: api, store: localStore); connectivity = ConnectivityMonitor()
        connectivity.onReachable = { [weak self] in
            Task { @MainActor [weak self] in await self?.handleSceneActive() }
        }
        connectivity.start()
        localRecordings = localStore.load()
        watchTransferObserver = NotificationCenter.default.addObserver(
            forName: .notedWatchTransferReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.importWatchRecordings()
            }
        }
        watchStopAcknowledgementObserver = NotificationCenter.default.addObserver(
            forName: .notedWatchStopAcknowledgementReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let acknowledgement = notification.object as? WatchStopCaptureAck else { return }
            Task { @MainActor [weak self] in
                self?.applyWatchStopAcknowledgement(acknowledgement)
            }
        }
    }

    func launch() async {
        isLoading = true; localRecordings = localStore.load(); importWatchRecordings(); importSharedRecordings()
        if let warning = localStore.lastLoadWarning { errorMessage = warning }
        isLoading = false
        if let saved = keychain.password() {
            password = saved
            Task { @MainActor [weak self] in await self?.restoreSavedSession(saved) }
        }
    }

    func login() async {
        guard !password.isEmpty, !isLoggingIn else { return }
        errorMessage = nil
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            try await api.login(password: password)
            try keychain.savePassword(password)
            authenticated = true
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        try? await api.logout(); keychain.deletePassword(); password = ""; authenticated = false
    }

    func refresh() async {
        guard authenticated else { return }
        do {
            await uploadPendingShareRecordings()
            await syncDeletions()
            let sources = try await api.listSources()
            let deletedSources = localStore.deletedServerSourceIDs()
            serverRecordings = sources.filter { $0.type == "voice" && !deletedSources.contains($0.id) }
            reconcileLocalStates()
            today = try await api.today()
        } catch { errorMessage = error.localizedDescription }
    }

    func handleSceneActive() async {
        localRecordings = localStore.load(); importWatchRecordings(); importSharedRecordings()
        if let warning = localStore.lastLoadWarning { errorMessage = warning }
        guard !isRestoringSession else { return }
        if !authenticated, let saved = keychain.password() {
            await restoreSavedSession(saved)
            return
        }
        await refresh()
    }

    private func restoreSavedSession(_ saved: String) async {
        guard !isRestoringSession else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }
        do {
            try await api.login(password: saved)
            authenticated = true
            await refresh()
        } catch {
            authenticated = false
            errorMessage = "The server is unavailable. Local recordings remain available and can be sent after you reconnect."
        }
    }

    @discardableResult
    private func importSharedRecordings() -> [UUID] {
        let pending = SharedImportInbox.pending()
        guard !pending.isEmpty else { return [] }
        var current = localRecordings
        var importedIDs: [UUID] = []

        for manifest in pending {
            if current.contains(where: { $0.id == manifest.id }) {
                SharedImportInbox.remove(manifest)
                continue
            }
            do {
                let imported = try localStore.importSharedRecording(manifest)
                current.append(imported)
                importedIDs.append(imported.id)
                pendingShareUploadIDs.insert(imported.id)
                SharedImportInbox.remove(manifest)
            } catch {
                errorMessage = "Noted saved the shared recording, but could not import it yet: \(error.localizedDescription)"
            }
        }

        if !importedIDs.isEmpty {
            localRecordings = current.sorted { $0.createdAt > $1.createdAt }
            try? localStore.save(localRecordings)
        }
        return importedIDs
    }

    @discardableResult
    private func importWatchRecordings() -> [UUID] {
        let pending = WatchTransferReceiver.shared.pendingTransfers()
        guard !pending.isEmpty else { return [] }

        var current = localRecordings
        var importedIDs: [UUID] = []
        let deletedIDs = localStore.deletedRecordingIDs()
        for transfer in pending where !deletedIDs.contains(transfer.manifest.sourceID) {
            do {
                let imported = try localStore.importWatchRecording(fileURL: transfer.fileURL, manifest: transfer.manifest)
                if let index = current.firstIndex(where: { $0.id == transfer.manifest.sourceID }) {
                    guard localStore.needsWatchRecordingRepair(current[index], manifest: transfer.manifest) else { continue }
                    current[index] = imported
                } else {
                    current.append(imported)
                }
                importedIDs.append(imported.id)
            } catch {
                errorMessage = "Noted received the Watch recording, but could not add it to Recordings: \(error.localizedDescription)"
            }
        }

        guard !importedIDs.isEmpty else { return [] }
        localRecordings = current.sorted { $0.createdAt > $1.createdAt }
        try? localStore.save(localRecordings)
        return importedIDs
    }

    private func uploadPendingShareRecordings() async {
        guard !pendingShareUploadIDs.isEmpty else { return }
        for id in Array(pendingShareUploadIDs) {
            localRecordings = await uploadManager.sync(localRecordings, recordingID: id)
            if let recording = localRecordings.first(where: { $0.id == id }), recording.serverSourceId != nil {
                pendingShareUploadIDs.remove(id)
            }
        }
        try? localStore.save(localRecordings)
    }

    func saveFinishedRecording(_ recording: LocalRecording) {
        var current = localStore.load()
        if let index = current.firstIndex(where: { $0.id == recording.id }) {
            current[index] = recording
        } else {
            current.insert(recording, at: 0)
        }
        localRecordings = current.sorted { $0.createdAt > $1.createdAt }
        try? localStore.save(localRecordings)
    }

    func startCapture(
        title: String,
        consentMode: String,
        alsoRecordOnWatch: Bool
    ) async throws {
        let meetingID = UUID()
        watchCaptureStatus = alsoRecordOnWatch ? .starting(meetingID: meetingID) : .idle

        do {
            try await audioRecorder.start(
                title: title,
                meetingID: meetingID,
                consentMode: consentMode,
                consentAcknowledged: true
            )
        } catch {
            watchCaptureStatus = .idle
            throw error
        }

        guard alsoRecordOnWatch else { return }
        guard WatchTransferReceiver.shared.isReachable else {
            watchCaptureStatus = .unavailable(
                meetingID: meetingID,
                message: "Apple Watch is not reachable. The iPhone recording continues locally."
            )
            return
        }

        do {
            let acknowledgement = try await WatchTransferReceiver.shared.requestWatchStart(
                meetingID: meetingID,
                title: title.isEmpty ? "Untitled Meeting" : title
            )
            guard acknowledgement.accepted,
                  acknowledgement.isRecording,
                  let sourceID = acknowledgement.sourceID else {
                watchCaptureStatus = .failed(
                    meetingID: meetingID,
                    message: acknowledgement.error ?? "The Apple Watch did not confirm recording. The iPhone recording continues locally."
                )
                return
            }
            watchCaptureStatus = .recording(meetingID: meetingID, sourceID: sourceID)
        } catch WatchConnectivityCommandError.notReachable {
            watchCaptureStatus = .unavailable(
                meetingID: meetingID,
                message: "Apple Watch became unreachable. The iPhone recording continues locally."
            )
        } catch {
            watchCaptureStatus = .failed(
                meetingID: meetingID,
                message: "Apple Watch did not start. The iPhone recording continues locally."
            )
        }
    }

    @discardableResult
    func stopCapture(title: String, consentMode: String, moments: [TimeInterval]) async -> LocalRecording? {
        let watchStatus = watchCaptureStatus
        let watchMeetingID: UUID?
        let shouldRequestWatchStop: Bool
        switch watchStatus {
        case .starting(let meetingID), .recording(let meetingID, _), .unavailable(let meetingID, _), .failed(let meetingID, _):
            watchMeetingID = meetingID
            shouldRequestWatchStop = true
        default:
            watchMeetingID = nil
            shouldRequestWatchStop = false
        }

        guard let finished = await audioRecorder.stop() else { return nil }
        var saved = finished
        saved.title = title.isEmpty ? "Untitled Recording" : title
        saved.consentMode = consentMode
        saved.bookmarks = moments.map { LocalBookmark(id: UUID(), timestamp: $0, createdAt: Date()) }
        saveFinishedRecording(saved)

        guard shouldRequestWatchStop, let watchMeetingID else { return saved }
        do {
            let acknowledgement = try await WatchTransferReceiver.shared.requestWatchStop(meetingID: watchMeetingID)
            applyWatchStopAcknowledgement(acknowledgement)
        } catch WatchConnectivityCommandError.notReachable {
            watchCaptureStatus = .unavailable(
                meetingID: watchMeetingID,
                message: "The iPhone recording is saved. Apple Watch stop is unresolved until it reconnects."
            )
        } catch {
            watchCaptureStatus = .failed(
                meetingID: watchMeetingID,
                message: "The iPhone recording is saved. Apple Watch stop still needs attention."
            )
        }
        return saved
    }

    private func applyWatchStopAcknowledgement(_ acknowledgement: WatchStopCaptureAck) {
        guard acknowledgement.accepted else {
            watchCaptureStatus = .failed(
                meetingID: acknowledgement.meetingID,
                message: acknowledgement.error ?? "Apple Watch did not accept the stop request."
            )
            return
        }
        if acknowledgement.completed {
            watchCaptureStatus = .stopped(meetingID: acknowledgement.meetingID)
        } else if acknowledgement.requiresConfirmation {
            watchCaptureStatus = .stopNeedsConfirmation(meetingID: acknowledgement.meetingID)
        } else {
            watchCaptureStatus = .failed(
                meetingID: acknowledgement.meetingID,
                message: acknowledgement.error ?? "Apple Watch stop remains unresolved."
            )
        }
    }

    func uploadRecording(id: UUID) async throws {
        guard authenticated else { throw AppModelError.notConnected }
        guard let recording = localRecordings.first(where: { $0.id == id }) else { throw AppModelError.recordingNotFound }
        guard recording.serverSourceId == nil else { return }
        guard recording.state != .needsRepair && recording.state != .missingFile else { throw AppModelError.audioNotUploadable }

        errorMessage = nil
        localRecordings = await uploadManager.sync(localRecordings, recordingID: id)
        try? localStore.save(localRecordings)
        guard let updated = localRecordings.first(where: { $0.id == id }) else { throw AppModelError.recordingNotFound }
        if updated.serverSourceId == nil {
            throw AppModelError.uploadFailed(updated.lastError ?? "The server did not accept this recording.")
        }
        if let sources = try? await api.listSources() {
            let deletedSources = localStore.deletedServerSourceIDs()
            serverRecordings = sources.filter { $0.type == "voice" && !deletedSources.contains($0.id) }
            reconcileLocalStates()
        }
    }

    func deleteRecording(_ recording: LocalRecording?, source: Source?) async throws {
        let id = recording?.id ?? UUID()
        if let recording, audioRecorder.activeRecordingIDForDeletion == recording.id {
            throw AppModelError.cannotDeleteActiveRecording
        }
        let sourceID = recording?.serverSourceId ?? source?.id
        try localStore.markDeleted(id: id, serverSourceId: sourceID)

        if let sourceID, authenticated {
            do {
                try await api.deleteSource(id: sourceID)
                try? localStore.clearDeletion(forServerSourceID: sourceID)
            } catch {
                errorMessage = "Deletion is queued until the server is reachable."
            }
        }

        if let recording {
            let url = localStore.resolvedURL(for: recording)
            try? FileManager.default.removeItem(at: url)
            localRecordings.removeAll { $0.id == recording.id }
        }
        if let sourceID { serverRecordings.removeAll { $0.id == sourceID } }
        try? localStore.save(localRecordings)
    }

    private func syncDeletions() async {
        guard authenticated else { return }
        for tombstone in localStore.deletionTombstones() {
            guard let sourceID = tombstone.serverSourceId else { continue }
            do {
                try await api.deleteSource(id: sourceID)
                try? localStore.clearDeletion(forServerSourceID: sourceID)
            } catch APIError.server(404, _) {
                try? localStore.clearDeletion(forServerSourceID: sourceID)
            } catch {
                continue
            }
        }
    }

    private func reconcileLocalStates() {
        let sourceByID = Dictionary(uniqueKeysWithValues: serverRecordings.map { ($0.id, $0) })
        var changed = false

        for index in localRecordings.indices {
            // Keep a local integrity failure visible. A server refresh may still
            // report the source as partial/failed, but it cannot make a corrupt
            // local file playable or safe to retry.
            if localRecordings[index].state == .needsRepair || localRecordings[index].state == .missingFile {
                continue
            }
            guard let sourceID = localRecordings[index].serverSourceId,
                  let source = sourceByID[sourceID] else { continue }

            let nextState: LocalRecordingState
            switch source.processingStatus {
            case .pending, .processing: nextState = .processing
            case .ready: nextState = .ready
            case .partial: nextState = .partial
            case .failed: nextState = .failed
            }

            if localRecordings[index].state != nextState || localRecordings[index].lastError != source.processingError {
                localRecordings[index].state = nextState
                localRecordings[index].lastError = source.processingError
                changed = true
            }
        }

        if changed { try? localStore.save(localRecordings) }
    }

    func addBookmark(to id: UUID, timestamp: TimeInterval) {
        guard let index = localRecordings.firstIndex(where: { $0.id == id }) else { return }
        localRecordings[index].bookmarks.append(LocalBookmark(id: UUID(), timestamp: timestamp, createdAt: Date())); try? localStore.save(localRecordings)
    }

    func updateTitle(_ title: String, for id: UUID) { guard let index = localRecordings.firstIndex(where: { $0.id == id }) else { return }; localRecordings[index].title = title; try? localStore.save(localRecordings) }

    func bundle(for sourceID: String) async -> SourceBundle? { try? await api.sourceBundle(id: sourceID) }
    func ask(_ question: String) async throws -> AskResponse { try await api.ask(question) }
    func resolveLoop(_ loop: OpenLoop) async { try? await api.resolveLoop(id: loop.id, status: "resolved"); await refresh() }
}

enum AppModelError: LocalizedError {
    case cannotDeleteActiveRecording
    case notConnected
    case recordingNotFound
    case audioNotUploadable
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteActiveRecording: "Stop the active recording before deleting it."
        case .notConnected: "Connect to the server in Settings before sending this recording."
        case .recordingNotFound: "This recording is no longer available on this iPhone."
        case .audioNotUploadable: "This recording's audio is missing or needs repair and cannot be sent."
        case .uploadFailed(let message): "The recording was not sent: \(message)"
        }
    }
}
