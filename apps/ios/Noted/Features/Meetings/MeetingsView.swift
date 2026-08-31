import SwiftUI
import UIKit

private enum MeetingSendPhase: Equatable {
    case uploading
    case processing

    var title: String {
        switch self {
        case .uploading: "Sending recording"
        case .processing: "Processing recording"
        }
    }

    var detail: String {
        switch self {
        case .uploading: "The audio is being sent. The original stays on this iPhone until receipt is confirmed."
        case .processing: "The recording arrived. Noted is transcribing and creating the meeting details now."
        }
    }
}

struct MeetingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingDelete: MeetingDeleteTarget?
    @State private var showDeleteConfirmation = false
    @State private var deletionError: String?

    private var serverByID: [String: Source] {
        Dictionary(uniqueKeysWithValues: model.serverRecordings.map { ($0.id, $0) })
    }

    private var serverOnly: [Source] {
        model.serverRecordings.filter { source in
            !model.localStore.deletedServerSourceIDs().contains(source.id) &&
            !model.localRecordings.contains { recording in
                recording.serverSourceId == source.id || source.metadata["clientRecordingId"] == recording.id.uuidString
            }
        }
    }

    private func source(for recording: LocalRecording) -> Source? {
        if let sourceID = recording.serverSourceId, let source = serverByID[sourceID] { return source }
        return model.serverRecordings.first { $0.metadata["clientRecordingId"] == recording.id.uuidString }
    }

    var body: some View {
        NavigationStack {
            List {
                if !model.localRecordings.isEmpty {
                    Section("On this iPhone") {
                        ForEach(model.localRecordings) { recording in
                            NavigationLink {
                                MeetingDetailView(recording: recording, source: source(for: recording))
                            } label: {
                                MeetingRow(recording: recording, source: source(for: recording))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = MeetingDeleteTarget(recording: recording, source: source(for: recording))
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityIdentifier("delete-meeting-\(recording.id.uuidString)")
                            }
                        }
                    }
                }

                if !serverOnly.isEmpty {
                    Section("From Noted") {
                        ForEach(serverOnly) { source in
                            NavigationLink {
                                MeetingDetailView(recording: nil, source: source)
                            } label: {
                                MeetingRow(recording: nil, source: source)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = MeetingDeleteTarget(recording: nil, source: source)
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityIdentifier("delete-meeting-\(source.id)")
                            }
                        }
                    }
                }

                if model.localRecordings.isEmpty && model.serverRecordings.isEmpty {
                    EmptyState(icon: "waveform", title: "No meetings yet", message: "Start a recording and it will appear here immediately, even without a connection.")
                }
            }
            .navigationTitle("Meetings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.handleSceneActive() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh meetings")
                }
            }
            .refreshable { await model.handleSceneActive() }
            .confirmationDialog("Delete this meeting?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let pendingDelete else { return }
                    Task { await delete(pendingDelete) }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("The audio and its derived memories will be removed. This cannot be undone.")
            }
            .alert("Could not delete meeting", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                Button("OK", role: .cancel) { deletionError = nil }
            } message: {
                Text(deletionError ?? "Try again when the server is reachable.")
            }
        }
    }

    private func delete(_ target: MeetingDeleteTarget) async {
        do {
            try await model.deleteRecording(target.recording, source: target.source)
        } catch {
            deletionError = error.localizedDescription
        }
        pendingDelete = nil
    }
}

struct MeetingDeleteTarget {
    let recording: LocalRecording?
    let source: Source?
}

struct MeetingRow: View {
    let recording: LocalRecording?
    let source: Source?

