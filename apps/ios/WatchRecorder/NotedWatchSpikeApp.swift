import SwiftUI

@main
struct NotedWatchSpikeApp: App {
    @StateObject private var recorder = WatchSpikeRecorder()

    var body: some Scene {
        WindowGroup {
            WatchSpikeView()
                .environmentObject(recorder)
        }
    }
}

struct WatchSpikeView: View {
    @EnvironmentObject private var recorder: WatchSpikeRecorder

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if recorder.isRecording {
                    Text("● REC")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(recorder.format(recorder.elapsed))
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                    Button { recorder.mark() } label: {
                        Label("Mark", systemImage: "bookmark.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.orange)
                    .buttonStyle(.borderedProminent)
                    Button { recorder.requestStop() } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                    .buttonStyle(.bordered)
                } else {
                    Text("Noted Spike")
                        .font(.headline)
                    Picker("Audio profile", selection: $recorder.selectedProfile) {
                        ForEach(WatchAudioProfile.allCases) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Button { Task { await recorder.start() } } label: {
                        Label("Record", systemImage: "record.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                }

                if let message = recorder.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(recorder.resourceWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !recorder.records.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SPIKE HISTORY")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(recorder.records) { record in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.createdAt, style: .time)
                                        .font(.caption2)
                                    Text(recorder.format(record.duration))
                                        .font(.system(.body, design: .monospaced))
                                    Text(record.state.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if record.state != .acknowledged {
                                    Button("Retry") { recorder.retry(record) }
                                        .font(.caption2)
                                }
                                Button {
                                    recorder.requestDelete(record)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(.red)
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete recording")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
        }
        .alert("Stop recording?", isPresented: $recorder.isStopConfirmationPresented) {
            Button("Stop", role: .destructive) { recorder.confirmStop() }
            Button("Continue", role: .cancel) { recorder.cancelStop() }
        } message: {
            Text("The Watch will finalize the audio and queue it for iPhone acknowledgement.")
        }
        .alert("Delete recording?", isPresented: $recorder.isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive) { recorder.confirmDelete() }
            Button("Cancel", role: .cancel) { recorder.cancelDelete() }
        } message: {
            Text(recorder.deleteConfirmationMessage)
        }
    }
}
