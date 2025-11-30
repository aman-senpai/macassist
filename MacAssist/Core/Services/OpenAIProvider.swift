//
//  OpenAIProvider.swift
//  MacAssist
//
//  Created by Aman Raj on 30/11/25.
//

import Foundation

/// OpenAI LLM Provider implementation
class OpenAIProvider: LLMProvider {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    func sendMessage(
        messages: [LLMMessage],
        model: String,
        temperature: Double?,
        maxTokens: Int?,
        tools: [ToolSchema]?
    ) async throws -> LLMResponse {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert unified messages to OpenAI format
        let openAIMessages = messages.map { convertToOpenAIMessage($0) }
        
        // Build request payload
        var payload: [String: Any] = [
            "model": model,
            "messages": openAIMessages
        ]
        
        if let temp = temperature {
            payload["temperature"] = temp
        }
        
        if let maxTok = maxTokens {
            payload["max_tokens"] = maxTok
        }
        
        // Add tools if provided
        if let tools = tools, !tools.isEmpty {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let toolsData = try tools.map { try encoder.encode($0) }
            let toolsJSON = try toolsData.map { try JSONSerialization.jsonObject(with: $0) }
            payload["tools"] = toolsJSON
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.networkError(URLError(.badServerResponse))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = try? extractErrorMessage(from: data)
            throw LLMProviderError.apiError(errorMessage ?? "HTTP \(httpResponse.statusCode)")
        }
        
        // Decode response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let openAIResponse = try decoder.decode(OpenAIChatCompletionResponse.self, from: data)
        
        guard let firstChoice = openAIResponse.choices.first else {
            throw LLMProviderError.apiError("No response choices returned")
        }
        
        return convertToLLMResponse(firstChoice.message)
    }
    
    // MARK: - Helper Methods
    
    private func convertToOpenAIMessage(_ message: LLMMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": message.role]
        
        if let content = message.content {
            dict["content"] = content
        }
        
        if let toolCallId = message.toolCallId, let name = message.name {
            dict["tool_call_id"] = toolCallId
            dict["name"] = name
        }
        
        if let toolCalls = message.toolCalls {
            dict["tool_calls"] = toolCalls.map { call -> [String: Any] in
                var callDict: [String: Any] = [
                    "id": call.id,
                    "type": call.type
                ]
                callDict["function"] = [
                    "name": call.function.name,
                    "arguments": call.function.arguments
                ]
                return callDict
            }
        }
        
        return dict
    }
    
    private func convertToLLMResponse(_ message: OpenAIChatMessage) -> LLMResponse {
        return LLMResponse(
            content: message.content,
            toolCalls: message.toolCalls,
            finishReason: nil
        )
    }
    
    private func extractErrorMessage(from data: Data) throws -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }
}

// MARK: - OpenAI-specific Models

private struct OpenAIChatCompletionResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: OpenAIChatMessage
        let finishReason: String?
    }
}

private struct OpenAIChatMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [ToolCall]?
}
