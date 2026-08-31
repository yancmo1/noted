import AppKit
import SwiftUI

struct TranscriptWindowView: View {
    @Bindable var store: TranscriptionStore
    let jobID: UUID
    @State private var showingSendSheet = false

    private var job: TranscriptionJob? {
        store.jobs.first(where: { $0.id == jobID })
    }

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: NotedSpacing.lg) {
                        header(for: job)

                        switch job.state {
                        case .queued, .transcribing:
                            processing(for: job)
                        case .failed:
                            failure(for: job)
                        case .ready:
                            editor(for: job)
                        }
                    }
                    .padding(NotedSpacing.xl)
                    .frame(maxWidth: 1_040, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("Transcript unavailable", systemImage: "text.document")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingSendSheet) {
            if let job {
                SendToNotedSheet(store: store, job: job)
            }
        }
    }

    private func header(for job: TranscriptionJob) -> some View {
        VStack(alignment: .leading, spacing: NotedSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: NotedSpacing.xs) {
                    Text("Transcript editor")
                        .font(.title.weight(.semibold))
                    Text(job.title)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                statusBadge(for: job)
            }
            Label("Timestamps stay fixed while transcript text remains editable. Changes save automatically.", systemImage: "lock.doc")
                .font(.callout)
                .foregroundStyle(Color.notedPrimary)
        }
    }

    @ViewBuilder
    private func statusBadge(for job: TranscriptionJob) -> some View {
        switch job.state {
        case .queued:
            StatusBadge(title: job.state.title, color: .secondary, systemImage: job.state.systemImage)
        case .transcribing:
            StatusBadge(title: job.state.title, color: .notedMemory, systemImage: job.state.systemImage)
        case .ready:
            StatusBadge(title: job.state.title, color: .notedSuccess, systemImage: job.state.systemImage)
        case .failed:
            StatusBadge(title: job.state.title, color: .notedAttention, systemImage: job.state.systemImage)
        }
    }

    private func processing(for job: TranscriptionJob) -> some View {
        NotedSurface {
            VStack(alignment: .leading, spacing: NotedSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.notedMemory)
                Text("Transcribing on this Mac")
                    .font(.title2.weight(.semibold))
                Text("Local Whisper is preparing the audio, detecting speech, and building your timestamped transcript. Longer recordings can take a few minutes.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560, alignment: .leading)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Elapsed \(elapsedText(for: job, at: context.date))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.notedMemory)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
        }
    }

    private func failure(for job: TranscriptionJob) -> some View {
        NotedSurface {
            VStack(alignment: .leading, spacing: NotedSpacing.md) {
                Label("Transcription didn’t finish", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.notedAttention)
                Text(job.errorMessage ?? "The recording could not be transcribed.")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button("Try Again", systemImage: "arrow.clockwise") { store.retry(job.id) }
                        .buttonStyle(.borderedProminent)
                        .tint(.notedPrimary)
                    Button("Open Run Log", systemImage: "doc.text.magnifyingglass") { store.revealOutput(job) }
                }
            }
        }
    }

    private func editor(for job: TranscriptionJob) -> some View {
        VStack(alignment: .leading, spacing: NotedSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: NotedSpacing.xs) {
                    Text("Review transcript")
                        .font(.title2.weight(.semibold))
                    Text(summaryLine(for: job))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { copyTranscript(for: job) }
                Button("Transcript Files", systemImage: "folder") { store.revealOutput(job) }
            }

            TimestampedTranscriptEditor(
                segments: job.segments,
                fallbackText: job.transcript,
                onChange: { segments, transcript in
                    store.updateTranscript(jobID: job.id, transcript: transcript, segments: segments)
                }
            )
            .frame(minHeight: 420)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: NotedRadius.surface))
            .overlay {
                RoundedRectangle(cornerRadius: NotedRadius.surface)
                    .strokeBorder(.separator.opacity(0.7))
            }

            HStack(spacing: NotedSpacing.md) {
                Label(sendFootnote(for: job), systemImage: sendFootnoteIcon(for: job))
                    .font(.callout)
                    .foregroundStyle(sendFootnoteColor(for: job))
                Spacer()
                Button(sendButtonTitle(for: job), systemImage: sendButtonIcon(for: job)) {
                    showingSendSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.notedPrimary)
                .disabled(isSending(for: job) || isSent(for: job))
            }
        }
    }

    private func copyTranscript(for job: TranscriptionJob) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(job.timestampedTranscript, forType: .string)
    }

    private func summaryLine(for job: TranscriptionJob) -> String {
        let language = job.detectedLanguage?.uppercased() ?? "AUTO"
        return "\(job.segments.count) timestamped segments · \(language) language"
    }

    private func elapsedText(for job: TranscriptionJob, at date: Date) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(job.updatedAt)))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private func currentSendState(for job: TranscriptionJob) -> RemoteSendState {
        store.sendStates[job.id] ?? .idle
    }

    private func isSending(for job: TranscriptionJob) -> Bool {
        switch currentSendState(for: job) {
        case .sending, .processing: return true
        default: return false
        }
    }

    private func isSent(for job: TranscriptionJob) -> Bool {
        if case .sent = currentSendState(for: job) { return true }
        return false
    }

    private func sendButtonTitle(for job: TranscriptionJob) -> String {
        switch currentSendState(for: job) {
        case .sending: return "Sending…"
        case .processing: return "Processing…"
        case .sent: return "Sent to Noted"
        default: return "Send to Noted"
        }
    }

    private func sendButtonIcon(for job: TranscriptionJob) -> String {
        isSent(for: job) ? "checkmark.circle.fill" : "paperplane.fill"
    }

    private func sendFootnote(for job: TranscriptionJob) -> String {
        switch currentSendState(for: job) {
        case .processing: return "Transcript received. Noted is processing it now; this may take a few minutes."
        case .sent: return "Transcript sent. The original recording stayed on this Mac."
        case .failed(let message): return message
        default: return "Only transcript text and timestamps are uploaded; audio stays local."
        }
    }

    private func sendFootnoteIcon(for job: TranscriptionJob) -> String {
        let state = currentSendState(for: job)
        if case .failed = state { return "exclamationmark.triangle.fill" }
        if isSent(for: job) { return "checkmark.circle.fill" }
        if case .processing = state { return "hourglass" }
        return "text.document"
    }

    private func sendFootnoteColor(for job: TranscriptionJob) -> Color {
        let state = currentSendState(for: job)
        if case .failed = state { return .notedAttention }
        if isSent(for: job) { return .notedSuccess }
        if case .processing = state { return .notedMemory }
        return .secondary
    }
}
