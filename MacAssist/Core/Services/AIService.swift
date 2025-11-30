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
}
