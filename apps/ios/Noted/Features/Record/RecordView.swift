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
    @State private var moments: [TimeInterval] = []
    @State private var savedMessage: String?
    @State private var recordOnWatch = false

    private var isActive: Bool {
        recorder.state == .recording || recorder.state == .paused || recorder.state == .interrupted
    }

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

                    if model.watchCaptureSupported {
                        Toggle(isOn: $recordOnWatch) {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Label("Also record on Apple Watch", systemImage: "applewatch")
                                Text("Keeps the iPhone and Watch microphones as separate source tracks in this meeting.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isActive || recorder.isStarting || recorder.isSaving)

                        if recordOnWatch || model.watchCaptureStatus != .idle {
                            watchStatusCard
                        }
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
                    if recorder.state == .recording {
                        recorder.pause()
                    } else {
                        Task { await recorder.resume() }
                    }
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

    private var watchStatusCard: some View {
        let status = model.watchCaptureStatus
        return Label(watchStatusText(status), systemImage: watchStatusIcon(status))
            .font(.subheadline)
            .foregroundStyle(watchStatusColor(status))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.card)
            .background(watchStatusColor(status).opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.card))
            .accessibilityIdentifier("watch-capture-status")
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
                    try await model.startCapture(
                        title: title,
                        consentMode: mode,
                        alsoRecordOnWatch: recordOnWatch
                    )
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopRecording() {
        Task {
            guard !recorder.isSaving,
                  let saved = await model.stopCapture(title: title, consentMode: mode, moments: moments) else { return }
            moments = []
            withAnimation { savedMessage = saved.state == .needsRepair ? "Recording needs repair and was kept on this iPhone" : "Recording saved on this iPhone" }
            try? await Task.sleep(for: .seconds(4))
            if !isActive { withAnimation { savedMessage = nil } }
        }
    }

    private func watchStatusText(_ status: WatchCaptureStatus) -> String {
        switch status {
        case .idle: "Apple Watch capture is off."
        case .starting: "Starting the Apple Watch source…"
        case .recording: "Apple Watch is recording a separate source."
        case .unavailable(_, let message), .failed(_, let message): message
        case .stopNeedsConfirmation: "Confirm Stop on the Apple Watch to finalize its source."
        case .stopped: "Apple Watch source stopped. Its local file will transfer and remain protected until acknowledgement."
        }
    }

    private func watchStatusIcon(_ status: WatchCaptureStatus) -> String {
        switch status {
        case .recording: "record.circle.fill"
        case .starting: "arrow.triangle.2.circlepath"
        case .unavailable, .failed, .stopNeedsConfirmation: "exclamationmark.triangle.fill"
        case .stopped: "checkmark.circle.fill"
        case .idle: "applewatch"
        }
    }

    private func watchStatusColor(_ status: WatchCaptureStatus) -> Color {
        switch status {
        case .recording: Color.notedRecording
        case .unavailable, .failed, .stopNeedsConfirmation: Color.notedAttention
        case .stopped: Color.notedSuccess
        case .starting: Color.notedPrimary
        case .idle: .secondary
        }
    }
}
