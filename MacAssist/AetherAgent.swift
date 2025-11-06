//
//  AetherAgent.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import Foundation
import SwiftUI
import Combine
import AppKit // Required for NSWorkspace (opening apps) and NSAppleScript (system actions)

// MARK: - 1. Data Models for OpenAI API

struct ChatMessage: Identifiable, Codable {
    var id: UUID?
    let role: String // "user", "assistant", "system", "tool"
    var content: String?
    var toolCalls: [ToolCall]?
    var toolCallId: String? // For role: "tool"
    var name: String? // For role: "tool"
    var refusal: String?
    var annotations: [Annotation]?
    var timestamp: Date

    var safeId: UUID { id ?? UUID() }

    // Custom initializer to provide a default timestamp for internal message creation
    init(id: UUID? = nil, role: String, content: String?, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil, name: String? = nil, refusal: String? = nil, annotations: [Annotation]? = nil, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
        self.refusal = refusal
        self.annotations = annotations
        self.timestamp = timestamp
    }

    // MARK: - Codable Implementation
    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case toolCalls
        case toolCallId
        case name
        case refusal
        case annotations
        case timestamp
    }

    // Custom Decodable initializer for parsing JSON (e.g., from OpenAI API)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.role = try container.decode(String.self, forKey: .role)
        self.content = try container.decodeIfPresent(String.self, forKey: .content)
        self.toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        self.toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.refusal = try container.decodeIfPresent(String.self, forKey: .refusal)
        self.annotations = try container.decodeIfPresent([Annotation].self, forKey: .annotations)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }

    // Custom Encodable implementation
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(refusal, forKey: .refusal)
        try container.encodeIfPresent(annotations, forKey: .annotations)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

struct Annotation: Codable {}

struct ToolCall: Codable {
    let id: String
    let function: FunctionCall
    let type: String = "function"
}

struct FunctionCall: Codable {
    let name: String
    let arguments: String // JSON string
}

struct ToolSchema: Codable {
    let type: String = "function"
    let function: FunctionDetails
}

struct FunctionDetails: Codable {
    let name: String
    let description: String
    let parameters: ParameterSchema
}

struct ParameterSchema: Codable {
    let type: String = "object"
    let properties: [String: PropertyDetails]
    let required: [String]
}

struct PropertyDetails: Codable {
    let type: String
    let description: String
}

// MARK: - Assistant Status Definition (NEW)
enum AssistantStatus: Equatable {
    case idle
    case thinking
    case callingTool(String) // AI is about to call or has called a tool
    case responding // AI is generating a textual response
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking..."
        case .callingTool(let toolName): return "Using Tool: \(toolName)"
        case .responding: return "Responding..."
        case .error(let message): return "Error: \(message)"
        }
    }
}

// MARK: - 3. Aether Agent Class (AI and Tool Management)

