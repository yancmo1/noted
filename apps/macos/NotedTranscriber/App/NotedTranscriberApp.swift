import AppKit
import SwiftUI

@main
struct NotedTranscriberApp: App {
    @State private var store = TranscriptionStore()
    @State private var transcriptWindowManager = TranscriptWindowManager()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, windowManager: transcriptWindowManager)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            AppCommands()
        }
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose Recording…") {
                NotificationCenter.default.post(name: .chooseRecording, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }
    }

}
