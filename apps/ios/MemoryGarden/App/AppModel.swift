import Foundation
import Combine

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

    init() {
        let baseString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? "http://127.0.0.1:3333"
        let baseURL = URL(string: baseString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "http://127.0.0.1:3333")!
        localStore = LocalRecordingStore(); api = APIClient(baseURL: baseURL); audioRecorder = AudioRecorder(store: localStore); uploadManager = UploadManager(api: api, store: localStore); connectivity = ConnectivityMonitor()
        connectivity.onReachable = { [weak self] in
            Task { @MainActor [weak self] in await self?.handleSceneActive() }
        }
        connectivity.start()
        localRecordings = localStore.load()
    }

    func launch() async {
        isLoading = true; localRecordings = localStore.load()
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
            let sources = try await api.listSources()
            serverRecordings = sources.filter { $0.type == "voice" }
            reconcileLocalStates()
            today = try await api.today()
            await syncUploads()
        } catch { errorMessage = error.localizedDescription }
    }

    func handleSceneActive() async {
        localRecordings = localStore.load()
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
            errorMessage = "The server is unavailable. Local recordings remain available and will sync when you reconnect."
        }
    }

    func saveFinishedRecording(_ recording: LocalRecording) {
        localRecordings.insert(recording, at: 0); try? localStore.save(localRecordings); Task { await syncUploads() }
    }

    func syncUploads() async {
        localRecordings = await uploadManager.sync(localRecordings)
        try? localStore.save(localRecordings)
        if authenticated {
            if let sources = try? await api.listSources() {
                serverRecordings = sources.filter { $0.type == "voice" }
                reconcileLocalStates()
            }
        }
    }

    private func reconcileLocalStates() {
        let sourceByID = Dictionary(uniqueKeysWithValues: serverRecordings.map { ($0.id, $0) })
        var changed = false

        for index in localRecordings.indices {
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
