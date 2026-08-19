import SwiftUI

struct AskView: View {
    @EnvironmentObject private var model: AppModel
    @State private var question = ""
    @State private var response: AskResponse?
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) { Text("ASK YOUR MEMORY").font(.caption.bold()).tracking(1.2).foregroundStyle(.indigo); Text("What do you remember?").font(.system(size: 32, weight: .bold, design: .rounded)); Text("Answers stay grounded in what you have captured.").foregroundStyle(.secondary) }
                    HStack { TextField("What did Bill say about the training cohort?", text: $question, axis: .vertical).textFieldStyle(.roundedBorder); Button { submit() } label: { Image(systemName: isBusy ? "hourglass" : "arrow.up.circle.fill").font(.title2) }.disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy) }
                    if let error { Text(error).foregroundStyle(.red) }
                    if let response { VStack(alignment: .leading, spacing: 14) { Text("GROUNDED ANSWER").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary); Text(response.answer).font(.body); Text("EVIDENCE").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary); ForEach(response.citations) { citation in NavigationLink { RecordingDetailView(recording: model.localRecordings.first { $0.serverSourceId == citation.sourceId }, source: model.serverRecordings.first { $0.id == citation.sourceId }) } label: { HStack { Image(systemName: "waveform"); VStack(alignment: .leading) { Text(citation.sourceTitle ?? "Recording").font(.headline); Text(citation.quote ?? citation.content).font(.caption).lineLimit(2); if let start = citation.startMs { Text("Jump to \(timeLabel(TimeInterval(start) / 1000))").font(.caption.bold()).foregroundStyle(.indigo) } }; Spacer(); Image(systemName: "chevron.right") } }.buttonStyle(.plain).padding().background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14)) } } }
                }.padding()
            }.navigationTitle("Ask")
        }
    }

    private func submit() { isBusy = true; error = nil; Task { do { response = try await model.ask(question) } catch let caught { error = caught.localizedDescription }; isBusy = false } }
}