    private var title: String { recording?.title ?? source?.title ?? "Untitled Meeting" }
    private var state: String {
        if let recording {
            if recording.state == .needsRepair || recording.state == .missingFile { return recording.state.title }
            if recording.serverSourceId != nil {
                switch recording.state {
                case .ready: return "Ready"
                case .processing, .uploading: return "Processing"
                case .failed: return "Server Error"
                default: return "On Server"
                }
            }
            return recording.state == .failed ? "Send Failed" : "Not Sent"
        }
        switch source?.processingStatus {
        case .pending, .processing: return "Processing"
        case .ready: return "Ready"
        case .partial: return "Uploaded · Awaiting transcription"
        case .failed: return "Needs Retry"
        case nil: return "Ready"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.notedPrimary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            StatusPill(text: state, color: statusColor)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(state)")
    }

    private var detailText: String {
        if let recording { return "\(recording.durationLabel) · \(recording.createdAt.formatted(date: .abbreviated, time: .shortened))" }
        if let durationMs = source?.durationMs { return "\(timeLabel(TimeInterval(durationMs) / 1000)) · \(source?.capturedAt ?? "")" }
        return source?.capturedAt ?? "Recording"
    }

    private var statusColor: Color {
        switch recording?.state {
        case .failed, .needsRepair, .missingFile: .red
        case .partial, .recovering, .interrupted, .localOnly, .queued: Color.notedAttention
        case .ready: Color.notedSuccess
        default: source?.processingStatus == .failed ? .red : Color.notedPrimary
        }
    }
}

struct MeetingDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let recording: LocalRecording?
    let source: Source?

    @State private var bundle: SourceBundle?
    @StateObject private var player = AudioPlayer()
    @State private var audioError: String?
    @State private var actionStatuses: [String: String] = [:]
    @State private var isRetrying = false
    @State private var retryError: String?
    @State private var retryNotice: String?
    @State private var sendPhase: MeetingSendPhase?
    @State private var uploadError: String?
    @State private var isSharingAudio = false
    @State private var shareNotice: String?
    @State private var showDeleteConfirmation = false
    @State private var deletionError: String?

    private var currentRecording: LocalRecording? {
        guard let recording else { return nil }
        return model.localRecordings.first(where: { $0.id == recording.id }) ?? recording
    }
    private var sourceID: String? { currentRecording?.serverSourceId ?? source?.id }
    private var localURL: URL? {
        guard let recording = currentRecording else { return nil }
        return model.localStore.resolvedURL(for: recording)
    }

