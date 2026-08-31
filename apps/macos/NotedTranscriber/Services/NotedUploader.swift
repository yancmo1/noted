import Foundation
import UniformTypeIdentifiers

enum NotedUploadError: LocalizedError {
    case invalidBaseURL
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Enter an HTTPS Noted address, or a local address such as http://127.0.0.1:3333."
        case .requestFailed(let message):
            message
        }
    }
}

struct NotedUploadResult: Sendable {
    let sourceID: String
    let deduplicated: Bool
}

enum NotedProcessingState: String, Codable, Sendable {
    case pending
    case processing
    case ready
    case partial
    case failed
}

enum NotedUploader {
    static let defaultBaseURL = "https://noted.shepswork.com"
    static let localBaseURL = "http://127.0.0.1:3333"

    static func isAllowedBaseURL(_ root: URL) -> Bool {
        guard let scheme = root.scheme?.lowercased(), let host = root.host?.lowercased() else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    private struct LoginBody: Encodable { let password: String }
    private struct SourceResponse: Decodable { let id: String }
    private struct UploadResponse: Decodable {
        let source: SourceResponse?
        let deduplicated: Bool?
    }
    private struct SourceStatusResponse: Decodable {
        let processingStatus: NotedProcessingState
    }
    private struct UploadBody: Encodable {
        let title: String
        let clientRecordingId: String
        let startedAt: String
        let endedAt: String
        let durationMs: Int
        let mimeType: String
        let consentMode: String
        let consentAcknowledged: Bool
        let transcriptText: String
        let segments: [Segment]

        struct Segment: Encodable {
            let startMs: Int
            let endMs: Int
            let text: String
        }
    }

    static func send(job: TranscriptionJob, baseURL: String, password: String) async throws -> NotedUploadResult {
        guard let root = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              isAllowedBaseURL(root) else { throw NotedUploadError.invalidBaseURL }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var loginRequest = URLRequest(url: root.appendingPathComponent("api/auth/login"))
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loginRequest.httpBody = try JSONEncoder().encode(LoginBody(password: password))
        let (loginData, loginResponse) = try await session.data(for: loginRequest)
        try validate(loginResponse, data: loginData, fallback: "Noted sign-in failed.")

        let segments = job.segments.map {
            UploadBody.Segment(startMs: $0.startMilliseconds, endMs: $0.endMilliseconds, text: $0.text)
        }
        let startedAt = ISO8601DateFormatter().string(from: job.createdAt)
        let endedAt = ISO8601DateFormatter().string(from: job.updatedAt)
        let mimeType = UTType(filenameExtension: job.sourceURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let payload = UploadBody(
            title: job.title,
            clientRecordingId: job.id.uuidString,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMs: job.segments.map(\.endMilliseconds).max() ?? 0,
            mimeType: mimeType,
            consentMode: "meeting",
            consentAcknowledged: true,
            transcriptText: job.transcript,
            segments: segments
        )

        var uploadRequest = URLRequest(url: root.appendingPathComponent("api/recordings/local-transcript"))
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = try JSONEncoder().encode(payload)
        let (uploadData, uploadResponse) = try await session.data(for: uploadRequest)
        try validate(uploadResponse, data: uploadData, fallback: "Noted could not save the transcript.")
        let result = try JSONDecoder().decode(UploadResponse.self, from: uploadData)
        guard let sourceID = result.source?.id else {
            throw NotedUploadError.requestFailed("Noted accepted the request but did not return a recording ID.")
        }
        return NotedUploadResult(sourceID: sourceID, deduplicated: result.deduplicated ?? false)
    }

    static func processingState(sourceID: String, baseURL: String, password: String) async throws -> NotedProcessingState {
        guard let root = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              isAllowedBaseURL(root) else { throw NotedUploadError.invalidBaseURL }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var loginRequest = URLRequest(url: root.appendingPathComponent("api/auth/login"))
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loginRequest.httpBody = try JSONEncoder().encode(LoginBody(password: password))
        let (loginData, loginResponse) = try await session.data(for: loginRequest)
        try validate(loginResponse, data: loginData, fallback: "Noted sign-in failed.")

        let statusURL = root.appendingPathComponent("api/sources").appendingPathComponent(sourceID)
        var statusRequest = URLRequest(url: statusURL)
        statusRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (statusData, statusResponse) = try await session.data(for: statusRequest)
        try validate(statusResponse, data: statusData, fallback: "Noted could not read processing status.")
        return try JSONDecoder().decode(SourceStatusResponse.self, from: statusData).processingStatus
    }

    private static func validate(_ response: URLResponse, data: Data, fallback: String) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let message = body?["error"] as? String
            throw NotedUploadError.requestFailed(message ?? fallback)
        }
    }
}
