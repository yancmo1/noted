import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLogout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") { LabeledContent("Server", value: model.api.baseURL.absoluteString); LabeledContent("Local recordings", value: "\(model.localRecordings.count)"); Button { Task { await model.syncUploads() } } label: { Label("Retry pending uploads", systemImage: "arrow.up.circle") } }
                Section("Privacy") { Label("Audio stays on this iPhone until upload is confirmed.", systemImage: "lock.shield"); Label("Authentication password is stored in Keychain.", systemImage: "key.fill"); Text("Recording conversations and meetings may be subject to laws and workplace policies. You are responsible for obtaining permission where required.").font(.footnote).foregroundStyle(.secondary) }
                Section("App") { LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"); LabeledContent("Audio", value: "M4A / AAC · 44.1 kHz mono"); Button("Log out", role: .destructive) { showLogout = true } }
            }.navigationTitle("More").confirmationDialog("Log out of Memory Garden?", isPresented: $showLogout) { Button("Log out", role: .destructive) { Task { await model.logout() } } }
        }
    }
}
