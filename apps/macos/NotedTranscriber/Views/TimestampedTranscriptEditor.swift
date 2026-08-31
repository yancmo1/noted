import AppKit
import SwiftUI

private extension NSAttributedString.Key {
    static let notedTimestamp = NSAttributedString.Key("NotedTimestamp")
}

struct TimestampedTranscriptEditor: NSViewRepresentable {
    let segments: [TranscriptSegment]
    let fallbackText: String
    let onChange: ([TranscriptSegment], String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: NotedSpacing.md, height: NotedSpacing.md)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Editable timestamped transcript")
        textView.setAccessibilityRole(.textArea)

        scrollView.documentView = textView
        context.coordinator.apply(segments: segments, fallbackText: fallbackText, to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.onChange = onChange
        context.coordinator.apply(segments: segments, fallbackText: fallbackText, to: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: ([TranscriptSegment], String) -> Void
        private var currentSegments: [TranscriptSegment] = []
        private var currentFallbackText = ""
        private var protectedRanges: [NSRange] = []
        private var renderedSignature = ""
        private var isApplyingDocument = false

        init(onChange: @escaping ([TranscriptSegment], String) -> Void) {
            self.onChange = onChange
        }

        func apply(segments: [TranscriptSegment], fallbackText: String, to textView: NSTextView) {
            let signature = documentSignature(segments: segments, fallbackText: fallbackText)
            guard signature != renderedSignature else { return }

            currentSegments = segments
            currentFallbackText = fallbackText
            isApplyingDocument = true

            let selectedRange = textView.selectedRange()
            let document = makeDocument(segments: segments, fallbackText: fallbackText)
            textView.textStorage?.setAttributedString(document)

            protectedRanges = timestampRanges(in: textView)
            renderedSignature = signature
            isApplyingDocument = false

            let maxLocation = textView.string.utf16.count
            let safeLocation = min(selectedRange.location, maxLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !protectedRanges.contains(where: { protectedRange in
                NSIntersectionRange(affectedCharRange, protectedRange).length > 0
                    || (affectedCharRange.length == 0 && NSLocationInRange(affectedCharRange.location, protectedRange))
            }) else {
                NSSound.beep()
                return false
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingDocument, let textView = notification.object as? NSTextView else { return }
            protectedRanges = timestampRanges(in: textView)

            if currentSegments.isEmpty {
                currentFallbackText = textView.string
                renderedSignature = documentSignature(segments: [], fallbackText: currentFallbackText)
                onChange([], currentFallbackText)
                return
            }

            let updatedSegments = segments(from: textView)
            let transcript = updatedSegments.map(\.text).joined(separator: "\n")
            currentSegments = updatedSegments
            renderedSignature = documentSignature(segments: updatedSegments, fallbackText: transcript)
            onChange(updatedSegments, transcript)
        }

        private func makeDocument(segments: [TranscriptSegment], fallbackText: String) -> NSAttributedString {
            let text = segments.isEmpty
                ? fallbackText
                : segments.map { "[\($0.timestamp)] \($0.text)" }.joined(separator: "\n")

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = NotedSpacing.xs / 2
            paragraphStyle.paragraphSpacing = NotedSpacing.xs

            let document = NSMutableAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ])

            guard !segments.isEmpty else { return document }

            var location = 0
            for (index, segment) in segments.enumerated() {
                let marker = "[\(segment.timestamp)]"
                let markerLength = marker.utf16.count
                let protectedLength = min(markerLength + 1, text.utf16.count - location)
                let range = NSRange(location: location, length: protectedLength)
                let markerColor = NSColor(Color.notedPrimary)
                document.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                    .foregroundColor: markerColor,
                    .notedTimestamp: true
                ], range: range)
                location += markerLength + 1 + segment.text.utf16.count
                if index < segments.count - 1 { location += 1 }
            }

            return document
        }

        private func timestampRanges(in textView: NSTextView) -> [NSRange] {
            guard let textStorage = textView.textStorage else { return [] }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            var ranges: [NSRange] = []
            textStorage.enumerateAttribute(.notedTimestamp, in: fullRange) { value, range, _ in
                if value != nil { ranges.append(range) }
            }
            return ranges.sorted { $0.location < $1.location }
        }

        private func segments(from textView: NSTextView) -> [TranscriptSegment] {
            let text = textView.string as NSString
            let ranges = timestampRanges(in: textView)
            guard ranges.count == currentSegments.count else { return currentSegments }

            return currentSegments.enumerated().map { index, originalSegment in
                let contentStart = NSMaxRange(ranges[index])
                let contentEnd = index + 1 < ranges.count ? ranges[index + 1].location : text.length
                let contentLength = max(0, contentEnd - contentStart)
                var updatedSegment = originalSegment
                updatedSegment.text = text.substring(with: NSRange(location: contentStart, length: contentLength))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return updatedSegment
            }
        }

        private func documentSignature(segments: [TranscriptSegment], fallbackText: String) -> String {
            guard !segments.isEmpty else { return "plain|\(fallbackText)" }
            return segments.map {
                "\($0.id.uuidString)|\($0.startMilliseconds)|\($0.endMilliseconds)|\($0.text)"
            }.joined(separator: "\u{1F} ")
        }
    }
}
