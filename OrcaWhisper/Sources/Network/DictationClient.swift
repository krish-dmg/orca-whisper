import Foundation
import os

struct DictationResponse: Decodable {
    let text: String
}

enum DictationError: LocalizedError {
    case missingURL
    case missingToken
    case invalidURL
    case invalidResponse(Int)
    case serverError(Int, String)
    case unauthorized
    case payloadTooLarge
    case decodingError(Error)
    case networkError(Error)
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Dictation endpoint URL is not configured."
        case .missingToken:
            return "Dictation bearer token is not configured in Keychain."
        case .invalidURL:
            return "The configured endpoint URL is invalid."
        case .invalidResponse(let code):
            return "Received unexpected status code \(code) from server."
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg)"
        case .unauthorized:
            return "Authentication failed (401 Unauthorized). Verify your bearer token."
        case .payloadTooLarge:
            return "Audio payload exceeded the maximum size limit."
        case .decodingError(let err):
            return "Failed to parse transcription response: \(err.localizedDescription)"
        case .networkError(let err):
            return "Network connection error: \(err.localizedDescription)"
        case .emptyAudio:
            return "Recorded audio file was empty."
        }
    }
}

final class DictationClient {
    private let logger = Logger(subsystem: "com.orca.whisper", category: "Network")

    private func makeSession(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    func transcribe(
        fileURL: URL,
        endpointURLString: String,
        token: String,
        timeout: TimeInterval = 30.0,
        maxRetries: Int = 1,
        retryOn5xxOnly: Bool = true,
        useRawAudio: Bool = true
    ) async throws -> String {
        guard !endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationError.missingURL
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationError.missingToken
        }
        guard let url = URL(string: endpointURLString) else {
            throw DictationError.invalidURL
        }

        let audioData = try Data(contentsOf: fileURL)
        guard !audioData.isEmpty else {
            throw DictationError.emptyAudio
        }

        let session = makeSession(timeout: timeout)
        return try await executeWithRetries(
            session: session,
            audioData: audioData,
            url: url,
            token: token,
            remainingRetries: maxRetries,
            retryOn5xxOnly: retryOn5xxOnly,
            useRawAudio: useRawAudio
        )
    }

    private func executeWithRetries(
        session: URLSession,
        audioData: Data,
        url: URL,
        token: String,
        remainingRetries: Int,
        retryOn5xxOnly: Bool,
        useRawAudio: Bool
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if useRawAudio {
            request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
            request.httpBody = audioData
        } else {
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DictationError.invalidResponse(-1)
            }

            let statusCode = httpResponse.statusCode
            if statusCode == 200 {
                let decoded = try JSONDecoder().decode(DictationResponse.self, from: data)
                return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if statusCode == 401 {
                throw DictationError.unauthorized
            }
            if statusCode == 413 {
                throw DictationError.payloadTooLarge
            }

            if statusCode >= 500 && statusCode < 600 && remainingRetries > 0 {
                logger.warning("Server error \(statusCode). Retrying (\(remainingRetries) retries left)...")
                try await Task.sleep(nanoseconds: 500_000_000)
                return try await executeWithRetries(
                    session: session,
                    audioData: audioData,
                    url: url,
                    token: token,
                    remainingRetries: remainingRetries - 1,
                    retryOn5xxOnly: retryOn5xxOnly,
                    useRawAudio: useRawAudio
                )
            }

            let serverMessage = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw DictationError.serverError(statusCode, serverMessage)

        } catch let error as DictationError {
            throw error
        } catch {
            if remainingRetries > 0 && !retryOn5xxOnly {
                logger.warning("Network connection error: \(error.localizedDescription). Retrying...")
                try await Task.sleep(nanoseconds: 500_000_000)
                return try await executeWithRetries(
                    session: session,
                    audioData: audioData,
                    url: url,
                    token: token,
                    remainingRetries: remainingRetries - 1,
                    retryOn5xxOnly: retryOn5xxOnly,
                    useRawAudio: useRawAudio
                )
            }
            throw DictationError.networkError(error)
        }
    }

    func testConnection(endpointURLString: String, token: String) async throws -> String {
        guard !endpointURLString.isEmpty else {
            throw DictationError.missingURL
        }
        guard !token.isEmpty else {
            throw DictationError.missingToken
        }
        guard let url = URL(string: endpointURLString) else {
            throw DictationError.invalidURL
        }

        var pingURL = url
        if url.path.isEmpty || url.path == "/" {
            pingURL = url.appendingPathComponent("health")
        }

        var request = URLRequest(url: pingURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10.0

        let session = makeSession(timeout: 10.0)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DictationError.invalidResponse(-1)
        }

        if httpResponse.statusCode == 200 {
            return "Connected successfully (HTTP 200 OK)"
        } else if httpResponse.statusCode == 401 {
            throw DictationError.unauthorized
        } else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw DictationError.serverError(httpResponse.statusCode, msg)
        }
    }
}
