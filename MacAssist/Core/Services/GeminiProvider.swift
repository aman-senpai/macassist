//
//  GeminiProvider.swift
//  MacAssist
//
//  Created by Aman Raj on 30/11/25.
//

import Foundation

/// Google Gemini LLM Provider implementation
class GeminiProvider: LLMProvider {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    
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
        // Construct Gemini API endpoint
        let endpoint = "\(baseURL)/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw LLMProviderError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert unified messages to Gemini format
        let geminiContents = convertToGeminiContents(messages)
        
        // Build request payload
        var payload: [String: Any] = [
            "contents": geminiContents
        ]
        
        // Add generation config
        var generationConfig: [String: Any] = [:]
        if let temp = temperature {
            generationConfig["temperature"] = temp
        }
        if let maxTok = maxTokens {
            generationConfig["maxOutputTokens"] = maxTok
        }
        if !generationConfig.isEmpty {
            payload["generationConfig"] = generationConfig
        }
        
        // Add tools if provided (Gemini function calling)
        if let tools = tools, !tools.isEmpty {
            payload["tools"] = [
                ["functionDeclarations": convertToolsToGeminiFunctions(tools)]
            ]
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
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        
        guard let candidate = geminiResponse.candidates.first,
              let part = candidate.content.parts.first else {
            throw LLMProviderError.apiError("No response content returned")
        }
        
        return convertToLLMResponse(part, allParts: candidate.content.parts)
    }
    
    // MARK: - Helper Methods
    
    private func convertToGeminiContents(_ messages: [LLMMessage]) -> [[String: Any]] {
        var contents: [[String: Any]] = []
        
        for message in messages {
            // Map roles for Gemini:
            // "assistant" -> "model"
            // "user" -> "user"
            // "system" -> "user" (Gemini doesn't have system role)
            // "tool" -> "user" (tool responses come from user side in Gemini's view)
            var role = message.role
            if role == "assistant" {
                role = "model"
            } else if role == "system" || role == "tool" {
                // Gemini doesn't have system or tool roles, use user
                role = "user"
            }
            
            var parts: [[String: Any]] = []
            
            // Handle tool responses first (they have special format)
            if let toolCallId = message.toolCallId, let name = message.name, let content = message.content {
                // This is a tool response - use functionResponse format
                parts.append([
                    "functionResponse": [
                        "name": name,
                        "response": ["result": content]
                    ]
                ])
            } else {
                // Regular content message
                if let content = message.content {
                    parts.append(["text": content])
                }
                
                // Handle tool calls (function calls in Gemini)
                if let toolCalls = message.toolCalls {
                    for toolCall in toolCalls {
                        if let argsData = toolCall.function.arguments.data(using: .utf8),
                           let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                            parts.append([
                                "functionCall": [
                                    "name": toolCall.function.name,
                                    "args": argsDict
                                ]
                            ])
                        }
                    }
                }
            }
            
            if !parts.isEmpty {
                contents.append([
                    "role": role,
                    "parts": parts
                ])
            }
        }
        
