import Foundation

enum WhisperRunnerError: LocalizedError {
    case wrapperMissing
    case transcriptionFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .wrapperMissing:
            "The Noted transcription engine was not found. Reinstall the local Whisper setup, then try again."
        case .transcriptionFailed(let details):
            details.isEmpty ? "Local transcription failed. Open the run log for details." : details
        case .outputMissing:
            "Whisper finished without producing a transcript. Try the recording again or inspect its audio track."
        }
    }
}

struct WhisperOutput: Sendable {
    let transcript: String
    let segments: [TranscriptSegment]
    let language: String?
}

enum WhisperRunner {
    static var wrapperURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Noted/transcription/bin/noted-transcribe")
    }

    /// Finder-launched apps do not reliably inherit Homebrew's shell PATH.
    /// Keep the wrapper's command lookup working for both Apple Silicon and
    /// Intel Homebrew installations, while preserving any user PATH entries.
    static var launchEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let inheritedPaths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        var paths: [String] = []

        for path in fallbackPaths + inheritedPaths where !path.isEmpty && !paths.contains(path) {
            paths.append(path)
        }

        environment["PATH"] = paths.joined(separator: ":")
        return environment
    }

    /// Whisper can enter a decoder loop when a quiet or indistinct section is
    /// interpreted as speech. Keep two genuine consecutive repetitions, but
    /// remove a longer run of directly contiguous identical segments.
    static func cleanedSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var cleaned: [TranscriptSegment] = []
        var repeatedSegments: [TranscriptSegment] = []

        for segment in segments where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let previous = repeatedSegments.last ?? cleaned.last
            if let previous, isLikelyDecoderLoop(previous, segment) {
                repeatedSegments.append(segment)
                continue
            }

            if repeatedSegments.count == 1 {
                cleaned.append(repeatedSegments[0])
            }
            repeatedSegments.removeAll(keepingCapacity: true)
            cleaned.append(segment)
        }

        if repeatedSegments.count == 1 {
            cleaned.append(repeatedSegments[0])
        }
        return cleaned
    }

    private static func normalizedSegmentText(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isLikelyDecoderLoop(_ previous: TranscriptSegment, _ current: TranscriptSegment) -> Bool {
        guard normalizedSegmentText(previous.text) == normalizedSegmentText(current.text) else { return false }
        let gap = current.startMilliseconds - previous.endMilliseconds
        return gap >= -100 && gap <= 250
    }

    static func transcribe(sourceURL: URL, outputURL: URL) async throws -> WhisperOutput {
        let wrapper = wrapperURL
        guard FileManager.default.isExecutableFile(atPath: wrapper.path) else {
            throw WhisperRunnerError.wrapperMissing
        }

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let logURL = outputURL.appendingPathComponent("launcher.log")

        let status = try await Task.detached(priority: .userInitiated) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }

            let process = Process()
            process.executableURL = wrapper
            process.arguments = [sourceURL.path, outputURL.path]
            process.environment = launchEnvironment
            process.standardOutput = log
            process.standardError = log
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value

        guard status == 0 else {
            let details = (try? String(contentsOf: logURL, encoding: .utf8))?
                .split(separator: "\n")
                .suffix(4)
                .joined(separator: "\n") ?? ""
            throw WhisperRunnerError.transcriptionFailed(details)
        }

        let jsonURL = outputURL.appendingPathComponent("transcript.json")
        let textURL = outputURL.appendingPathComponent("transcript.txt")
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              FileManager.default.fileExists(atPath: textURL.path) else {
            throw WhisperRunnerError.outputMissing
        }

        let document = try JSONDecoder().decode(WhisperDocument.self, from: Data(contentsOf: jsonURL))
        let rawTranscript = try String(contentsOf: textURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawSegments = document.transcription.map {
            TranscriptSegment(
                startMilliseconds: $0.offsets.from,
                endMilliseconds: $0.offsets.to,
                text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let segments = Self.cleanedSegments(rawSegments)
        let transcript = segments.isEmpty ? rawTranscript : segments.map { $0.text }.joined(separator: "\n")
        return WhisperOutput(transcript: transcript, segments: segments, language: document.result.language)
    }
}
