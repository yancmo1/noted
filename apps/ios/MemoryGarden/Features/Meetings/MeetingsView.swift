import SwiftUI

struct MeetingsView: View {
    @EnvironmentObject private var model: AppModel

    private var serverByID: [String: Source] {
        Dictionary(uniqueKeysWithValues: model.serverRecordings.map { ($0.id, $0) })
    }

    private var serverOnly: [Source] {
        model.serverRecordings.filter { source in
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
                        }
                    }
                }

                if !serverOnly.isEmpty {
                    Section("From Memory Garden") {
                        ForEach(serverOnly) { source in
                            NavigationLink {
                                MeetingDetailView(recording: nil, source: source)
                            } label: {
                                MeetingRow(recording: nil, source: source)
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
        }
    }
}

struct MeetingRow: View {
    let recording: LocalRecording?
    let source: Source?

    private var title: String { recording?.title ?? source?.title ?? "Untitled Meeting" }
    private var state: String {
        if let recording { return recording.state.title }
        switch source?.processingStatus {
        case .pending, .processing: return "Processing"
        case .ready: return "Ready"
        case .partial: return "Partial"
        case .failed: return "Needs Retry"
        case nil: return "Ready"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.indigo)
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
        case .failed, .missingFile: .red
        case .partial, .recovering, .interrupted: .orange
        case .ready: .green
        default: source?.processingStatus == .failed ? .red : .indigo
        }
    }
}

struct MeetingDetailView: View {
    @EnvironmentObject private var model: AppModel
    let recording: LocalRecording?
    let source: Source?

    @State private var bundle: SourceBundle?
    @State private var player = AudioPlayer()
    @State private var audioError: String?
    @State private var actionStatuses: [String: String] = [:]
    @State private var isRetrying = false

    private var sourceID: String? { recording?.serverSourceId ?? source?.id }
    private var localURL: URL? { recording?.localFileURL }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                header
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
        .navigationTitle(recording?.title ?? source?.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAndPoll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(recording?.title ?? source?.title ?? "Untitled Meeting")
                .font(.title.bold())
                .lineLimit(3)
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "calendar")
                Text(recording?.createdAt.formatted(date: .abbreviated, time: .shortened) ?? source?.capturedAt ?? "")
                StatusPill(text: recording?.state.title ?? source?.processingStatus.rawValue.capitalized ?? "Ready", color: .indigo)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(player.isPlaying ? "Pause meeting playback" : "Play meeting recording")
            if let recording, !recording.bookmarks.isEmpty {
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
        .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.card))
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let error = audioError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
        if let processingError = bundle?.source.processingError ?? source?.processingError ?? recording?.lastError {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("This meeting is safe on the device, but processing needs attention.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Text(processingError).font(.footnote).foregroundStyle(.secondary)
                if sourceID != nil && model.authenticated {
                    Button("Retry processing") { retryProcessing() }
                        .buttonStyle(.bordered)
                        .disabled(isRetrying)
                }
            }
            .padding(AppSpacing.card)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.card))
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
                                .foregroundStyle(.indigo)
                                .frame(width: 62, alignment: .leading)
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
        for _ in 0..<20 where !Task.isCancelled {
            guard let current = bundle?.source.processingStatus, current == .pending || current == .processing else { break }
            try? await Task.sleep(for: .seconds(3))
            await loadBundle()
        }
    }

    private func load() async {
        await loadBundle()
        do {
            if let localURL, FileManager.default.fileExists(atPath: localURL.path) {
                try player.load(url: localURL)
            } else if let id = sourceID {
                let temporary = try await model.api.downloadAudio(sourceId: id)
                try player.load(url: temporary)
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
        guard let sourceID else { return }
        isRetrying = true
        Task {
            try? await model.api.reprocess(sourceID: sourceID)
            await loadBundle()
            isRetrying = false
        }
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
                                .foregroundStyle(status == "done" ? .green : .indigo)
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
