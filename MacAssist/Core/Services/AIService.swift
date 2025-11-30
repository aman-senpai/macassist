import Foundation

// MARK: - AIService and Error Handling

enum AIServiceError: Error, LocalizedError {
    case providerError(LLMProviderError)
    case noProviderConfigured
    case invalidConfiguration
    case unknownError(Error)

    var errorDescription: String? {
        switch self {
        case .providerError(let error):
            return error.localizedDescription
        case .noProviderConfigured:
            return "No LLM provider configured. Please configure a provider in Settings."
        case .invalidConfiguration:
            return "Invalid provider configuration. Please check your settings."
        case .unknownError(let error):
            return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}

class AIService {
    private var provider: LLMProvider
    private let providerType: LLMProviderType
    private let config: LLMProviderConfig
    
    // MARK: - OpenAI Chat Completion Models (Nested Types)
    // These types are kept for backward compatibility with existing code
    
    // Enum for chat message roles (system, user, assistant)
    enum ChatRole: String, Codable, Equatable {
        case system
        case user
        case assistant
    }

    // Struct to represent a single message in the chat conversation
    struct ChatMessage: Codable, Equatable {
        let role: ChatRole
        let content: String
    }

    // Initialize the service using current provider settings
    init() throws {
        // Migrate legacy settings if needed
        if !UserDefaults.standard.bool(forKey: "llm_settings_migrated") {
            LLMSettings.migrateFromLegacySettings()
        }
        
        // Load current settings
        let settings = LLMSettings.load()
        self.providerType = settings.selectedProvider
        self.config = settings.config(for: settings.selectedProvider)
        
        // Create provider instance
        do {
            self.provider = try LLMProviderFactory.createProvider(type: providerType, config: config)
        } catch {
            throw AIServiceError.providerError(error as? LLMProviderError ?? .unknownError(error))
        }
    }
    
    // Initialize with specific provider and configuration
    init(providerType: LLMProviderType, config: LLMProviderConfig) throws {
        self.providerType = providerType
        self.config = config
        
        do {
            self.provider = try LLMProviderFactory.createProvider(type: providerType, config: config)
        } catch {
            throw AIServiceError.providerError(error as? LLMProviderError ?? .unknownError(error))
        }
    }

    // Asynchronously fetches a chat completion from the configured LLM provider
    func getChatCompletion(
        messages: [ChatMessage],
        model: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) async throws -> String {
        // Convert ChatMessage to LLMMessage
        let llmMessages = messages.map { message in
            LLMMessage(
                role: message.role.rawValue,
                content: message.content,
                toolCalls: nil,
                toolCallId: nil,
                name: nil
            )
        }
        
        do {
            let response = try await provider.sendMessage(
                messages: llmMessages,
                model: model ?? config.model,
                temperature: temperature ?? config.temperature,
                maxTokens: maxTokens ?? config.maxTokens,
                tools: nil
            )
            
            return response.content ?? ""
        } catch let error as LLMProviderError {
            throw AIServiceError.providerError(error)
        } catch {
            throw AIServiceError.unknownError(error)
        }
    }
    
    // Method to send messages with tool support (for AetherAgent)
    func sendMessageWithTools(
        messages: [LLMMessage],
        model: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        tools: [ToolSchema]?
    ) async throws -> LLMResponse {
        do {
            return try await provider.sendMessage(
                messages: messages,
                model: model ?? config.model,
                temperature: temperature ?? config.temperature,
                maxTokens: maxTokens ?? config.maxTokens,
                tools: tools
            )
        } catch let error as LLMProviderError {
            throw AIServiceError.providerError(error)
        } catch {
            throw AIServiceError.unknownError(error)
        }
    }
    
    // Reload provider if settings changed
    func reloadProvider() throws {
        let settings = LLMSettings.load()
        let newType = settings.selectedProvider
        let newConfig = settings.config(for: newType)
        
        do {
            self.provider = try LLMProviderFactory.createProvider(type: newType, config: newConfig)
        } catch {
            throw AIServiceError.providerError(error as? LLMProviderError ?? .unknownError(error))
        }
    }
    
    // Generates a title and summary for the given conversation messages
    func generateTitleAndSummary(for messages: [ChatMessage]) async throws -> (title: String, summary: String) {
        // Filter out system messages and ensure we have content
        let conversationContent = messages
            .filter { $0.role != .system }
            .map { "\($0.role.rawValue.capitalized): \($0.content)" }
            .joined(separator: "\n")
        
        guard !conversationContent.isEmpty else {
            return ("New Conversation", "No content to summarize.")
        }
        
        let prompt = """
        Analyze the following conversation and provide a short, descriptive title (max 6 words) and a concise summary (max 2 sentences).
        
        Conversation:
        \(conversationContent)
        
        CRITICAL INSTRUCTION: Output ONLY valid JSON. Do not include any markdown formatting (like ```json ... ```). Do not include any other text.
        
        Output format:
        {
            "title": "Your Title Here",
            "summary": "Your summary here."
        }
        """
        
        let systemMessage = ChatMessage(role: .system, content: "You are a helpful assistant that summarizes conversations. You MUST respond with raw JSON only.")
        let userMessage = ChatMessage(role: .user, content: prompt)
        
        // Use a temporary provider instance or the existing one, but ensure we don't use tools
        // We'll use the existing provider but call sendMessage without tools
        
        // Convert to LLMMessage
        let llmMessages = [systemMessage, userMessage].map { message in
            LLMMessage(role: message.role.rawValue, content: message.content, toolCalls: nil, toolCallId: nil, name: nil)
        }
        
        do {
            let response = try await provider.sendMessage(
                messages: llmMessages,
                model: config.model,
                temperature: 0.7,
                maxTokens: 200,
                tools: nil
            )
            
            guard let content = response.content else {
                throw AIServiceError.unknownError(NSError(domain: "AIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response from LLM"]))
            }
            
            // Parse JSON response
            var jsonString = content
            
            // Attempt 1: Extract JSON between braces
            if let firstOpenBrace = content.firstIndex(of: "{"),
               let lastCloseBrace = content.lastIndex(of: "}") {
                let range = firstOpenBrace...lastCloseBrace
                jsonString = String(content[range])
            }
            
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String],
               let title = json["title"],
               let summary = json["summary"] {
                return (title, summary)
            }
            
            // Attempt 2: Regex Fallback
            // If JSON parsing fails, try to extract fields using regex
            print("JSON Parsing failed. Attempting regex extraction for content: \(content)")
            
            let titlePattern = "\"title\"\\s*:\\s*\"(.*?)\""
            let summaryPattern = "\"summary\"\\s*:\\s*\"(.*?)\""
            
            let title = extractWithRegex(pattern: titlePattern, from: content) ?? "Conversation"
            let summary = extractWithRegex(pattern: summaryPattern, from: content) ?? content.prefix(100) + "..."
            
            // If we found at least a title or a summary via regex that looks valid (not the fallback), return it.
            // Note: extractWithRegex returns nil if not found.
            if title != "Conversation" || summary != content.prefix(100) + "..." {
                 // Clean up any escaped quotes if necessary, though .*? usually captures content.
                 return (title, summary)
            }

            return (title, summary)
            
        } catch {
            print("Error generating title and summary: \(error)")
            // Return fallback values on error
            return ("New Conversation", "Summary unavailable.")
        }
    }
    
    private func extractWithRegex(pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if let match = results.first, match.numberOfRanges > 1 {
            return nsString.substring(with: match.range(at: 1))
        }
        return nil
    }
}
