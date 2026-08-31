import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureView()
        Task { await importSharedAudio() }
    }

    private func configureView() {
        let stack = UIStackView(arrangedSubviews: [statusLabel, closeButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = "Saving recording to Noted…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)

        closeButton.setTitle("Close", for: .normal)
        closeButton.isHidden = true
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func importSharedAudio() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first,
              let typeIdentifier = supportedTypeIdentifier(for: provider) else {
            showFailure("Noted could not find an audio file in this share.")
            return
        }

        do {
            let fileURL = try await provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            _ = try SharedImportInbox.enqueue(
                fileURL: fileURL,
                title: item.attributedContentText?.string,
                mimeType: UTType(typeIdentifier)?.preferredMIMEType
            )
            statusLabel.text = "Saved to Noted. Open Noted to upload and process it."
            try? await Task.sleep(for: .milliseconds(900))
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            showFailure("Noted could not save this recording. \(error.localizedDescription)")
        }
    }

    private func supportedTypeIdentifier(for provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .audio)
        } ?? provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .fileURL) == true
        }
    }

    @MainActor
    private func showFailure(_ message: String) {
        statusLabel.text = message
        closeButton.isHidden = false
    }

    @objc private func close() {
        extensionContext?.cancelRequest(withError: NSError(domain: "NotedShareExtension", code: 1))
    }
}

@MainActor
private extension NSItemProvider {
    func loadFileRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    // The provider-owned URL is temporary and may be deleted as soon as
                    // this callback returns. Copy it while the provider still owns it so
                    // the async caller never receives a stale path.
                    let extensionName = url.pathExtension.isEmpty
                        ? (UTType(typeIdentifier)?.preferredFilenameExtension ?? "m4a")
                        : url.pathExtension
                    let copyURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("noted-share-\(UUID().uuidString).\(extensionName)")
                    let accessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessingSecurityScopedResource { url.stopAccessingSecurityScopedResource() }
                    }
                    do {
                        try FileManager.default.copyItem(at: url, to: copyURL)
                        continuation.resume(returning: copyURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: SharedImportInboxError.fileUnavailable)
                }
            }
        }
    }
}
