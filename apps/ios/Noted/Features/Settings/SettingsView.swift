import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLogout = false
    @State private var connectionPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Server", value: model.api.baseURL.absoluteString)
                    LabeledContent("Local recordings", value: "\(model.localRecordings.count)")
                    if model.authenticated {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Color.notedSuccess)
                        Label("Send recordings individually from Meetings.", systemImage: "hand.tap")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Offline capture is available. Connect to upload and process meetings.", systemImage: "wifi.slash").foregroundStyle(.secondary)
                        SecureField("Server password", text: $connectionPassword)
                        Button("Connect") {
                            model.password = connectionPassword
                            Task { await model.login() }
                        }
                        .disabled(connectionPassword.isEmpty || model.isLoggingIn)
                    }
                    if model.isLoggingIn { ProgressView("Connecting…") }
                    if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(Color.notedAttention).accessibilityAddTraits(.isStaticText) }
                }
                Section("Provider monitoring") {
                    Link(destination: URL(string: "https://console.groq.com/home")!) {
                        Label("Open Groq usage dashboard", systemImage: "chart.bar.xaxis")
                    }
                    Text("Monitor Groq transcription and analysis usage.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Import recordings") {
                    Label("Share an audio recording to Noted from the Phone, Notes, or Files share sheet.", systemImage: "square.and.arrow.down")
                    Text("From a meeting, use Share Audio File for AirDrop or Files, or Send to Noted Cloud for transcription and summaries. The original stays on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Privacy") { Label("Audio stays on this iPhone until you send that recording and upload is confirmed.", systemImage: "lock.shield"); Label("Authentication password is stored in Keychain.", systemImage: "key.fill"); Text("Recording conversations and meetings may be subject to laws and workplace policies. You are responsible for obtaining permission where required.").font(.footnote).foregroundStyle(.secondary) }
                Section("App") { LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"); LabeledContent("Audio", value: "M4A / AAC · 44.1 kHz mono"); Button("Log out", role: .destructive) { showLogout = true } }
            }.navigationTitle("Settings").confirmationDialog("Log out of Noted?", isPresented: $showLogout) { Button("Log out", role: .destructive) { Task { await model.logout() } } }
        }
    }
}
