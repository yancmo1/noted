import AppKit
import SwiftUI

@MainActor
final class TranscriptWindowManager {
    private var windows: [UUID: TranscriptWindowController] = [:]
    private weak var mainWindow: NSWindow?
    private var mainWindowCloseObserver: NSObjectProtocol?

    func openTranscript(for jobID: UUID, store: TranscriptionStore) {
        guard let job = store.jobs.first(where: { $0.id == jobID }) else { return }

        if let existingWindow = windows[jobID]?.window {
            existingWindow.title = "Transcript · \(job.title)"
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transcript · \(job.title)"
        window.minSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false

        let frameName = "NotedTranscript.\(jobID.uuidString)"
        if !window.setFrameUsingName(frameName) {
            window.center()
        }
        window.setFrameAutosaveName(frameName)
        window.contentView = NSHostingView(rootView: TranscriptWindowView(store: store, jobID: jobID))

        let controller = TranscriptWindowController(window: window, jobID: jobID, manager: self)
        windows[jobID] = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func observeMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindowCloseObserver.map(NotificationCenter.default.removeObserver)
        mainWindow = window
        mainWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeAll()
            }
        }
    }

    func closeAll() {
        let currentWindows = Array(windows.values)
        windows.removeAll()
        currentWindows.forEach { $0.close() }
    }

    fileprivate func didCloseTranscript(for jobID: UUID) {
        windows.removeValue(forKey: jobID)
    }
}

@MainActor
private final class TranscriptWindowController: NSWindowController, NSWindowDelegate {
    let jobID: UUID
    weak var manager: TranscriptWindowManager?

    init(window: NSWindow, jobID: UUID, manager: TranscriptWindowManager) {
        self.jobID = jobID
        self.manager = manager
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("Transcript windows are created programmatically.")
    }

    func windowWillClose(_ notification: Notification) {
        manager?.didCloseTranscript(for: jobID)
    }
}

struct MainWindowRegistration: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> RegistrationView {
        RegistrationView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: RegistrationView, context: Context) {}

    final class RegistrationView: NSView {
        private let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("Main window registration is created programmatically.")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow(window)
            }
        }
    }
}