    private var shareableAudioURL: URL? {
        guard let recording = currentRecording,
              recording.state != .needsRepair,
              recording.state != .missingFile,
              let localURL,
              model.localStore.byteSize(of: localURL) > 0 else { return nil }
        return localURL
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                header
                uploadControl
                playerCard
                statusBanner
                if let brief = bundle?.source.meetingBrief {
                    MeetingBriefView(brief: brief, actionStatuses: $actionStatuses, onActionStatusChange: updateActionStatus, onSeek: seek)
                } else if bundle?.source.processingStatus == .ready {
                    Card(title: "Meeting brief") { Text("No structured brief was returned for this meeting.").foregroundStyle(.secondary) }
                } else if bundle == nil && sourceID != nil {
                    ProgressView("Loading meeting record…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.lg)
                }
                transcriptSection
            }
            .padding(AppSpacing.screen)
        }
        .navigationTitle(currentRecording?.title ?? source?.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete meeting")
                .accessibilityIdentifier("delete-meeting-detail")
            }
        }
        .confirmationDialog("Delete this meeting?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await model.deleteRecording(currentRecording, source: source)
                        dismiss()
                    } catch {
                        deletionError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The audio and its derived memories will be removed. This cannot be undone.")
        }
        .alert("Could not delete meeting", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "Try again when the server is reachable.")
        }
        .task { await loadAndPoll() }
        .onDisappear { player.stop() }
        .sheet(isPresented: $isSharingAudio) {
            if let shareableAudioURL {
                AudioShareSheet(fileURL: shareableAudioURL) { completed, error in
                    if completed {
                        shareNotice = "Audio sent. Open Noted Transcriber on your Mac to watch local transcription progress."
                    } else if let error {
                        shareNotice = "Audio share did not finish: \(error.localizedDescription)"
                    } else {
                        shareNotice = "Audio share canceled. The original recording is still safe on this iPhone."
                    }
                }
            } else {
                ContentUnavailableView("Audio unavailable", systemImage: "waveform.slash", description: Text("This recording is no longer available on this iPhone."))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(currentRecording?.title ?? source?.title ?? "Untitled Meeting")
                .font(.title.bold())
                .lineLimit(3)
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "calendar")
                Text(currentRecording?.createdAt.formatted(date: .abbreviated, time: .shortened) ?? source?.capturedAt ?? "")
                StatusPill(text: uploadStatusText, color: uploadStatusColor)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var uploadControl: some View {
        if let recording = currentRecording {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if recording.state == .needsRepair || recording.state == .missingFile {
                    Label("Cannot send this recording", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(recording.lastError ?? "The audio is missing or incomplete.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if recording.serverSourceId != nil {
                    Label("Saved on the server", systemImage: "checkmark.icloud.fill")
                        .font(.headline)
                        .foregroundStyle(Color.notedSuccess)
                    Text(serverProgressText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Only on this iPhone", systemImage: "iphone")
                        .font(.headline)
                    Text("This recording will stay private on this phone until you choose to send it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if shareableAudioURL != nil {
                    Button {
                        shareNotice = nil
                        isSharingAudio = true
                    } label: {
                        Label("Share Audio File", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("share-recording-\(recording.id.uuidString)")
                    Text("AirDrop it to your Mac or save it to Files for local Whisper. Sharing does not upload it to Noted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let shareNotice {
                        Label(shareNotice, systemImage: shareNotice.hasPrefix("Audio sent") ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(shareNotice.hasPrefix("Audio sent") ? Color.notedSuccess : Color.notedAttention)
                    }
                }
                if recording.serverSourceId == nil {
                    Button {
                        sendToServer(recording.id)
                    } label: {
                        if let sendPhase {
                            HStack {
                                ProgressView().tint(.white)
                                Text(sendPhase.title + "…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Send to Noted Cloud", systemImage: "icloud.and.arrow.up.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sendPhase != nil || !model.authenticated || shareableAudioURL == nil)
                    .accessibilityIdentifier("send-recording-\(recording.id.uuidString)")
                    if !model.authenticated {
                        Text("Connect to the server in Settings before sending.")
                            .font(.footnote)
                            .foregroundStyle(Color.notedAttention)
                    }
                }
                if let uploadError {
                    Text(uploadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(AppSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.card))
        }
    }

    private var uploadStatusText: String {
        guard let recording = currentRecording else { return source?.processingStatus.rawValue.capitalized ?? "Ready" }
        if recording.state == .needsRepair || recording.state == .missingFile { return recording.state.title }
        if recording.serverSourceId != nil {
            switch recording.state {
            case .ready: return "Ready"
            case .processing, .uploading: return "Processing"
            case .failed: return "Server Error"
            default: return "On Server"
            }
        }
        return recording.state == .failed ? "Send Failed" : "Not Sent"
    }

    private var uploadStatusColor: Color {
        guard let recording = currentRecording else { return source?.processingStatus == .failed ? .red : Color.notedPrimary }
        if recording.state == .needsRepair || recording.state == .missingFile || recording.state == .failed { return .red }
        return recording.serverSourceId == nil ? Color.notedAttention : Color.notedSuccess
    }

    private var serverProgressText: String {
        switch currentRecording?.state {
        case .ready: "Audio, transcript, and meeting record are ready."
        case .processing: "Audio uploaded. The server is processing it."
        case .partial: "Audio uploaded. Transcription setup is still required."
        case .failed: "Audio uploaded, but server processing needs attention."
        default: "The server has confirmed receipt of the audio."
        }
    }

    private var serverIsProcessing: Bool {
        switch bundle?.source.processingStatus {
        case .pending, .processing: return true
        default: return currentRecording?.state == .processing
        }
    }

    private var playerCard: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Text(timeLabel(player.currentTime)).monospacedDigit()
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 1))
                    .accessibilityLabel("Playback position")
                Text(timeLabel(player.duration)).monospacedDigit()
            }
            .font(.caption)
            if !player.canPlay {
                Label(audioError ?? player.errorMessage ?? "Preparing audio…", systemImage: audioError == nil && player.errorMessage == nil ? "hourglass" : "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(audioError == nil && player.errorMessage == nil ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { _ = player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(player.isPlaying ? "Pause meeting playback" : "Play meeting recording")
            .accessibilityValue(player.canPlay ? "(timeLabel(player.currentTime)) of (timeLabel(player.duration))" : "Audio unavailable")
            .disabled(!player.canPlay)
            if let recording = currentRecording, !recording.bookmarks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(recording.bookmarks) { mark in
                            Button("Moment \(timeLabel(mark.timestamp))") { seek(mark.timestamp) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.card)
        .background(Color.notedMemory.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.card))
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let sendPhase {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                ProgressView()
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(sendPhase.title)
                        .font(.callout.weight(.semibold))
                    Text(sendPhase.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("You can leave this screen; the recording remains safe on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(AppSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.notedMemory.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(sendPhase.title). \(sendPhase.detail)")
        }
        if sendPhase == nil && serverIsProcessing {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                ProgressView()
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Noted is still processing this recording")
                        .font(.callout.weight(.semibold))
                    Text("The server has received it and is working on the transcript and meeting details. You can leave this screen and return later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(AppSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.notedMemory.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Noted is still processing this recording. The server has received it and is working on the transcript and meeting details.")
        }
        if isRetrying {
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                Text("Transcribing and processing this recording…")
            }
            .font(.callout)
            .foregroundStyle(Color.notedMemory)
            .padding(AppSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.notedMemory.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Retrying processing")
        }
        if let retryError {
            Label(retryError, systemImage: "xmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
        if let retryNotice {
            Label(retryNotice, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(Color.notedSuccess)
        }
        if let error = audioError ?? player.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color.notedAttention)
        }
        if let processingError = bundle?.source.processingError ?? source?.processingError ?? currentRecording?.lastError {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                let awaitingSetup = processingError.localizedCaseInsensitiveContains("no transcription provider is configured")
                Label(awaitingSetup ? "Uploaded · awaiting transcription setup" : "This meeting is safe on the device, but processing needs attention.", systemImage: awaitingSetup ? "clock.badge.exclamationmark" : "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Color.notedAttention)
                Text(processingError).font(.footnote).foregroundStyle(.secondary)
                if awaitingSetup {
                    Text("Configure a transcription provider on the server before retrying processing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if sourceID != nil && model.authenticated {
                    Button { retryProcessing() } label: {
                        if isRetrying {
                            HStack(spacing: AppSpacing.xs) {
                                ProgressView()
                                Text("Retrying…")
                            }
                        } else {
                            Text("Retry processing")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRetrying)
                }
            }
            .padding(AppSpacing.card)
            .background(Color.notedAttention.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.card))
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("TRANSCRIPT")
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(.secondary)
            if let segments = bundle?.transcript.segments, !segments.isEmpty {
                ForEach(segments) { segment in
                    Button { seek(segment.seekTime) } label: {
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Text(segment.startMs.map { timeLabel(TimeInterval($0) / 1000) } ?? "—")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.notedPrimary)
                                .frame(minWidth: 62, alignment: .leading)
                            Text(segment.text)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, AppSpacing.xs)
                }
            } else if let transcriptStatus = bundle?.source.transcriptStatus, transcriptStatus == .failed || transcriptStatus == .partial {
                Text("The audio is saved, but a complete transcript is not available yet.").foregroundStyle(.secondary)
            } else {
                Text("Transcript will appear here after upload and processing.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seek(_ time: TimeInterval) {
        player.seek(to: time)
    }

    private func loadAndPoll() async {
        await load()
        guard sourceID != nil else { return }
        for _ in 0..<120 where !Task.isCancelled {
            guard let current = bundle?.source.processingStatus, current == .pending || current == .processing else { break }
            try? await Task.sleep(for: .seconds(3))
            await loadBundle()
        }
    }

    private func load() async {
        audioError = nil
        await loadBundle()
        do {
            if let localURL, model.localStore.byteSize(of: localURL) > 0 {
                try player.load(url: localURL)
            } else if let id = sourceID {
                let temporary = try await model.api.downloadAudio(sourceId: id)
                try player.load(url: temporary)
            } else {
                throw AudioPlayerError.fileMissing
            }
        } catch {
            audioError = error.localizedDescription
        }
    }

    private func loadBundle() async {
        guard let id = sourceID else { return }
        bundle = await model.bundle(for: id)
    }

    private func retryProcessing() {
        guard let sourceID, !isRetrying else { return }
        retryError = nil
        retryNotice = nil
        isRetrying = true
        Task {
            defer { isRetrying = false }
            do {
                try await model.api.reprocess(sourceID: sourceID)
                try? await Task.sleep(for: .milliseconds(300))
                for _ in 0..<60 where !Task.isCancelled {
                    await loadBundle()
                    if let status = bundle?.source.processingStatus,
                       status != .pending && status != .processing {
                        await model.refresh()
                        retryNotice = status == .ready
                            ? "Processing complete."
                            : "Processing finished, but this recording still needs attention."
                        return
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
                retryNotice = "Processing is still running on the server. You can leave this screen and return later."
            } catch {
                retryError = error.localizedDescription
            }
        }
    }

    private func sendToServer(_ id: UUID) {
        uploadError = nil
        sendPhase = .uploading
        Task {
            do {
                try await model.uploadRecording(id: id)
                await loadBundle()
                sendPhase = .processing
                await waitForServerProcessing()
            } catch {
                uploadError = error.localizedDescription
                sendPhase = nil
            }
        }
    }

    private func waitForServerProcessing() async {
        guard sourceID != nil else {
            sendPhase = nil
            return
        }

        for _ in 0..<180 where !Task.isCancelled {
            await loadBundle()
            switch bundle?.source.processingStatus {
            case .ready:
                await model.refresh()
                sendPhase = nil
                return
            case .failed, .partial:
                sendPhase = nil
                return
            case .pending, .processing, nil:
                try? await Task.sleep(for: .seconds(2))
            }
        }

        sendPhase = nil
        uploadError = "The recording was received, but processing is still running. You can leave this screen and check back later."
    }

    private func updateActionStatus(_ item: MeetingActionItem, _ status: String) {
        guard let sourceID else { return }
        actionStatuses[item.id] = status
        Task { _ = try? await model.api.updateActionItem(sourceID: sourceID, actionItemID: item.id, status: status) }
    }
}

struct MeetingBriefView: View {
    let brief: MeetingBrief
    @Binding var actionStatuses: [String: String]
    let onActionStatusChange: (MeetingActionItem, String) -> Void
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            Card(title: "Summary") { Text(brief.summary.isEmpty ? "No summary was generated." : brief.summary) }
            claimSection(title: "Key points", claims: brief.keyPoints)
            claimSection(title: "Decisions", claims: brief.decisions)
            actionSection
            claimSection(title: "Suggested follow-ups", claims: brief.suggestedFollowUps)
            claimSection(title: "Unresolved questions", claims: brief.unresolvedQuestions)
        }
    }

    @ViewBuilder
    private func claimSection(title: String, claims: [MeetingClaim]) -> some View {
        if !claims.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(title.uppercased()).font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
                ForEach(claims) { claim in
                    ClaimRow(claim: claim, onSeek: onSeek)
                }
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if !brief.actionItems.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("ACTION ITEMS").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
                ForEach(brief.actionItems) { item in
                    let status = actionStatuses[item.id] ?? item.status
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        Button {
                            onActionStatusChange(item, status == "done" ? "open" : "done")
                        } label: {
                            Image(systemName: status == "done" ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(status == "done" ? Color.notedSuccess : Color.notedPrimary)
                        }
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            ClaimRow(claim: MeetingClaim(id: item.id, text: item.text, confidence: item.confidence, state: item.state, evidenceRefs: item.evidenceRefs), onSeek: onSeek)
                            if let owner = item.owner { InferredValueLabel(label: "Owner", value: owner) }
                            if let dueAt = item.dueAt { InferredValueLabel(label: "Due", value: dueAt) }
                        }
                    }
                }
            }
        }
    }
}

struct ClaimRow: View {
    let claim: MeetingClaim
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Text(claim.text)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if claim.state != .confirmed {
                    Text("Generated")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
            if let evidence = claim.evidenceRefs.first, let startMs = evidence.startMs {
                Button("Evidence · \(timeLabel(TimeInterval(startMs) / 1000))") { onSeek(TimeInterval(startMs) / 1000) }
                    .font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.card)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: AppRadius.card))
    }
}

struct InferredValueLabel: View {
    let label: String
    let value: InferredValue

    var body: some View {
        Label("\(label): \(value.value) · Suggested", systemImage: "sparkles")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Presents the system share sheet for a local recording file.
/// The file URL is passed directly so AirDrop and Files receive the original audio.
private struct AudioShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    let onComplete: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in
                onComplete(completed, error)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
