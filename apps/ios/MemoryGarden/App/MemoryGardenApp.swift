import SwiftUI

@main
struct MemoryGardenApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

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
            if model.isLoading { ProgressView("Opening Memory Garden…") }
            else { MainTabView() }
        }
        .tint(.indigo)
    }
}

struct LoginView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "leaf.circle.fill").font(.system(size: 54)).foregroundStyle(.indigo)
                        Text("Memory Garden").font(.largeTitle.bold())
                        Text("Capture first. Your garden will take care of the remembering.").foregroundStyle(.secondary)
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
                            Text("Open Memory Garden")
                        }
                    }
                    .disabled(model.password.isEmpty || model.isLoggingIn)
                }
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
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
            SettingsView().tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.audioRecorder.state == .recording || model.audioRecorder.state == .paused || model.audioRecorder.state == .interrupted {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "record.circle.fill")
                    Text("Recording · (timeLabel(model.audioRecorder.elapsed))")
                        .monospacedDigit()
                    Spacer()
                    Text(model.audioRecorder.state == .paused ? "Paused" : "Active")
                        .font(.caption.bold())
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.screen)
                .padding(.vertical, AppSpacing.xs)
                .background(.red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recording in progress, (timeLabel(model.audioRecorder.elapsed))")
            }
        }
    }
}