@MainActor
final class AetherAgent: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing: Bool = false
    @Published var spokenResponse: String?
    @Published var currentAgentStatus: AssistantStatus = .idle // NEW: Agent's internal status
    
    // NEW: Instance of the modularized SystemTools
    private let systemTools = SystemTools()
    
    // System Prompt for Aether
    private let systemPrompt = ChatMessage(id: UUID(), role: "system", content: """
        You are 'Aether', an expert conversational AI assistant for macOS.
        Your primary goal is to be helpful, concise, and conversational.
        You have the capability to interact directly with the user's operating system using the tools provided.
        You can also manipulate text in the foreground application, such as typing, pasting, selecting, or summarizing content.

        RULES:
        1. When a user asks you to perform an action (e.g., "Open Safari," "Set volume to 50"), ALWAYS use the appropriate tool function.
        2. When a user asks to write something (e.g., "write an email saying hello"), use the 'typeText' tool to type it out.
        3. When a user asks a general question (e.g., "Who won the last F1 race?"), use the 'googleSearch' tool.
        4. When a user asks for the current date or time, use the 'getCurrentDateTime' tool.
        5. When a user asks to watch a video or search for a video, use the 'searchYouTube' tool.
        6. After calling a tool, report the result of the action (success or error) back to the user naturally.
        7. Keep your responses short and effective for a menu bar interface.
        """)

    private let modelName = "gpt-4o-mini"
    private var history: [ChatMessage] = []
    
    // MARK: - Initialization
    
    init() {
        // On first launch, check and request necessary system permissions.
        AetherAgent.checkAndRequestPermissions()
        
        history.append(systemPrompt)
        messages.append(ChatMessage(id: UUID(), role: "assistant", content: "Hello! I'm Aether, your macOS assistant. Enter your OpenAI API key in the Settings tab to get started."))
        currentAgentStatus = .idle // Set initial status
    }
    
    // MARK: - Permissions Management
    
    private static func checkAndRequestPermissions() {
        // --- Accessibility Permission ---
        // This is required for controlling other applications via AppleScript.
        // The user will be prompted for permission if the app is not trusted.
        // This prompt only appears once. If they deny it, they must manually
        // grant permission in System Settings > Privacy & Security > Accessibility.
        let accessibilityOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if AXIsProcessTrustedWithOptions(accessibilityOptions) {
            print("[AetherAgent] Accessibility access has been granted.")
        } else {
            print("[AetherAgent] Accessibility access not granted. The system should prompt the user.")
        }
        
        // --- Screen Recording Permission ---
        // Permission for screen recording is required for taking screenshots.
        // The `screencapture` command-line tool will trigger the system prompt
        // automatically the first time the user tries to take a screenshot.
        // No special code is needed here to trigger it, but you MUST provide
        // the `NSScreenCaptureUsageDescription` key in Info.plist.
    }
    
    // MARK: - Tool Schemas
    
    private var toolSchemas: [ToolSchema] {
        return [
            // --- NEW SYSTEM INFORMATION TOOL ---
            ToolSchema(function: FunctionDetails(
                name: "getCurrentDateTime",
                description: "Retrieves the current system date, time, and timezone. Use this when the user asks 'what time is it?' or 'what is the date?'",
                parameters: ParameterSchema(properties: [:], required: []))),

            // --- SEARCH/WEB TOOLS ---
            ToolSchema(function: FunctionDetails(
                name: "googleSearch",
                description: "Opens the default web browser and performs a general search query using Google. Use this for general knowledge, news, or fact-finding queries.",
                parameters: ParameterSchema(
                    properties: ["query": PropertyDetails(type: "string", description: "The search phrase to look for on Google (e.g., 'current weather in London').")],
                    required: ["query"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "openWebsite",
                description: "Opens a specific website URL in the default web browser (e.g., 'open www.apple.com'). Use this when the user specifies a full or partial URL to visit.",
                parameters: ParameterSchema(
                    properties: ["url": PropertyDetails(type: "string", description: "The full or partial URL of the website to open (e.g., 'https://www.google.com', 'https://www.apple.in').")],
                    required: ["url"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "searchYouTube",
                description: "Opens the default web browser and searches YouTube for a specified video topic. Only use this for video-related queries.",
                parameters: ParameterSchema(
                    properties: ["query": PropertyDetails(type: "string", description: "The video topic or search phrase to look for on YouTube (e.g., 'latest AI news video').")],
                    required: ["query"]
                ))),
            
            // --- APPLICATION CONTROL TOOLS ---
            ToolSchema(function: FunctionDetails(
                name: "openApplication",
                description: "Opens a specified macOS application (e.g., 'open Mail', 'launch Terminal'). Takes the exact application name as input.",
                parameters: ParameterSchema(
                    properties: ["name": PropertyDetails(type: "string", description: "The exact name of the macOS application to open, like 'Safari' or 'Finder'.")],
                    required: ["name"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "closeFrontmostApplication",
                description: "Closes or quits the application that is currently active on the user's screen.",
                parameters: ParameterSchema(properties: [:], required: []))),
            ToolSchema(function: FunctionDetails(
                name: "minimizeFrontmostWindow",
                description: "Minimizes the window of the application that is currently active on the screen.",
                parameters: ParameterSchema(properties: [:], required: []))),

            // --- WRITING & TEXT MANIPULATION TOOLS ---
            ToolSchema(function: FunctionDetails(
                name: "typeText",
                description: "Types the given text at the current cursor location by simulating keystrokes. Use this for writing messages, emails, or any text directly into an active text field.",
                parameters: ParameterSchema(
                    properties: ["content": PropertyDetails(type: "string", description: "The text to be typed out.")],
                    required: ["content"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "pasteText",
                description: "Pastes the given text at the current cursor location from the clipboard. This is faster than typing but will overwrite the user's current clipboard.",
                parameters: ParameterSchema(
                    properties: ["content": PropertyDetails(type: "string", description: "The text content to be pasted.")],
                    required: ["content"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "replaceAllText",
                description: "Replaces all selectable text in the frontmost application with the provided new content by selecting all and then pasting.",
                parameters: ParameterSchema(
                    properties: ["newContent": PropertyDetails(type: "string", description: "The new text that will replace everything in the active field.")],
                    required: ["newContent"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "getTextFromFrontmostApplication",
                description: "Retrieves all selectable text from the active document or text field of the frontmost application. This is useful before performing an action like summarization.",
                parameters: ParameterSchema(properties: [:], required: []))),
            ToolSchema(function: FunctionDetails(
                name: "summarizeText",
                description: "Gets all text from the frontmost application, summarizes it, and replaces the original text with the summary. Use this when the user asks to summarize the current content.",
                parameters: ParameterSchema(properties: [:], required: []))),
            ToolSchema(function: FunctionDetails(
                name: "selectAllText",
                description: "Selects all text in the active text field or document of the frontmost application (simulates Command-A).",
                parameters: ParameterSchema(properties: [:], required: []))),
            ToolSchema(function: FunctionDetails(
                name: "copySelection",
                description: "Copies the currently selected text to the clipboard (simulates Command-C).",
                parameters: ParameterSchema(properties: [:], required: []))),
            
            // --- SYSTEM UTILITY TOOLS ---
            ToolSchema(function: FunctionDetails(
                name: "runShellCommand",
                description: "Executes an arbitrary command in the macOS shell (e.g., 'ls -l', 'date'). Use this for advanced system tasks not covered by other specific tools.",
                parameters: ParameterSchema(
                    properties: ["command": PropertyDetails(type: "string", description: "The exact shell command string to execute.")],
                    required: ["command"]
                ))),
            
            ToolSchema(function: FunctionDetails(
                name: "takeScreenshot",
                description: "Captures the entire screen and copies the image to the clipboard, allowing it to be pasted anywhere.",
                parameters: ParameterSchema(properties: [:], required: []))),
            
            ToolSchema(function: FunctionDetails(
                name: "setSystemVolume",
                description: "Sets the system output volume level to a specific percentage (0-100).",
                parameters: ParameterSchema(
                    properties: ["level": PropertyDetails(type: "integer", description: "The volume percentage to set, between 0 and 100.")],
                    required: ["level"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "createFileWithContent",
                description: "Creates a new text file at a specified path (e.g., '~/Documents/report.txt') with the provided content.",
                parameters: ParameterSchema(
                    properties: [
                        "path": PropertyDetails(type: "string", description: "The path to the file, relative to the user's home directory (e.g., '~/Desktop/notes.md')."),
                        "content": PropertyDetails(type: "string", description: "The text content to be written into the new file.")
                    ],
                    required: ["path", "content"]
                )))
        ]
    }
    
    // MARK: - Public API
    
    func sendMessage(text: String) {
        guard !isProcessing else { return } // If already processing, ignore new message

        let userMessage = ChatMessage(id: UUID(), role: "user", content: text)
        messages.append(userMessage)
        history.append(userMessage)
        
        Task {
            isProcessing = true
            currentAgentStatus = .thinking // Agent starts thinking after receiving a message
            await processResponse()
            isProcessing = false
            // After processing, if no error, the agent should return to idle
            // unless speech service is still active. This is handled by VoiceAssistantController.
            if case .thinking = currentAgentStatus { // Only if status wasn't changed to error or tool call
                currentAgentStatus = .idle
            }
        }
    }
    
    // MARK: - Core Processing Loop
    
    private func processResponse() async {
        let apiKey = UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
        guard !apiKey.isEmpty else {
            addAssistantMessage(content: "Please enter a valid OpenAI API Key in the Settings tab.")
            currentAgentStatus = .error("API Key Missing") // Update status
            return
        }

        do {
            var conversationHistory = history
            
            for _ in 0..<5 { // Limit the number of turns to prevent infinite loops (AI response -> tool call -> tool result -> AI response etc.)
                
                currentAgentStatus = .responding // AI is generating a text response from OpenAI
                let (responseMessage, completionError) = try await callOpenAI(with: conversationHistory)
                
                if let error = completionError {
                    addAssistantMessage(content: "API Error: \(error.localizedDescription)")
                    currentAgentStatus = .error("API Error") // Update status
                    return
                }
                
                guard let response = responseMessage else {
                    addAssistantMessage(content: "Received an empty response from the AI.")
                    currentAgentStatus = .error("Empty AI Response") // Update status
                    return
                }

                conversationHistory.append(response)

                if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                    
                    var toolOutputs: [ChatMessage] = []
                    
                    for toolCall in toolCalls {
                        currentAgentStatus = .callingTool(toolCall.function.name) // Update status to show tool being called
                        let toolOutput = await executeTool(toolCall: toolCall)
                        toolOutputs.append(toolOutput)
                    }

                    conversationHistory.append(contentsOf: toolOutputs)
                    currentAgentStatus = .thinking // Back to thinking after tool output, for the next AI turn
                    
                } else {
                    let finalContent = response.content ?? "I processed your request, but the final response was empty."
                    addAssistantMessage(content: finalContent)
                    history = conversationHistory
                    currentAgentStatus = .idle // AI has finished its turn
                    return
                }
            }
            addAssistantMessage(content: "I hit the maximum step limit while trying to process your request.")
            currentAgentStatus = .error("Max Step Limit Reached") // Update status
            
        } catch {
            addAssistantMessage(content: "An unexpected error occurred: \(error.localizedDescription)")
            currentAgentStatus = .error(error.localizedDescription) // Update status
        }
    }
    
    private func addAssistantMessage(content: String) {
        print("Assistant message:", content)
        let message = ChatMessage(id: UUID(), role: "assistant", content: content)
        messages.append(message)
        spokenResponse = content // This triggers the speech service to speak
    }

    // MARK: - Tool Execution

    private func executeTool(toolCall: ToolCall) async -> ChatMessage {
        let functionName = toolCall.function.name
        let argumentsJSON = toolCall.function.arguments
        
        var finalResult: Result<String, ToolExecutionError>
        
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return ChatMessage(id: UUID(), role: "tool", content: "Error: Could not parse arguments for \(functionName).", toolCallId: toolCall.id, name: functionName)
        }

        do {
            switch functionName {
            // NEW SYSTEM INFORMATION TOOL
            case "getCurrentDateTime":
                finalResult = systemTools.getCurrentDateTime()
                
            // WEB TOOLS
            case "googleSearch":
                guard let query = args["query"] as? String else { throw ToolExecutionError.missingArgument("query") }
                finalResult = systemTools.googleSearch(query: query)
                
            case "openWebsite":
                guard let url = args["url"] as? String else { throw ToolExecutionError.missingArgument("url") }
                finalResult = systemTools.openWebsite(url: url)

            case "searchYouTube":
                guard let query = args["query"] as? String else { throw ToolExecutionError.missingArgument("query") }
                finalResult = systemTools.searchYouTube(query: query)
                
            // APPLICATION CONTROL TOOLS
            case "openApplication":
                guard let name = args["name"] as? String else { throw ToolExecutionError.missingArgument("name") }
                finalResult = systemTools.openApplication(name: name)
                
            case "closeFrontmostApplication":
                finalResult = await systemTools.closeFrontmostApplication()
                
            case "minimizeFrontmostWindow":
                finalResult = await systemTools.minimizeFrontmostWindow()

            // WRITING & TEXT MANIPULATION TOOLS
            case "typeText":
                guard let content = args["content"] as? String else { throw ToolExecutionError.missingArgument("content") }
                finalResult = await systemTools.typeText(content: content)
            
            case "pasteText":
                guard let content = args["content"] as? String else { throw ToolExecutionError.missingArgument("content") }
                finalResult = await systemTools.pasteText(content: content)
            
            case "replaceAllText":
                guard let newContent = args["newContent"] as? String else { throw ToolExecutionError.missingArgument("newContent") }
                finalResult = await systemTools.replaceAllText(with: newContent)
            
            case "getTextFromFrontmostApplication":
                finalResult = await systemTools.getTextFromFrontmostApplication()
            
            case "summarizeText":
                finalResult = await systemTools.summarizeText()
            
            case "selectAllText":
                finalResult = await systemTools.selectAllText()
            
            case "copySelection":
                finalResult = await systemTools.copySelection()
                
            // SYSTEM UTILITY TOOLS
            case "runShellCommand":
                guard let command = args["command"] as? String else { throw ToolExecutionError.missingArgument("command") }
                finalResult = await systemTools.runShellCommand(command: command)
                
            case "takeScreenshot":
                finalResult = await systemTools.takeScreenshot()
                
            case "setSystemVolume":
                guard let level = args["level"] as? Int else { throw ToolExecutionError.missingArgument("level") }
                finalResult = await systemTools.setSystemVolume(level: level)
                
            case "createFileWithContent":
                guard let path = args["path"] as? String, let content = args["content"] as? String else { throw ToolExecutionError.missingArgument("path or content") }
                finalResult = try systemTools.createFileWithContent(path: path, content: content)
                
            default:
                finalResult = .failure(.unexpectedError("Tool '\(functionName)' is not implemented in SystemTools."))
            }
        } catch let error as ToolExecutionError {
            finalResult = .failure(error)
        } catch {
            finalResult = .failure(.unexpectedError(error.localizedDescription))
        }
        
        let resultContent: String
        switch finalResult {
        case .success(let message):
            resultContent = message
        case .failure(let error):
            resultContent = "TOOL_ERROR: \(error.localizedDescription)"
        }
        
        return ChatMessage(id: UUID(), role: "tool", content: resultContent, toolCallId: toolCall.id, name: functionName)
    }
    
    // MARK: - OpenAI Network Call

    private func callOpenAI(with messages: [ChatMessage]) async throws -> (ChatMessage?, Error?) {
        let apiKey = UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        let apiMessages = messages.map { message -> [String: Any] in
            var dict: [String: Any] = ["role": message.role]
            if let content = message.content { dict["content"] = content }
            if let toolCallId = message.toolCallId, let name = message.name, let content = message.content {
                dict["tool_call_id"] = toolCallId
                dict["name"] = name
                dict["content"] = content
            }
            if let toolCalls = message.toolCalls {
                dict["tool_calls"] = toolCalls.map { call -> [String: Any] in
                    var callDict: [String: Any] = ["id": call.id, "type": call.type]
                    callDict["function"] = ["name": call.function.name, "arguments": call.function.arguments]
                    return callDict
                }
            }
            return dict
        }
        
        let apiPayload: [String: Any] = [
            "model": modelName,
            "messages": apiMessages,
            "tools": try toolSchemas.map { try encoder.encode($0) }
                .compactMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: apiPayload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        
        #if DEBUG
        if let httpResponse = response as? HTTPURLResponse {
            print("[AetherAgent] Status code: \(httpResponse.statusCode)")
            print("[AetherAgent] Headers: \(httpResponse.allHeaderFields)")
        }
        print("[AetherAgent] Returned data length: \(data.count)")
        if data.count < 1000 {
            print("[AetherAgent] Data as String: \(String(data: data, encoding: .utf8) ?? "<unreadable>")")
        }
        #endif
        
        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            print("[AetherAgent] Response is not an HTTPURLResponse.")
            #endif
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = errorData["error"] as? [String: Any],
               let errorMessage = errorDict["message"] as? String {
                #if DEBUG
                print("[AetherAgent] API Error message: \(errorMessage)")
                #endif
                throw NSError(domain: "OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            #if DEBUG
            print("[AetherAgent] Bad server response with status code: \(httpResponse.statusCode)")
            #endif
            throw URLError(.badServerResponse)
        }
        
        guard !data.isEmpty else {
            #if DEBUG
            print("[AetherAgent] Warning: No data returned from API.")
            #endif
            throw NSError(domain: "OpenAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data returned from API."])
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        struct APIResponse: Codable {
            struct Choice: Codable {
                let message: ChatMessage
            }
            let choices: [Choice]
        }
        
        let apiResponse = try decoder.decode(APIResponse.self, from: data)
        return (apiResponse.choices.first?.message, nil)
    }
}

