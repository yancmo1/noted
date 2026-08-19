import SwiftUI

@main
struct MemoryGardenApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.launch() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isLoading { ProgressView("Opening Memory Garden…") }
            else if model.authenticated { MainTabView() }
            else { LoginView() }
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
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "sun.max") }
            RecordView().tabItem { Label("Record", systemImage: "record.circle") }
            RecordingsView().tabItem { Label("Recordings", systemImage: "waveform") }
            AskView().tabItem { Label("Ask", systemImage: "sparkles") }
            SettingsView().tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
    }
}
