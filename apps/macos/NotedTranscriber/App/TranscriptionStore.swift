import AppKit
import Foundation
import Observation

enum RemoteSendState: Equatable {
    case idle
    case sending
    case processing(sourceID: String)
    case sent(sourceID: String)
    case failed(String)
}

@MainActor
@Observable
final class TranscriptionStore {
    private(set) var jobs: [TranscriptionJob] = []
    private(set) var sendStates: [UUID: RemoteSendState] = [:]
    var selection: UUID?
    var importError: String?

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    var selectedJob: TranscriptionJob? {
        guard let selection else { return nil }
        return jobs.first { $0.id == selection }
    }

    func importRecordings(_ urls: [URL]) {
        importError = nil
        for url in urls {
            do {
                try importRecording(url)
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    func updateTranscript(jobID: UUID, transcript: String, segments: [TranscriptSegment]? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].transcript = transcript
        if let segments {
            jobs[index].segments = segments
        }
        jobs[index].updatedAt = Date()
        persist()
    }

    func sendToNoted(jobID: UUID, baseURL: String, password: String, rememberPassword: Bool) async {
        guard let job = jobs.first(where: { $0.id == jobID }), job.state == .ready else { return }
        sendStates[jobID] = .sending
        do {
            let result = try await NotedUploader.send(job: job, baseURL: baseURL, password: password)
            if rememberPassword { try NotedKeychain.save(password: password) }
            sendStates[jobID] = .processing(sourceID: result.sourceID)

            for _ in 0..<180 where !Task.isCancelled {
                let state = try await NotedUploader.processingState(sourceID: result.sourceID, baseURL: baseURL, password: password)
                switch state {
                case .ready:
                    sendStates[jobID] = .sent(sourceID: result.sourceID)
                    return
                case .partial, .failed:
                    sendStates[jobID] = .failed("Noted received the transcript, but processing needs attention. Open Noted to review the server status.")
                    return
                case .pending, .processing:
                    try? await Task.sleep(for: .seconds(2))
                }
            }

            sendStates[jobID] = .failed("Noted received the transcript, but local processing is still running. Check Noted again in a moment.")
        } catch {
            sendStates[jobID] = .failed(error.localizedDescription)
        }
    }

    func retry(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].state = .queued
        jobs[index].errorMessage = nil
        jobs[index].updatedAt = Date()
        persist()
        start(jobID)
    }

    func remove(_ jobID: UUID) {
        jobs.removeAll { $0.id == jobID }
        if selection == jobID { selection = jobs.first?.id }
        persist()
    }

    func revealSource(_ job: TranscriptionJob) {
        NSWorkspace.shared.activateFileViewerSelecting([job.sourceURL])
    }

    func revealOutput(_ job: TranscriptionJob) {
        NSWorkspace.shared.activateFileViewerSelecting([job.outputURL])
    }

    private func importRecording(_ url: URL) throws {
        guard RecordingImport.supports(url) else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [
                NSLocalizedDescriptionKey: "That file type is not supported yet. Try an audio file or a video containing audio."
            ])
        }
        let fingerprint = try RecordingImport.fingerprint(for: url)
        if let existing = jobs.first(where: { $0.sourceFingerprint == fingerprint }) {
            selection = existing.id
            return
        }

        let jobID = UUID()
        let outputURL = transcriptionRoot
            .appendingPathComponent("work", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
        let now = Date()
        let job = TranscriptionJob(
            id: jobID,
            title: url.deletingPathExtension().lastPathComponent,
            sourcePath: url.standardizedFileURL.path,
            sourceFingerprint: fingerprint,
            createdAt: now,
            updatedAt: now,
            state: .queued,
            transcript: "",
            segments: [],
            detectedLanguage: nil,
            errorMessage: nil,
            outputPath: outputURL.path
        )
        jobs.insert(job, at: 0)
        selection = jobID
        persist()
        start(jobID)
    }

    private func start(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].state = .transcribing
        jobs[index].updatedAt = Date()
        let source = jobs[index].sourceURL
        let output = jobs[index].outputURL
        persist()

        Task {
            do {
                let result = try await WhisperRunner.transcribe(sourceURL: source, outputURL: output)
                guard let finishedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
                jobs[finishedIndex].transcript = result.transcript
                jobs[finishedIndex].segments = result.segments
                jobs[finishedIndex].detectedLanguage = result.language
                jobs[finishedIndex].state = .ready
                jobs[finishedIndex].errorMessage = nil
                jobs[finishedIndex].updatedAt = Date()
                persist()
            } catch {
                guard let failedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
                jobs[failedIndex].state = .failed
                jobs[failedIndex].errorMessage = error.localizedDescription
                jobs[failedIndex].updatedAt = Date()
                persist()
            }
        }
    }

    private var transcriptionRoot: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Noted/transcription", isDirectory: true)
    }

    private var applicationSupportRoot: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Noted Transcriber", isDirectory: true)
    }

    private var jobsURL: URL { applicationSupportRoot.appendingPathComponent("jobs.json") }

    private func load() {
        guard let data = try? Data(contentsOf: jobsURL),
              let saved = try? decoder.decode([TranscriptionJob].self, from: data) else { return }
        jobs = saved.map { job in
            guard job.state == .transcribing else { return job }
            var interrupted = job
            interrupted.state = .failed
            interrupted.errorMessage = "Transcription stopped when the app closed. Choose Retry to continue."
            return interrupted
        }
        selection = jobs.first?.id
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: applicationSupportRoot, withIntermediateDirectories: true)
            let data = try encoder.encode(jobs)
            try data.write(to: jobsURL, options: .atomic)
        } catch {
            importError = "Your transcript is safe, but the job list could not be saved: \(error.localizedDescription)"
        }
    }
}
