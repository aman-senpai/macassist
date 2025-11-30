//
//  LLMProviderFactory.swift
//  MacAssist
//
//  Created by Aman Raj on 30/11/25.
//

import Foundation

/// Factory to create LLM provider instances
class LLMProviderFactory {
    
    /// Create a provider instance based on type and configuration
    static func createProvider(type: LLMProviderType, config: LLMProviderConfig) throws -> LLMProvider {
        switch type {
        case .openai:
            guard let apiKey = config.apiKey, !apiKey.isEmpty else {
                throw LLMProviderError.invalidAPIKey
            }
            return OpenAIProvider(apiKey: apiKey)
            
        case .gemini:
            guard let apiKey = config.apiKey, !apiKey.isEmpty else {
                throw LLMProviderError.invalidAPIKey
            }
            return GeminiProvider(apiKey: apiKey)
            
        case .ollama:
            let endpoint = config.endpoint ?? "http://localhost:11434"
            return OllamaProvider(endpoint: endpoint)
        }
    }
    
    /// Create a provider using current settings
    static func createProvider() throws -> LLMProvider {
        let settings = LLMSettings.load()
        let config = settings.config(for: settings.selectedProvider)
        return try createProvider(type: settings.selectedProvider, config: config)
    }
    
    /// Get the current provider configuration
    static func getCurrentConfig() -> (type: LLMProviderType, config: LLMProviderConfig) {
        let settings = LLMSettings.load()
        let config = settings.config(for: settings.selectedProvider)
        return (settings.selectedProvider, config)
    }
}
