import AppKit
import SwiftUI

struct JobDetailView: View {
    @Bindable var store: TranscriptionStore
    let job: TranscriptionJob
    let windowManager: TranscriptWindowManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NotedSpacing.lg) {
                header

                switch job.state {
                case .queued, .transcribing:
                    processing
                case .failed:
                    failure
                case .ready:
                    transcriptSummary
                }
            }
            .padding(NotedSpacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(job.title)
        .toolbar {
            ToolbarItemGroup {
                Button("Show Recording", systemImage: "folder") { store.revealSource(job) }
                Button("Open Transcript", systemImage: "text.document") {
                    windowManager.openTranscript(for: job.id, store: store)
                }
                Button("Add Recording", systemImage: "plus") {
                    NotificationCenter.default.post(name: .chooseRecording, object: nil)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NotedSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: NotedSpacing.xs) {
                    Text(job.title)
                        .font(.largeTitle.weight(.bold))
                        .textSelection(.enabled)
                    Text("\(job.fileDetails) · Added \(job.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }
            Label("The original recording remains on this Mac.", systemImage: "lock.shield.fill")
                .font(.callout)
                .foregroundStyle(Color.notedPrimary)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
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

    private var processing: some View {
        NotedSurface {
            VStack(alignment: .leading, spacing: NotedSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.notedMemory)
                Text("Transcribing on this Mac")
                    .font(.title2.weight(.semibold))
                Text("Local Whisper is preparing the audio, detecting speech, and building a timestamped transcript. Longer recordings can take a few minutes.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560, alignment: .leading)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Elapsed \(elapsedText(at: context.date))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.notedMemory)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
        }
    }

    private var failure: some View {
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

    private var transcriptSummary: some View {
        VStack(alignment: .leading, spacing: NotedSpacing.md) {
            Label("Transcript editor", systemImage: "text.document")
                .font(.title2.weight(.semibold))
            Text(summaryLine)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("The timestamped transcript is open in its own window. Edit there and your changes will save automatically.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Transcript", systemImage: "arrow.up.forward.app") {
                windowManager.openTranscript(for: job.id, store: store)
            }
            .buttonStyle(.borderedProminent)
            .tint(.notedPrimary)
        }
    }

    private var summaryLine: String {
        let language = job.detectedLanguage?.uppercased() ?? "AUTO"
        return "\(job.segments.count) timestamped segments · \(language) language"
    }

    private func elapsedText(at date: Date) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(job.updatedAt)))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}

struct SendToNotedSheet: View {
    @Bindable var store: TranscriptionStore
    let job: TranscriptionJob
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = NotedUploader.defaultBaseURL
    @State private var password = ""
    @State private var rememberPassword = false

    private var sendState: RemoteSendState { store.sendStates[job.id] ?? .idle }
    private var isSending: Bool {
        switch sendState {
        case .sending, .processing: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotedSpacing.lg) {
            VStack(alignment: .leading, spacing: NotedSpacing.xs) {
                Text("Send transcript to Noted")
                    .font(.title2.weight(.bold))
                Text("After secure sign-in, only the edited transcript and its timestamps are uploaded. The original \(job.fileDetails.lowercased()) remains local.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: NotedSpacing.sm) {
                Text("Noted web address")
                    .font(.callout.weight(.semibold))
                TextField("https://noted.shepswork.com", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: NotedSpacing.sm) {
                    Button("Use Local Mac") { baseURL = NotedUploader.localBaseURL }
                        .buttonStyle(.link)
                    Button("Use Hosted Noted") { baseURL = NotedUploader.defaultBaseURL }
                        .buttonStyle(.link)
                }
                Text("Use HTTPS for hosted Noted. For local Mac testing, use http://127.0.0.1:3333.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: NotedSpacing.sm) {
                Text("Noted password")
                    .font(.callout.weight(.semibold))
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                Toggle("Remember securely in Keychain", isOn: $rememberPassword)
                    .toggleStyle(.checkbox)
            }

            sendProgress

            if case .failed(let message) = sendState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.notedAttention)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Send Transcript", systemImage: "paperplane.fill") {
                    Task {
                        await store.sendToNoted(jobID: job.id, baseURL: baseURL, password: password, rememberPassword: rememberPassword)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.notedPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(isSending || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(NotedSpacing.xl)
        .frame(width: 480)
        .onAppear {
            if password.isEmpty, let saved = NotedKeychain.password() {
                password = saved
                rememberPassword = true
            }
        }
        .onChange(of: store.sendStates[job.id]) { _, newValue in
            if case .sent = newValue { dismiss() }
        }
    }

    @ViewBuilder
    private var sendProgress: some View {
        switch sendState {
        case .sending:
            sendProgressCard(title: "Sending transcript", detail: "The edited transcript and timestamps are being sent to Noted. The original audio stays on this Mac.")
        case .processing:
            sendProgressCard(title: "Processing on Noted", detail: "The transcript was received. Noted is now creating the summary, memories, and follow-ups.")
        default:
            EmptyView()
        }
    }

    private func sendProgressCard(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: NotedSpacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(.notedMemory)
            VStack(alignment: .leading, spacing: NotedSpacing.xs) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NotedSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.notedMemory.opacity(0.10), in: RoundedRectangle(cornerRadius: NotedRadius.control))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}
