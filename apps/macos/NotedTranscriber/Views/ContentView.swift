import SwiftUI

struct ContentView: View {
    @Bindable var store: TranscriptionStore
    let windowManager: TranscriptWindowManager
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var hasOpenedInitialTranscript = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            JobSidebar(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 340)
        } detail: {
            if let job = store.selectedJob {
                JobDetailView(store: store, job: job, windowManager: windowManager)
            } else {
                VStack(spacing: NotedSpacing.lg) {
                    VStack(spacing: NotedSpacing.xs) {
                        Image(systemName: "note.text")
                            .font(.largeTitle)
                            .foregroundStyle(Color.notedPrimary)
                        Text("Noted Transcriber")
                            .font(.largeTitle.weight(.bold))
                        Text("Turn any recording into a private, local transcript.")
                            .foregroundStyle(.secondary)
                    }
                    DropZoneView(isCompact: false, onImport: store.importRecordings)
                        .frame(maxWidth: 680)
                }
                .padding(NotedSpacing.xl)
                .navigationTitle("Noted Transcriber")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Couldn’t add that recording", isPresented: importErrorPresented) {
            Button("OK") { store.importError = nil }
        } message: {
            Text(store.importError ?? "Try another recording.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .chooseRecording)) { _ in
            let urls = RecordingPicker.choose()
            if !urls.isEmpty { store.importRecordings(urls) }
        }
        .background(MainWindowRegistration { window in
            windowManager.observeMainWindow(window)
        })
        .onAppear {
            guard !hasOpenedInitialTranscript, let selection = store.selection else { return }
            hasOpenedInitialTranscript = true
            windowManager.openTranscript(for: selection, store: store)
        }
        .onChange(of: store.selection) { _, newSelection in
            guard let newSelection else { return }
            hasOpenedInitialTranscript = true
            windowManager.openTranscript(for: newSelection, store: store)
        }
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(
            get: { store.importError != nil },
            set: { if !$0 { store.importError = nil } }
        )
    }
}

extension Notification.Name {
    static let chooseRecording = Notification.Name("NotedTranscriber.chooseRecording")
}