        return contents
    }
    
    private func convertToolsToGeminiFunctions(_ tools: [ToolSchema]) -> [[String: Any]] {
        return tools.map { tool in
            var function: [String: Any] = [
                "name": tool.function.name,
                "description": tool.function.description
            ]
            
            // Convert parameters
            var parameters: [String: Any] = [
                "type": "OBJECT",
                "properties": [:]
            ]
            
            var properties: [String: Any] = [:]
            for (key, value) in tool.function.parameters.properties {
                properties[key] = [
                    "type": value.type.uppercased(),
                    "description": value.description
                ]
            }
            parameters["properties"] = properties
            
            if !tool.function.parameters.required.isEmpty {
                parameters["required"] = tool.function.parameters.required
            }
            
            function["parameters"] = parameters
            
            return function
        }
    }
    
    private func convertToLLMResponse(_ part: GeminiPart, allParts: [GeminiPart]) -> LLMResponse {
        var toolCalls: [ToolCall]? = nil
        
        // Check for function calls in any part
        var functionCalls: [(name: String, args: String)] = []
        for part in allParts {
            if let functionCall = part.functionCall {
                if let argsData = try? JSONSerialization.data(withJSONObject: functionCall.args),
                   let argsString = String(data: argsData, encoding: .utf8) {
                    functionCalls.append((functionCall.name, argsString))
                }
            }
        }
        
        if !functionCalls.isEmpty {
            toolCalls = functionCalls.enumerated().map { index, fc in
                // OpenAI requires tool call IDs to be max 40 characters
                // Use shorter format: "c_" + first 37 chars of UUID = 39 chars total
                let uuid = UUID().uuidString
                let shortId = "c_\(uuid.prefix(37))"
                
                return ToolCall(
                    id: shortId,
                    function: FunctionCall(name: fc.name, arguments: fc.args)
                )
            }
        }
        
        return LLMResponse(
            content: part.text,
            toolCalls: toolCalls,
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

// MARK: - Gemini-specific Models

private struct GeminiResponse: Codable {
    let candidates: [Candidate]
    
    struct Candidate: Codable {
        let content: Content
    }
    
    struct Content: Codable {
        let parts: [GeminiPart]
        let role: String?
    }
}

private struct GeminiPart: Codable {
    let text: String?
    let functionCall: FunctionCallData?
    
    struct FunctionCallData: Codable {
        let name: String
        let args: [String: Any]
        
        enum CodingKeys: String, CodingKey {
            case name, args
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            args = try container.decode([String: Any].self, forKey: .args)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(args, forKey: .args)
        }
    }
}

// Extension to decode [String: Any]
extension KeyedDecodingContainer {
    func decode(_ type: [String: Any].Type, forKey key: Key) throws -> [String: Any] {
        let container = try self.nestedContainer(keyedBy: JSONCodingKeys.self, forKey: key)
        return try container.decode(type)
    }
}

extension KeyedEncodingContainer {
    mutating func encode(_ value: [String: Any], forKey key: Key) throws {
        var container = self.nestedContainer(keyedBy: JSONCodingKeys.self, forKey: key)
        try container.encode(value)
    }
}

private struct JSONCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.init(stringValue: "\(intValue)")
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where K == JSONCodingKeys {
    func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        var dictionary = [String: Any]()
        
        for key in allKeys {
            if let boolValue = try? decode(Bool.self, forKey: key) {
                dictionary[key.stringValue] = boolValue
            } else if let intValue = try? decode(Int.self, forKey: key) {
                dictionary[key.stringValue] = intValue
            } else if let doubleValue = try? decode(Double.self, forKey: key) {
                dictionary[key.stringValue] = doubleValue
            } else if let stringValue = try? decode(String.self, forKey: key) {
                dictionary[key.stringValue] = stringValue
            } else if let nestedDictionary = try? decode([String: Any].self, forKey: key) {
                dictionary[key.stringValue] = nestedDictionary
            } else if let nestedArray = try? decode([Any].self, forKey: key) {
                dictionary[key.stringValue] = nestedArray
            }
        }
        
        return dictionary
    }
    
    func decode(_ type: [Any].Type, forKey key: K) throws -> [Any] {
        var container = try self.nestedUnkeyedContainer(forKey: key)
        return try container.decode(type)
    }
}

extension KeyedEncodingContainer where K == JSONCodingKeys {
    mutating func encode(_ value: [String: Any]) throws {
        for (key, val) in value {
            let key = JSONCodingKeys(stringValue: key)!
            switch val {
            case let v as Bool:
                try encode(v, forKey: key)
            case let v as Int:
                try encode(v, forKey: key)
            case let v as Double:
                try encode(v, forKey: key)
            case let v as String:
                try encode(v, forKey: key)
            case let v as [String: Any]:
                try encode(v, forKey: key)
            case let v as [Any]:
                try encode(v, forKey: key)
            default:
                break
            }
        }
    }
    
    mutating func encode(_ value: [Any], forKey key: K) throws {
        var container = self.nestedUnkeyedContainer(forKey: key)
        try container.encode(value)
    }
}

extension UnkeyedDecodingContainer {
    mutating func decode(_ type: [Any].Type) throws -> [Any] {
        var array: [Any] = []
        
        while !isAtEnd {
            if let value = try? decode(Bool.self) {
                array.append(value)
            } else if let value = try? decode(Int.self) {
                array.append(value)
            } else if let value = try? decode(Double.self) {
                array.append(value)
            } else if let value = try? decode(String.self) {
                array.append(value)
            } else if let nestedDictionary = try? decode([String: Any].self) {
                array.append(nestedDictionary)
            } else if let nestedArray = try? decode([Any].self) {
                array.append(nestedArray)
            }
        }
        
        return array
    }
    
    mutating func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        let container = try self.nestedContainer(keyedBy: JSONCodingKeys.self)
        return try container.decode(type)
    }
}

extension UnkeyedEncodingContainer {
    mutating func encode(_ value: [Any]) throws {
        for val in value {
            switch val {
            case let v as Bool:
                try encode(v)
            case let v as Int:
                try encode(v)
            case let v as Double:
                try encode(v)
            case let v as String:
                try encode(v)
            case let v as [String: Any]:
                // Need to create a nested container for dictionaries
                var nestedContainer = self.nestedContainer(keyedBy: JSONCodingKeys.self)
                try nestedContainer.encode(v)
            case let v as [Any]:
                var nestedContainer = self.nestedUnkeyedContainer()
                try nestedContainer.encode(v)
            default:
                break
            }
        }
    }
}
