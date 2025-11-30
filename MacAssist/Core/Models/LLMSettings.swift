//
//  LLMSettings.swift
//  MacAssist
//
//  Created by Aman Raj on 30/11/25.
//

import Foundation

/// Settings for LLM providers
struct LLMSettings: Codable {
    var selectedProvider: LLMProviderType
    var providers: [String: LLMProviderConfig] // Using String key instead of enum for Codable compatibility
    
    init(selectedProvider: LLMProviderType, providers: [LLMProviderType: LLMProviderConfig]) {
        self.selectedProvider = selectedProvider
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.rawValue, $1) })
    }
    
    /// Get configuration for a specific provider
    func config(for type: LLMProviderType) -> LLMProviderConfig {
        return providers[type.rawValue] ?? LLMProviderConfig.defaultConfig(for: type)
    }
    
    /// Set configuration for a specific provider
    mutating func setConfig(_ config: LLMProviderConfig, for type: LLMProviderType) {
        providers[type.rawValue] = config
    }
    
    /// Default settings with all providers configured
    static var `default`: LLMSettings {
        LLMSettings(
            selectedProvider: .openai,
            providers: [
                .openai: LLMProviderConfig.defaultConfig(for: .openai),
                .gemini: LLMProviderConfig.defaultConfig(for: .gemini),
                .ollama: LLMProviderConfig.defaultConfig(for: .ollama)
            ]
        )
    }
    
    // MARK: - UserDefaults Integration
    
    private static let settingsKey = "llm_settings"
    
    /// Load settings from UserDefaults
    static func load() -> LLMSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(LLMSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    /// Save settings to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: LLMSettings.settingsKey)
        }
    }
    
    /// Migrate from old OpenAI-only settings
    static func migrateFromLegacySettings() {
        // Check if we have an old OpenAI API key
        if let oldAPIKey = UserDefaults.standard.string(forKey: "openAIApiKey"),
           !oldAPIKey.isEmpty {
            var settings = LLMSettings.load()
            
            // Update OpenAI config with the old API key
            var openAIConfig = settings.config(for: .openai)
            openAIConfig.apiKey = oldAPIKey
            settings.setConfig(openAIConfig, for: .openai)
            
            // Save migrated settings
            settings.save()
            
            // Mark migration as complete (don't remove the old key for backward compatibility)
            UserDefaults.standard.set(true, forKey: "llm_settings_migrated")
        }
    }
}
