import SwiftUI

struct DropZoneView: View {
    let isCompact: Bool
    let onImport: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: NotedSpacing.md) {
            Image(systemName: isTargeted ? "waveform.badge.plus" : "waveform")
                .font(.system(size: isCompact ? 28 : 44, weight: .medium))
                .foregroundStyle(Color.notedPrimary)
                .symbolEffect(.bounce, value: isTargeted)

            VStack(spacing: NotedSpacing.xs) {
                Text(isCompact ? "Add another recording" : "Drop a recording here")
                    .font(isCompact ? .headline : .title2.weight(.semibold))
                if !isCompact {
                    Text("Audio and video stay on this Mac while Whisper transcribes them locally.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
            }

            Button(isCompact ? "Choose File" : "Choose a Recording") {
                let urls = RecordingPicker.choose()
                if !urls.isEmpty { onImport(urls) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.notedPrimary)
            .controlSize(.large)

            if !isCompact {
                Text("M4A, MP3, WAV, AIFF, FLAC, AAC, OGG, MP4, MOV, MKV, and WebM")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isCompact ? 150 : 310)
        .padding(NotedSpacing.lg)
        .background(
            isTargeted ? Color.notedPrimary.opacity(0.12) : Color.notedPrimary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: NotedRadius.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NotedRadius.surface)
                .strokeBorder(
                    isTargeted ? Color.notedPrimary : Color.notedPrimary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [7, 6])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            let recordings = urls.filter(RecordingImport.supports)
            guard !recordings.isEmpty else { return false }
            onImport(recordings)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording import area")
    }
}
