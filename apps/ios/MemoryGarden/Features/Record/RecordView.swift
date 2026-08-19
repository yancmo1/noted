import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var model: AppModel
    @State private var title = "Untitled Meeting"
    @State private var mode = "meeting"
    @State private var consentAcknowledged = false
    @State private var moments: [TimeInterval] = []
    @State private var showConsentNotice = false

    private var isRecording: Bool { model.audioRecorder.state == .recording || model.audioRecorder.state == .paused || model.audioRecorder.state == .interrupted }
    private var needsConsent: Bool { mode == "conversation" || mode == "meeting" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CAPTURE FIRST").font(.caption.bold()).tracking(1.5).foregroundStyle(.indigo)
                        Text("Capture what matters.").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Your iPhone saves the original audio before it ever needs a network connection.").foregroundStyle(.secondary)
                    }
                    if let message = model.audioRecorder.interruptionMessage { Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
                    Picker("Recording mode", selection: $mode) {
                        Text("Private thought").tag("private_thought")
                        Text("Conversation").tag("conversation")
                        Text("Meeting").tag("meeting")
                    }.pickerStyle(.segmented).disabled(isRecording)
                    if needsConsent && !consentAcknowledged && !isRecording { Button { showConsentNotice = true } label: { Label("Acknowledge recording consent", systemImage: "person.2.wave.2"); Text("Make sure everyone present knows and agrees where required.").font(.caption).foregroundStyle(.secondary) }.buttonStyle(.bordered).tint(.orange) }
                    Button(action: toggleRecording) {
                        VStack(spacing: 12) {
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill").font(.system(size: 38, weight: .bold))
                            Text(isRecording ? timeLabel(model.audioRecorder.elapsed) : "RECORD").font(.headline.bold()).tracking(1)
                        }.frame(maxWidth: .infinity).frame(height: 190).background(isRecording ? Color.red.opacity(0.12) : Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 32)).overlay(RoundedRectangle(cornerRadius: 32).stroke(isRecording ? .red.opacity(0.35) : .indigo.opacity(0.25), lineWidth: 1))
                    }.buttonStyle(.plain).disabled(!isRecording && needsConsent && !consentAcknowledged).accessibilityLabel(isRecording ? "Stop recording" : "Start recording").accessibilityIdentifier("record-toggle")
                    if isRecording { HStack(spacing: 12) { Button { model.audioRecorder.markMoment().map { moments.append($0) } } label: { Label("Mark Moment", systemImage: "bookmark.fill") }.buttonStyle(.borderedProminent).accessibilityIdentifier("record-mark-moment"); Button { model.audioRecorder.state == .recording ? model.audioRecorder.pause() : model.audioRecorder.resume() } label: { Label(model.audioRecorder.state == .recording ? "Pause" : "Resume", systemImage: model.audioRecorder.state == .recording ? "pause.fill" : "play.fill") }.buttonStyle(.bordered).accessibilityIdentifier("record-pause-resume") } }
                    if !isRecording { TextField("Recording title", text: $title).textFieldStyle(.roundedBorder) }
                    VStack(alignment: .leading, spacing: 8) { Label("Local-first capture", systemImage: "lock.shield.fill").font(.headline); Text("Recordings stay on this iPhone until the server confirms upload. Network loss is recoverable.").font(.subheadline).foregroundStyle(.secondary) }.padding().background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
                }.padding()
            }
            .navigationTitle("Record")
            .confirmationDialog("Recording notice", isPresented: $showConsentNotice, titleVisibility: .visible) { Button("I understand and have permission") { consentAcknowledged = true } } message: { Text("You are responsible for complying with applicable recording laws and workplace policies.") }
        }
    }

    private func toggleRecording() {
        if isRecording { if var finished = model.audioRecorder.stop() { finished.title = title.isEmpty ? "Untitled Recording" : title; finished.consentMode = mode; finished.bookmarks = moments.map { LocalBookmark(id: UUID(), timestamp: $0, createdAt: Date()) }; model.saveFinishedRecording(finished); moments = [] } }
        else {
            model.errorMessage = nil
            Task {
                do {
                    try await model.audioRecorder.start(
                        title: title,
                        consentMode: mode,
                        consentAcknowledged: consentAcknowledged || !needsConsent
                    )
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
