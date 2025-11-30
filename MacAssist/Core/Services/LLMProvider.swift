//
//  LLMProvider.swift
//  MacAssist
//
//  Created by Aman Raj on 30/11/25.
//

import Foundation

// MARK: - LLM Provider Protocol

/// Protocol that all LLM providers must conform to
protocol LLMProvider {
    /// Send a message to the LLM and get a response
    func sendMessage(
        messages: [LLMMessage],
        model: String,
        temperature: Double?,
        maxTokens: Int?,
        tools: [ToolSchema]?
    ) async throws -> LLMResponse
}

// MARK: - Unified Message Format

/// Unified message format that works across all providers
struct LLMMessage: Codable, Equatable {
    let role: String
    let content: String?
    let toolCalls: [ToolCall]?
    let toolCallId: String?
    let name: String?
    
    init(role: String, content: String?, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil, name: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
    }
}

// MARK: - Unified Response Format

/// Unified response format from LLM providers
struct LLMResponse: Codable {
    let content: String?
    let toolCalls: [ToolCall]?
    let finishReason: String?
    
    init(content: String?, toolCalls: [ToolCall]? = nil, finishReason: String? = nil) {
        self.content = content
        self.toolCalls = toolCalls
        self.finishReason = finishReason
    }
}

// MARK: - Provider Type Enum

/// Available LLM provider types
enum LLMProviderType: String, Codable, CaseIterable {
    case openai = "OpenAI"
    case gemini = "Gemini"
    case ollama = "Ollama"
    
    var displayName: String {
        return self.rawValue
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .openai, .gemini:
            return true
        case .ollama:
            return false
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-4o-mini"
        case .gemini:
            return "gemini-1.5-flash"
        case .ollama:
            return "llama3.1"
        }
    }
    
    var supportsToolCalling: Bool {
        // All providers support tool calling, but it depends on the model
        return true
    }
}

// MARK: - Provider Configuration

/// Configuration for an LLM provider
struct LLMProviderConfig: Codable {
    var apiKey: String?
    var endpoint: String?
    var model: String
    var temperature: Double?
    var maxTokens: Int?
    
    init(apiKey: String? = nil, endpoint: String? = nil, model: String, temperature: Double? = 0.7, maxTokens: Int? = 150) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
    
    /// Default configuration for a provider type
    static func defaultConfig(for type: LLMProviderType) -> LLMProviderConfig {
        switch type {
        case .openai:
            return LLMProviderConfig(
                apiKey: nil,
                endpoint: nil,
                model: "gpt-4o-mini",
                temperature: 0.7,
                maxTokens: 150
            )
        case .gemini:
            return LLMProviderConfig(
                apiKey: nil,
                endpoint: nil,
                model: "gemini-1.5-flash",
                temperature: 0.7,
                maxTokens: 150
            )
        case .ollama:
            return LLMProviderConfig(
                apiKey: nil,
                endpoint: "http://localhost:11434",
                model: "llama3.1",
                temperature: 0.7,
                maxTokens: 150
            )
        }
    }
}

// MARK: - LLM Provider Errors

enum LLMProviderError: Error, LocalizedError {
    case invalidAPIKey
    case invalidEndpoint
    case invalidModel
    case networkError(Error)
    case decodingError(Error)
    case apiError(String)
    case modelNotFound(String)
    case serverNotReachable
    case toolsNotSupported
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid or missing API key. Please check your settings."
        case .invalidEndpoint:
            return "Invalid endpoint URL."
        case .invalidModel:
            return "Invalid model specified."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .apiError(let message):
            return "API Error: \(message)"
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Please pull the model first."
        case .serverNotReachable:
            return "Server not reachable. Please check if the service is running."
        case .toolsNotSupported:
            return "This model does not support tool calling."
        case .unknownError(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
