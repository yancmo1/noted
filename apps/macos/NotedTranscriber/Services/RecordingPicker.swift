import AppKit
import UniformTypeIdentifiers

@MainActor
enum RecordingPicker {
    static func choose() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose recordings"
        panel.message = "Select one or more audio files or videos containing audio."
        panel.prompt = "Transcribe"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = RecordingImport.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.urls : []
    }
}
