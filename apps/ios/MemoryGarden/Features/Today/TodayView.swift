import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) { Text("TODAY").font(.caption.bold()).tracking(1.5).foregroundStyle(Color.notedPrimary); Text("Good morning.").font(.largeTitle.bold()); Text("Capture first. Noted will take care of the remembering.").foregroundStyle(.secondary) }
                    NavigationLink { RecordView() } label: { Label("Record something", systemImage: "record.circle.fill").font(.headline).frame(maxWidth: .infinity).padding().background(Color.notedPrimary, in: RoundedRectangle(cornerRadius: AppRadius.card)).foregroundStyle(.white) }.buttonStyle(.plain)
                    if let today = model.today, !today.openLoops.isEmpty { VStack(alignment: .leading, spacing: 10) { Text("OPEN LOOPS").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary); ForEach(today.openLoops) { loop in HStack { Button { Task { await model.resolveLoop(loop) } } label: { Image(systemName: "circle") }; Text(loop.description); Spacer() } } } } else { EmptyState(icon: "checkmark.circle", title: "Nothing waiting on you", message: "Open loops from your captures will show up here.").frame(height: 170) }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECENT RECORDINGS").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
                        ForEach(model.localRecordings.prefix(3)) { recording in
                            NavigationLink { RecordingDetailView(recording: recording, source: model.serverRecordings.first { $0.id == recording.serverSourceId }) } label: { LocalRecordingRow(recording: recording) }.buttonStyle(.plain)
                        }
                        if model.localRecordings.isEmpty { Text("Your first recording is waiting.").foregroundStyle(.secondary) }
                    }
                }.padding()
            }
            .navigationTitle("Today")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") } } }
        }
    }
}
