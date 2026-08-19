import SwiftUI

struct RecordingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if !model.localRecordings.isEmpty {
                    Section("On this iPhone") { ForEach(model.localRecordings) { recording in NavigationLink { RecordingDetailView(recording: recording, source: model.serverRecordings.first { $0.id == recording.serverSourceId }) } label: { LocalRecordingRow(recording: recording) } } }
                }
                let serverOnly = model.serverRecordings.filter { source in !model.localRecordings.contains { $0.serverSourceId == source.id } }
                if !serverOnly.isEmpty { Section("From Memory Garden") { ForEach(serverOnly) { source in NavigationLink { RecordingDetailView(recording: nil, source: source) } label: { ServerRecordingRow(source: source) } } } }
                if model.localRecordings.isEmpty && model.serverRecordings.isEmpty { EmptyState(icon: "waveform", title: "No recordings yet", message: "Your next recording will appear here immediately, even before upload.") }
            }
            .navigationTitle("Recordings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.syncUploads(); await model.refresh() } } label: { Image(systemName: "arrow.clockwise") } } }
            .refreshable { await model.refresh() }
        }
    }
}

struct LocalRecordingRow: View {
    let recording: LocalRecording
    var body: some View { HStack(spacing: 12) { Image(systemName: "waveform.circle.fill").font(.title2).foregroundStyle(.indigo); VStack(alignment: .leading) { Text(recording.title).font(.headline); Text("\(recording.durationLabel) · \(recording.state.title)").font(.caption).foregroundStyle(.secondary) }; Spacer(); StatusPill(text: recording.state.title, color: recording.state == .failed ? .red : .indigo) } }
}

struct ServerRecordingRow: View {
    let source: Source
    var body: some View { HStack(spacing: 12) { Image(systemName: "waveform.circle.fill").font(.title2).foregroundStyle(.indigo); VStack(alignment: .leading) { Text(source.title).font(.headline); Text(source.durationMs.map { timeLabel(TimeInterval($0) / 1000) } ?? "Recording").font(.caption).foregroundStyle(.secondary) }; Spacer(); StatusPill(text: source.processingStatus.rawValue.capitalized, color: source.processingStatus == .failed ? .red : .indigo) } }
}

struct RecordingDetailView: View {
    @EnvironmentObject private var model: AppModel
    let recording: LocalRecording?
    let source: Source?
    @State private var bundle: SourceBundle?
    @State private var player = AudioPlayer()
    @State private var audioError: String?

    private var sourceID: String? { recording?.serverSourceId ?? source?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                playerCard
                if let error = audioError { Text(error).font(.footnote).foregroundStyle(.orange) }
                if let message = bundle?.source.processingError { Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                if let summary = bundle?.source.summary, !summary.isEmpty { Card(title: "Summary") { Text(summary) } }
                transcriptSection
                memorySection
                loopSection
            }.padding()
        }
        .navigationTitle(recording?.title ?? source?.title ?? "Recording")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View { VStack(alignment: .leading, spacing: 8) { Text(recording?.title ?? source?.title ?? "Recording").font(.title.bold()); HStack { Image(systemName: "calendar"); Text(recording.map { $0.createdAt.formatted(date: .abbreviated, time: .shortened) } ?? source?.capturedAt ?? ""); if let recording { StatusPill(text: recording.state.title, color: .indigo) } else if let source { StatusPill(text: source.processingStatus.rawValue.capitalized, color: .indigo) } }.font(.subheadline).foregroundStyle(.secondary) } }

    private var playerCard: some View { VStack(spacing: 14) { HStack { Text(timeLabel(player.currentTime)).monospacedDigit(); Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 1)); Text(timeLabel(player.duration)).monospacedDigit() }.font(.caption); Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 56)) }.accessibilityLabel(player.isPlaying ? "Pause playback" : "Play recording"); if let recording, !recording.bookmarks.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(recording.bookmarks) { mark in Button("\(timeLabel(mark.timestamp))") { player.seek(to: mark.timestamp) }.buttonStyle(.bordered) } } } } }.padding().background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 22)) }

    private var transcriptSection: some View { VStack(alignment: .leading, spacing: 10) { Text("TRANSCRIPT").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary); if let segments = bundle?.transcript.segments, !segments.isEmpty { ForEach(segments) { segment in Button { player.seek(to: segment.seekTime); if !player.isPlaying { player.toggle() } } label: { HStack(alignment: .top, spacing: 12) { Text(segment.startMs.map { timeLabel(TimeInterval($0) / 1000) } ?? "—").font(.caption.monospacedDigit()).foregroundStyle(.indigo).frame(width: 60, alignment: .leading); Text(segment.text).foregroundStyle(.primary); Spacer() } }.buttonStyle(.plain).padding(.vertical, 4) } } else { Text("Transcript will appear here after upload and processing.").foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading) }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEMORIES").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
            ForEach(bundle?.memories ?? []) { memory in
                Card(title: memory.memoryType.capitalized) {
                    Text(memory.content)
                    if let ref = memory.evidenceRefs?.first, let start = ref.startMs {
                        Button("Evidence · \(timeLabel(TimeInterval(start) / 1000))") { player.seek(to: TimeInterval(start) / 1000); if !player.isPlaying { player.toggle() } }.font(.caption.bold())
                    }
                }
            }
            if (bundle?.memories ?? []).isEmpty { Text("Memories are still being interpreted.").foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loopSection: some View { VStack(alignment: .leading, spacing: 10) { Text("OPEN LOOPS").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary); ForEach(bundle?.openLoops ?? []) { loop in HStack { Button { Task { await model.resolveLoop(loop) } } label: { Image(systemName: "circle") }; Text(loop.description); Spacer() } } }.frame(maxWidth: .infinity, alignment: .leading) }

    private func load() async { if let id = sourceID { bundle = await model.bundle(for: id) }; do { if let recording { try player.load(url: recording.localFileURL) } else if let id = sourceID { let temp = try await model.api.downloadAudio(sourceId: id); let local = model.localStore.newAudioURL(for: UUID()); try? FileManager.default.removeItem(at: local); try FileManager.default.moveItem(at: temp, to: local); try player.load(url: local) } } catch { audioError = error.localizedDescription } }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); content }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 16)) }
}
