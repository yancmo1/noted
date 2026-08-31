import Foundation
import Testing
@testable import NotedTranscriber

struct RecordingImportTests {
    @Test func allowsHostedHTTPSAndLoopbackHTTPOnly() {
        #expect(NotedUploader.isAllowedBaseURL(URL(string: "https://noted.shepswork.com")!))
        #expect(NotedUploader.isAllowedBaseURL(URL(string: "http://127.0.0.1:3333")!))
        #expect(NotedUploader.isAllowedBaseURL(URL(string: "http://localhost:3333")!))
        #expect(!NotedUploader.isAllowedBaseURL(URL(string: "http://noted.shepswork.com")!))
        #expect(!NotedUploader.isAllowedBaseURL(URL(string: "ftp://127.0.0.1")!))
    }

    @Test func localTranscriptionEnvironmentIncludesHomebrewPaths() {
        let path = WhisperRunner.launchEnvironment["PATH"] ?? ""
        let entries = path.split(separator: ":").map(String.init)

        #expect(entries.contains("/opt/homebrew/bin"))
        #expect(entries.contains("/usr/local/bin"))
        #expect(entries.contains("/usr/bin"))
        #expect(entries.contains("/bin"))
    }

    @Test func removesLongContiguousDecoderLoopsButKeepsShortRepetitions() {
        let repeated = [
            TranscriptSegment(startMilliseconds: 0, endMilliseconds: 4_000, text: "Yes"),
            TranscriptSegment(startMilliseconds: 4_000, endMilliseconds: 7_000, text: "Yes"),
            TranscriptSegment(startMilliseconds: 7_000, endMilliseconds: 10_000, text: "Yes"),
        ]
        #expect(WhisperRunner.cleanedSegments(repeated).map { $0.text } == ["Yes"])

        let genuine = [
            TranscriptSegment(startMilliseconds: 0, endMilliseconds: 1_000, text: "Yes"),
            TranscriptSegment(startMilliseconds: 1_000, endMilliseconds: 2_000, text: "Yes"),
            TranscriptSegment(startMilliseconds: 4_000, endMilliseconds: 5_000, text: "Yes"),
        ]
        #expect(WhisperRunner.cleanedSegments(genuine).map { $0.text } == ["Yes", "Yes", "Yes"])
    }

    @Test func acceptsCommonAudioAndVideoExtensions() {
        for name in ["meeting.m4a", "memo.mp3", "audio.wav", "voice.caf", "capture.mkv", "call.mov", "clip.mp4", "recording.m4v", "recording.webm"] {
            #expect(RecordingImport.supports(URL(fileURLWithPath: name)))
        }
    }

    @Test func rejectsUnrelatedFiles() {
        #expect(!RecordingImport.supports(URL(fileURLWithPath: "notes.pdf")))
        #expect(!RecordingImport.supports(URL(fileURLWithPath: "transcript.txt")))
    }

    @Test func formatsTheSingleTimestampedTranscriptDocument() {
        let job = TranscriptionJob(
            id: UUID(),
            title: "Meeting",
            sourcePath: "/tmp/meeting.m4a",
            sourceFingerprint: "fingerprint",
            createdAt: .now,
            updatedAt: .now,
            state: .ready,
            transcript: "First line\nSecond line",
            segments: [
                TranscriptSegment(startMilliseconds: 0, endMilliseconds: 1_000, text: "First line"),
                TranscriptSegment(startMilliseconds: 62_000, endMilliseconds: 63_000, text: "Second line")
            ],
            detectedLanguage: "en",
            errorMessage: nil,
            outputPath: "/tmp/meeting-output"
        )

        #expect(job.timestampedTranscript == "[00:00:00] First line\n[00:01:02] Second line")
    }
}
