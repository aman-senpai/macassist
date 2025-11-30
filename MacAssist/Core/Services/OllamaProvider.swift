//
//  OllamaProvider.swift
//  MacAssist
//
//  Created by Aman Raj on 30/11/25.
//

import Foundation

/// Ollama LLM Provider implementation (local or remote)
class OllamaProvider: LLMProvider {
    private let endpoint: String
    private let session: URLSession
    
    init(endpoint: String) {
        self.endpoint = endpoint
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60 // Longer timeout for local models
        self.session = URLSession(configuration: config)
    }
    
    func sendMessage(
        messages: [LLMMessage],
        model: String,
        temperature: Double?,
        maxTokens: Int?,
        tools: [ToolSchema]?
    ) async throws -> LLMResponse {
        // Construct Ollama chat endpoint
        let chatEndpoint = endpoint.hasSuffix("/") ? "\(endpoint)api/chat" : "\(endpoint)/api/chat"
        guard let url = URL(string: chatEndpoint) else {
            throw LLMProviderError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert unified messages to Ollama format
        let ollamaMessages = messages.map { convertToOllamaMessage($0) }
        
        // Build request payload
        var payload: [String: Any] = [
            "model": model,
            "messages": ollamaMessages,
            "stream": false
        ]
        
        // Add options
        var options: [String: Any] = [:]
        if let temp = temperature {
            options["temperature"] = temp
        }
        if let maxTok = maxTokens {
            options["num_predict"] = maxTok
        }
        if !options.isEmpty {
            payload["options"] = options
        }
        
        // Add tools if provided (Ollama tool calling support)
        if let tools = tools, !tools.isEmpty {
            payload["tools"] = convertToolsToOllamaFormat(tools)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMProviderError.networkError(URLError(.badServerResponse))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = try? extractErrorMessage(from: data)
                
                // Check for specific Ollama errors
                if let error = errorMessage?.lowercased() {
                    if error.contains("not found") || error.contains("model") {
                        throw LLMProviderError.modelNotFound(model)
                    }
                    if error.contains("does not support tools") || error.contains("tool") {
                        throw LLMProviderError.toolsNotSupported
                    }
                }
                
                throw LLMProviderError.apiError(errorMessage ?? "HTTP \(httpResponse.statusCode)")
            }
            
            // Debug: Print raw response for troubleshooting
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[OllamaProvider] Raw response: \(jsonString)")
            }
            #endif
            
            // Decode response
            do {
                let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
                return convertToLLMResponse(ollamaResponse.message)
            } catch {
                print("[OllamaProvider] Decoding error: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[OllamaProvider] Failed to decode response: \(jsonString)")
                }
                throw LLMProviderError.decodingError(error)
            }
        } catch let error as URLError {
            // Handle connection errors (server not running)
            if error.code == .cannotConnectToHost || error.code == .cannotFindHost {
                throw LLMProviderError.serverNotReachable
            }
            throw LLMProviderError.networkError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func convertToOllamaMessage(_ message: LLMMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": message.role]
        
        if let content = message.content {
            dict["content"] = content
        }
        
        // Ollama tool calls - need to parse arguments string to object
        if let toolCalls = message.toolCalls {
            dict["tool_calls"] = toolCalls.compactMap { call -> [String: Any]? in
                // Parse arguments string into dictionary
                guard let argsData = call.function.arguments.data(using: .utf8),
                      let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
                    print("[OllamaProvider] Warning: Failed to parse tool call arguments: \(call.function.arguments)")
                    return nil
                }
                
                return [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.function.name,
                        "arguments": argsDict  // Send as object, not string
                    ]
                ]
            }
        }
        
        return dict
    }
    
    private func convertToolsToOllamaFormat(_ tools: [ToolSchema]) -> [[String: Any]] {
        return tools.map { tool in
            return [
                "type": "function",
                "function": [
                    "name": tool.function.name,
                    "description": tool.function.description,
                    "parameters": [
                        "type": "object",
                        "properties": tool.function.parameters.properties.mapValues { prop in
                            [
                                "type": prop.type,
                                "description": prop.description
                            ]
                        },
                        "required": tool.function.parameters.required
                    ]
                ]
            ]
        }
    }
    
    private func convertToLLMResponse(_ message: OllamaMessage) -> LLMResponse {
        // Convert Ollama-specific tool calls to standard format
        let standardToolCalls = message.toolCalls?.map { $0.toToolCall() }
        
        return LLMResponse(
            content: message.content,
            toolCalls: standardToolCalls,
            finishReason: nil
        )
    }
    
    private func extractErrorMessage(from data: Data) throws -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            return error
        }
        return nil
    }
}

// MARK: - Ollama-specific Models

private struct OllamaResponse: Codable {
    let message: OllamaMessage
    let done: Bool
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [OllamaToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

// Ollama-specific ToolCall that can decode arguments as object
private struct OllamaToolCall: Codable {
    let id: String
    let function: OllamaFunctionCall
    
    // Convert to standard ToolCall
    func toToolCall() -> ToolCall {
        ToolCall(
            id: id,
            function: FunctionCall(
                name: function.name,
                arguments: function.argumentsString
            )
        )
    }
}

private struct OllamaFunctionCall: Codable {
    let name: String
    private let argumentsDict: [String: AnyCodable]
    
    // Convert arguments dict to JSON string
    var argumentsString: String {
        let dict = argumentsDict.mapValues { $0.value }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
    
    enum CodingKeys: String, CodingKey {
        case name, arguments
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        argumentsDict = (try? container.decode([String: AnyCodable].self, forKey: .arguments)) ?? [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(argumentsDict, forKey: .arguments)
    }
}

// Helper to decode Any values
private struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
