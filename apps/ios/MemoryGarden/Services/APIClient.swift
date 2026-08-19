import Foundation

enum APIError: LocalizedError {
    case invalidURL, unauthorized, server(Int, String), invalidResponse, decoding(Error), offline(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The Memory Garden server URL is invalid."
        case .unauthorized: "The password was rejected, or the Memory Garden server is not accepting this session."
        case let .server(code, message): "Memory Garden returned \(code): \(message)"
        case .invalidResponse: "The server returned an invalid response."
        case let .decoding(error): "Memory Garden returned data this app could not read: \(error.localizedDescription)"
        case let .offline(error): "The request could not be completed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class APIClient {
    let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var storedPassword: String?

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 10 * 60
        session = URLSession(configuration: configuration)
    }

    func login(password: String) async throws {
        let _: LoginResponse = try await send(path: "/api/auth/login", method: "POST", body: try JSONEncoder().encode(["password": password]), allowAuthRetry: false)
        storedPassword = password
    }

    func logout() async throws {
        defer { storedPassword = nil }
        let _: LoginResponse = try await send(path: "/api/auth/logout", method: "POST")
    }

    func authStatus() async throws -> AuthStatus { try await send(path: "/api/auth/status") }

    func listSources() async throws -> [Source] { let payload: SourceListPayload = try await send(path: "/api/sources?limit=200"); return payload.sources }

    func sourceBundle(id: String) async throws -> SourceBundle { try await send(path: "/api/sources/\(id)") }

    func recordingByClientID(_ clientRecordingID: UUID) async throws -> UploadResponse {
        try await send(path: "/api/recordings/by-client-id/\(clientRecordingID.uuidString)")
    }

    func updateActionItem(sourceID: String, actionItemID: String, status: String, state: ClaimState? = nil) async throws -> MeetingActionItem {
        var payload: [String: String] = ["status": status]
        if let state { payload["state"] = state.rawValue }
        return try await send(path: "/api/recordings/\(sourceID)/action-items/\(actionItemID)", method: "PATCH", body: try JSONEncoder().encode(payload))
    }

    func reprocess(sourceID: String) async throws {
        let _: ReprocessResponse = try await send(path: "/api/sources/\(sourceID)/reprocess", method: "POST")
    }

    func today() async throws -> TodayPayload { try await send(path: "/api/today") }

    func ask(_ question: String) async throws -> AskResponse { try await send(path: "/api/ask", method: "POST", body: try JSONEncoder().encode(["question": question])) }

    func resolveLoop(id: String, status: String) async throws { let _: OpenLoop = try await send(path: "/api/open-loops/\(id)", method: "PATCH", body: try JSONEncoder().encode(["status": status])) }

    func downloadAudio(sourceId: String, allowAuthRetry: Bool = true) async throws -> URL {
        let request = try makeRequest(path: "/files/\(sourceId)")
        do {
            let (temporary, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401, allowAuthRetry, let password = storedPassword {
                    try await login(password: password)
                    return try await downloadAudio(sourceId: sourceId, allowAuthRetry: false)
                }
                throw http.statusCode == 401 ? APIError.unauthorized : APIError.server(http.statusCode, "Audio download failed")
            }
            return temporary
        } catch let error as APIError { throw error } catch { throw APIError.offline(error) }
    }

    func uploadRecording(_ recording: LocalRecording, allowAuthRetry: Bool = true) async throws -> UploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        let temporaryBody = FileManager.default.temporaryDirectory.appendingPathComponent("memory-garden-upload-\(recording.id.uuidString)")
        try writeMultipartBody(for: recording, boundary: boundary, to: temporaryBody)
        defer { try? FileManager.default.removeItem(at: temporaryBody) }
        var request = try makeRequest(path: "/api/capture/voice", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await session.upload(for: request, fromFile: temporaryBody)
            do {
                return try decodeResponse(data: data, response: response)
            } catch APIError.unauthorized where allowAuthRetry && storedPassword != nil {
                try await login(password: storedPassword!)
                return try await uploadRecording(recording, allowAuthRetry: false)
            }
        } catch let error as APIError { throw error } catch { throw APIError.offline(error) }
    }

    private func writeMultipartBody(for recording: LocalRecording, boundary: String, to destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        func write(_ string: String) throws { try output.write(contentsOf: Data(string.utf8)) }
        func field(_ name: String, _ value: String) throws { try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n") }
        try field("title", recording.title)
        try field("durationMs", String(Int(recording.duration * 1000)))
        try field("startedAt", ISO8601DateFormatter().string(from: recording.createdAt))
        try field("endedAt", ISO8601DateFormatter().string(from: recording.createdAt.addingTimeInterval(recording.duration)))
        try field("consentMode", recording.consentMode)
        try field("consentAcknowledged", "true")
        try field("client", "native")
        try field("clientRecordingId", recording.id.uuidString)
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(recording.id.uuidString).m4a\"\r\nContent-Type: audio/mp4\r\n\r\n")
        let input = try FileHandle(forReadingFrom: recording.localFileURL)
        defer { try? input.close() }
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { try output.write(contentsOf: data) }
        try write("\r\n--\(boundary)--\r\n")
    }

    private func makeRequest(path: String, method: String = "GET") throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw APIError.invalidURL }
        var request = URLRequest(url: url); request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<T: Decodable>(path: String, method: String = "GET", body: Data? = nil, allowAuthRetry: Bool = true) async throws -> T {
        var request = try makeRequest(path: path, method: method); request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            let (data, response) = try await session.data(for: request)
            return try decodeResponse(data: data, response: response)
        } catch APIError.unauthorized where allowAuthRetry && storedPassword != nil {
            try await login(password: storedPassword!)
            return try await send(path: path, method: method, body: body, allowAuthRetry: false)
        } catch let error as APIError { throw error } catch { throw APIError.offline(error) }
    }

    private func decodeResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { if http.statusCode == 401 { throw APIError.unauthorized }; let message = String(data: data, encoding: .utf8) ?? "Request failed"; throw APIError.server(http.statusCode, message) }
        do { return try decoder.decode(T.self, from: data) } catch { throw APIError.decoding(error) }
    }
}

struct LoginResponse: Codable { let ok: Bool? }
struct AuthStatus: Codable { let authenticated: Bool }
struct SourceListPayload: Codable { let sources: [Source] }
struct TodayPayload: Codable { let openLoops: [OpenLoop]; let recent: [Source]; let resurfaced: [Memory]; let recordings: [Source]; let now: String }
struct ReprocessResponse: Codable { let ok: Bool; let sourceId: String }
