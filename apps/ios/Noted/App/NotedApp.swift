import SwiftUI

@main
struct NotedApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchTransferReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.launch() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.handleSceneActive() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isLoading { ProgressView("Opening Noted…") }
            else { MainTabView() }
        }
        .tint(Color.notedPrimary)
    }
}

struct LoginView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "note.text").font(.largeTitle).foregroundStyle(Color.notedPrimary)
                        Text("Noted").font(.largeTitle.bold())
                        Text("Capture first. Noted will take care of the remembering.").foregroundStyle(.secondary)
                    }.padding(.vertical, 18)
                }
                Section("Local server password") {
                    SecureField("Password", text: $model.password)
                    Button {
                        Task { await model.login() }
                    } label: {
                        if model.isLoggingIn {
                            HStack {
                                ProgressView()
                                Text("Connecting…")
                            }
                        } else {
                            Text("Open Noted")
                        }
                    }
                    .disabled(model.password.isEmpty || model.isLoggingIn)
                }
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) } }
            }
            .navigationTitle("Welcome")
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            MeetingsView().tabItem { Label("Meetings", systemImage: "waveform") }
            RecordView().tabItem { Label("Record", systemImage: "record.circle") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            RecordingStatusBanner(recorder: model.audioRecorder)
        }
    }
}

struct RecordingStatusBanner: View {
    @ObservedObject var recorder: AudioRecorder

    private var isActive: Bool {
        recorder.state == .recording || recorder.state == .paused || recorder.state == .interrupted
    }

    var body: some View {
        if isActive {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: stateIcon)
                Text("Recording · \(timeLabel(recorder.elapsed))").monospacedDigit()
                Spacer()
                Text(stateLabel).font(.caption.bold())
            }
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.screen)
            .padding(.vertical, AppSpacing.xs)
            .background(statusColor)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recording \(stateLabel.lowercased()), \(timeLabel(recorder.elapsed))")
            .accessibilityIdentifier("recording-status-banner")
        }
    }

    private var stateLabel: String {
        switch recorder.state {
        case .paused: "Paused"
        case .interrupted: "Interrupted"
        default: "Active"
        }
    }

    private var stateIcon: String {
        switch recorder.state {
        case .paused: "pause.circle.fill"
        case .interrupted: "exclamationmark.triangle.fill"
        default: "record.circle.fill"
        }
    }

    private var statusColor: Color {
        switch recorder.state {
        case .paused, .interrupted: Color.notedAttention
        default: Color.notedRecording
        }
    }
}
