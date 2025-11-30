//
//  ProviderSettingsView.swift
//  MacAssist
//
//  Created by Aman Raj on 30/11/25.
//

import SwiftUI

struct ProviderSettingsView: View {
    @State private var settings = LLMSettings.load()
    @State private var testingConnection = false
    @State private var testResult: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Provider Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("LLM Provider")
                    .font(.headline)
                    .bold()
                
                Picker("Provider", selection: $settings.selectedProvider) {
                    ForEach(LLMProviderType.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.selectedProvider) { _, _ in
                    settings.save()
                }
            }
            
            // Provider Configuration
            let currentProvider = settings.selectedProvider
            let currentConfig = Binding(
                get: { settings.config(for: currentProvider) },
                set: { newConfig in
                    settings.setConfig(newConfig, for: currentProvider)
                    settings.save()
                }
            )
            
            VStack(alignment: .leading, spacing: 12) {
                // API Key (if required)
                if currentProvider.requiresAPIKey {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter your \(currentProvider.displayName) API key", text: Binding(
                            get: { currentConfig.wrappedValue.apiKey ?? "" },
                            set: { newValue in
                                var config = currentConfig.wrappedValue
                                config.apiKey = newValue
                                currentConfig.wrappedValue = config
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                
                // Endpoint (for Ollama)
                if currentProvider == .ollama {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Endpoint URL")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("http://localhost:11434", text: Binding(
                            get: { currentConfig.wrappedValue.endpoint ?? "http://localhost:11434" },
                            set: { newValue in
                                var config = currentConfig.wrappedValue
                                config.endpoint = newValue
                                currentConfig.wrappedValue = config
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                
                // Model Selection
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Model name", text: Binding(
                        get: { currentConfig.wrappedValue.model },
                        set: { newValue in
                            var config = currentConfig.wrappedValue
                            config.model = newValue
                            currentConfig.wrappedValue = config
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    // Model suggestions based on provider
                    Text(modelSuggestions(for: currentProvider))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Temperature
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", currentConfig.wrappedValue.temperature ?? 0.7))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { currentConfig.wrappedValue.temperature ?? 0.7 },
                        set: { newValue in
                            var config = currentConfig.wrappedValue
                            config.temperature = newValue
                            currentConfig.wrappedValue = config
                        }
                    ), in: 0.0...2.0, step: 0.1)
                }
                
                // Max Tokens
                VStack(alignment: .leading, spacing: 6) {
                    Text("Max Tokens")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Max tokens", value: Binding(
                        get: { currentConfig.wrappedValue.maxTokens ?? 150 },
                        set: { newValue in
                            var config = currentConfig.wrappedValue
                            config.maxTokens = newValue
                            currentConfig.wrappedValue = config
                        }
                    ), formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                }
            }
            
            // Test Connection Button
            HStack {
                Button(action: testConnection) {
                    HStack {
                        if testingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "checkmark.circle")
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(testingConnection || (currentProvider.requiresAPIKey && (currentConfig.wrappedValue.apiKey?.isEmpty ?? true)))
                
                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("Success") ? .green : .red)
                }
            }
            
            // Info Box
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.body)
                        .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if currentProvider == .ollama {
                            Text("Ollama runs locally on your machine. Install it with: brew install ollama")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Your API key is stored securely on your Mac and only used for AI requests.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func modelSuggestions(for provider: LLMProviderType) -> String {
        switch provider {
        case .openai:
            return "Examples: gpt-4o, gpt-4o-mini, gpt-4-turbo"
        case .gemini:
            return "Examples: gemini-1.5-pro, gemini-1.5-flash, gemini-1.5-flash-8b"
        case .ollama:
            return "Examples: llama3.1, mistral, codellama (pull models with: ollama pull <model>)"
        }
    }
    
    private func testConnection() {
        testingConnection = true
        testResult = nil
        
        Task {
            do {
                let aiService = try AIService()
                let testMessage = AIService.ChatMessage(role: .user, content: "Hi")
                let _ = try await aiService.getChatCompletion(messages: [testMessage])
                
                await MainActor.run {
                    testResult = "✓ Success!"
                    testingConnection = false
                }
                
                // Clear success message after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    testResult = nil
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ Error: \(error.localizedDescription)"
                    testingConnection = false
                }
            }
        }
    }
}

#Preview {
    ProviderSettingsView()
}
