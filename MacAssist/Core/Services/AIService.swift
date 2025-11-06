import Foundation

// MARK: - AIService and Error Handling

enum AIServiceError: Error, LocalizedError {
    case invalidAPIKey
    case invalidURL
    case noData
    case decodingError(Error)
    case apiError(String)
    case unknownError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "OpenAI API Key not found. Please set the OPENAI_API_KEY environment variable in your scheme."
        case .invalidURL: return "Invalid OpenAI API URL."
        case .noData: return "No data received from OpenAI API."
        case .decodingError(let error): return "Failed to decode API response: \(error.localizedDescription)"
        case .apiError(let message): return "OpenAI API Error: \(message)"
        case .unknownError(let error): return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}

class AIService {
    private let apiKey: String
    private let session: URLSession

    // MARK: - OpenAI Chat Completion Models (Nested Types)
    // These types are nested within AIService to prevent global ambiguity
    // and are accessed as AIService.ChatRole and AIService.ChatMessage.

    // Enum for chat message roles (system, user, assistant)
    enum ChatRole: String, Codable, Equatable { // Added Equatable for consistency
        case system
        case user
        case assistant
    }

    // Struct to represent a single message in the chat conversation
    struct ChatMessage: Codable, Equatable {
        let role: ChatRole
        let content: String
    }

    // Struct for the request payload sent to the OpenAI API
    struct ChatCompletionRequest: Codable {
        let model: String
        let messages: [ChatMessage] // References AIService.ChatMessage
        let temperature: Double? // Optional: controls randomness (creativity)
        let max_tokens: Int?    // Optional: sets the maximum length of the response
        let stream: Bool?       // Optional: for streaming partial responses (not used in this non-streaming example)

        init(model: String, messages: [ChatMessage], temperature: Double? = nil, max_tokens: Int? = nil, stream: Bool? = false) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
            self.max_tokens = max_tokens
            self.stream = stream
        }
    }

    // MARK: - Response Models for OpenAI Chat Completions

    // Top-level struct for the OpenAI API response
    struct ChatCompletionResponse: Codable {
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [Choice]
        let usage: Usage? // Optional: includes token usage information
    }

    // Struct for individual choices within the response (usually just one for non-streaming)
    struct Choice: Codable {
        let index: Int
        let message: ChatMessage // References AIService.ChatMessage
        let finish_reason: String
    }

    // Struct for token usage details
    struct Usage: Codable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }

    // Initialize the service, retrieving the API key from environment variables
    init() throws {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            throw AIServiceError.invalidAPIKey
        }
        self.apiKey = key
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30 // Set a timeout for network requests
        self.session = URLSession(configuration: config)
    }

    // Asynchronously fetches a chat completion from the OpenAI API
    func getChatCompletion(messages: [ChatMessage], model: String = "gpt-4o-mini", temperature: Double? = 0.7, maxTokens: Int? = 150) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let chatRequest = ChatCompletionRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: maxTokens,
            stream: false // We are not using streaming for this example
        )

        do {
            let encoder = JSONEncoder()
            // Configure encoder to convert Swift `camelCase` to JSON `snake_case`
            encoder.keyEncodingStrategy = .convertToSnakeCase
        } catch {
            throw AIServiceError.decodingError(error)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.noData // This should ideally be a more specific error for URLSession
        }

        // Check for successful HTTP status codes (2xx range)
        guard (200...299).contains(httpResponse.statusCode) else {
            // Attempt to decode a more detailed error message from the API response
            if let apiError = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let errorDict = apiError["error"] as? [String: Any],
               let errorMessage = errorDict["message"] as? String {
                throw AIServiceError.apiError(errorMessage)
            } else {
                throw AIServiceError.apiError("HTTP \(httpResponse.statusCode): Unknown API error.")
            }
        }

        do {
            let decoder = JSONDecoder()
            // Configure decoder to convert JSON `snake_case` to Swift `camelCase`
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)

            guard let firstChoice = completionResponse.choices.first else {
                throw AIServiceError.noData // No AI response choice found
            }
            return firstChoice.message.content
        } catch {
            throw AIServiceError.decodingError(error)
        }
    }
}
