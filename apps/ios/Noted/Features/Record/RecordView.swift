import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        RecordSurface(recorder: model.audioRecorder)
    }
}

/// Owns the direct recorder observation. AppModel remains the persistence source of truth,
/// while this child invalidates on every elapsed/state tick.
private struct RecordSurface: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var recorder: AudioRecorder

    @State private var title = "Untitled Meeting"
    @State private var mode = "meeting"
    @State private var consentAcknowledged = false
    @State private var moments: [TimeInterval] = []
    @State private var showConsentNotice = false
    @State private var savedMessage: String?

    private var isActive: Bool {
        recorder.state == .recording || recorder.state == .paused || recorder.state == .interrupted
    }

    private var needsConsent: Bool { mode == "conversation" || mode == "meeting" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("CAPTURE FIRST").font(.caption.bold()).tracking(1.5).foregroundStyle(Color.notedPrimary)
                        Text("Capture what matters.").font(.largeTitle.bold())
                        Text("Your iPhone saves the original audio before it ever needs a network connection.").foregroundStyle(.secondary)
                    }

                    if let message = recorder.interruptionMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(Color.notedAttention)
                    }

                    Picker("Recording mode", selection: $mode) {
                        Text("Private thought").tag("private_thought")
                        Text("Conversation").tag("conversation")
                        Text("Meeting").tag("meeting")
                    }
                    .pickerStyle(.segmented)
                    .disabled(isActive || recorder.isStarting || recorder.isSaving)

                    if needsConsent && !consentAcknowledged && !isActive {
                        Button { showConsentNotice = true } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Label("Acknowledge recording consent", systemImage: "person.2.wave.2")
                                Text("Make sure everyone present knows and agrees where required.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.notedAttention)
                    }

                    captureControl

                    if isActive {
                        activeControls
                    } else if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.notedSuccess)
                            .transition(.opacity)
                    }

                    if !isActive {
                        TextField("Recording title", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("recording-title")
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Label("Local-first capture", systemImage: "lock.shield.fill").font(.headline)
                        Text("Recordings stay on this iPhone until you choose one to send and the server confirms upload.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(AppSpacing.card)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.notedSuccess.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.card))

                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(.red).font(.callout).accessibilityAddTraits(.isStaticText)
                    }
                }
                .padding(AppSpacing.screen)
            }
            .navigationTitle("Record")
            .confirmationDialog("Recording notice", isPresented: $showConsentNotice, titleVisibility: .visible) {
                Button("I understand and have permission") { consentAcknowledged = true }
            } message: {
                Text("You are responsible for complying with applicable recording laws and workplace policies.")
            }
        }
    }

    @ViewBuilder
    private var captureControl: some View {
        if recorder.isStarting || recorder.isSaving {
            statusCard
        } else if isActive {
            statusCard
        } else {
            Button(action: toggleRecording) {
                idleCaptureLabel
            }
            .buttonStyle(.plain)
            .disabled(needsConsent && !consentAcknowledged)
            .accessibilityLabel("Start recording")
            .accessibilityIdentifier("record-toggle")
        }
    }

    private var idleCaptureLabel: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "mic.fill").font(.system(size: 38, weight: .bold))
            Text("START RECORDING")
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 190)
        .foregroundStyle(.white)
        .background(Color.notedPrimary, in: RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var statusCard: some View {
        VStack(spacing: AppSpacing.sm) {
            if recorder.isStarting {
                ProgressView().tint(.white).scaleEffect(1.2)
                Text("STARTING…")
            } else if recorder.isSaving {
                ProgressView().tint(.white).scaleEffect(1.2)
                Text("SAVING…")
            } else {
                Image(systemName: stateIcon)
                    .font(.title2.monospacedDigit().bold())
                Text(stateLabel.uppercased())
                Text(timeLabel(recorder.elapsed)).font(.title2.monospacedDigit().bold())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 190)
        .foregroundStyle(.white)
        .background(statusColor, in: RoundedRectangle(cornerRadius: 32))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("record-toggle")
    }

    private var stateLabel: String {
        switch recorder.state {
        case .recording: "Recording"
        case .paused: "Paused"
        case .interrupted: "Interrupted"
        default: recorder.isStarting ? "Starting" : "Saving"
        }
    }

    private var stateIcon: String {
        switch recorder.state {
        case .paused: "pause.fill"
        case .interrupted: "exclamationmark.triangle.fill"
        default: "stop.fill"
        }
    }

    private var statusColor: Color {
        switch recorder.state {
        case .interrupted: Color.notedAttention
        case .paused: Color.notedAttention
        default: recorder.isStarting || recorder.isSaving ? Color.notedPrimary : Color.notedRecording
        }
    }

    private var activeControls: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Button { recorder.markMoment().map { moments.append($0) } } label: {
                    Label("Mark Moment", systemImage: "bookmark.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("record-mark-moment")

                Button {
                    if recorder.state == .recording { recorder.pause() } else { recorder.resume() }
                } label: {
                    Label(recorder.state == .recording ? "Pause" : "Resume", systemImage: recorder.state == .recording ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("record-pause-resume")
            }

            Button(action: stopRecording) {
                Label("Stop & Save", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.notedRecording)
            .accessibilityIdentifier("record-stop-save")
            .accessibilityLabel("Stop and save recording")
        }
    }

    private var accessibilityLabel: String {
        if recorder.isStarting { return "Starting recording" }
        if recorder.isSaving { return "Saving recording" }
        if isActive { return "\(stateLabel), \(timeLabel(recorder.elapsed))" }
        return "Start recording"
    }

    private func toggleRecording() {
        guard !recorder.isStarting, !recorder.isSaving else { return }
        if isActive {
            stopRecording()
        } else {
            model.errorMessage = nil
            Task {
                do {
                    try await recorder.start(
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

    private func stopRecording() {
        Task {
            guard !recorder.isSaving, let finished = await recorder.stop() else { return }
            var saved = finished
            saved.title = title.isEmpty ? "Untitled Recording" : title
            saved.consentMode = mode
            saved.bookmarks = moments.map { LocalBookmark(id: UUID(), timestamp: $0, createdAt: Date()) }
            model.saveFinishedRecording(saved)
            moments = []
            withAnimation { savedMessage = saved.state == .needsRepair ? "Recording needs repair and was kept on this iPhone" : "Recording saved on this iPhone" }
            try? await Task.sleep(for: .seconds(4))
            if !isActive { withAnimation { savedMessage = nil } }
        }
    }
}
