//
//  AetherAgent.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import Foundation
import SwiftUI
import Combine
import AppKit

struct ChatMessage: Identifiable, Codable {
    var id: UUID?
    let role: String
    var content: String?
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var name: String?
    var refusal: String?
    var annotations: [Annotation]?
    var timestamp: Date

    var safeId: UUID { id ?? UUID() }

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

struct ToolCall: Codable, Equatable {
    let id: String
    let function: FunctionCall
    let type: String = "function"
}

struct FunctionCall: Codable, Equatable {
    let name: String
    let arguments: String
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

@MainActor
final class AetherAgent: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing: Bool = false
    @Published var spokenResponse: String?
    @Published var currentAgentStatus: AssistantStatus = .idle // NEW: Agent's internal status
    
    private let systemTools = SystemTools()
    private let historyManager: HistoryManager
    private var conversationID: UUID
    
    private let systemPrompt = ChatMessage(id: UUID(), role: "system", content: """
        You are 'Aether', a proactive, resourceful, and charming AI assistant deeply integrated into macOS.

        ## Your Personality & Tone
        *   **Conversational & Warm:** You are not a robot; you are a helpful companion. Use natural language. Instead of "The current time is...", say "It's 3:30 PM."
        *   **Concise but Friendly:** You live in a menu bar, so keep it brief, but don't sacrifice warmth.
        *   **Proactive:** If you do something, explain *what* you did simply.
        *   **Witty (Optional):** Feel free to add a tiny bit of flair or wit if appropriate, but keep it professional.

        ## Your Mission
        Your primary goal is to be exceptionally helpful, conversational, and efficient. You must anticipate user needs, understand their intent, and execute tasks seamlessly.

        ## Core Capabilities
        *   **OS & App Control:** You use a suite of tools to open apps, control system settings (like volume, brightness), and manage files.
        *   **Text Manipulation:** You can interact with the foreground application to type, paste, select, or replace text.
        *   **Content Comprehension:** You can summarize or analyze on-screen content or provided text.
        *   **Knowledge Retrieval:** You have access to real-time information via search.

        ## Core Directives & Reasoning Strategy

        ### 1. Decision Protocol: Direct vs. Deliberate
        *   **FAST PATH (Direct Execution):**
            *   **Trigger:** Simple, unambiguous commands (e.g., "What time is it?", "Open Safari", "Mute volume").
            *   **Action:** Execute the tool *immediately*. Do not explain your plan. Just do it and confirm.
        *   **SLOW PATH (Deliberate Reasoning):**
            *   **Trigger:** Complex, multi-step, or ambiguous requests (e.g., "Find the best Italian restaurant nearby and draft an email to my boss about it").
            *   **Action:** You must **PAUSE and THINK**. Formulate a "Chain of Thought" or "Tree of Thoughts" before calling tools.
            *   **Tree of Thoughts:** Consider 2-3 approaches. Pick the most efficient one.
            *   **Chain of Thought:** Break the chosen approach into steps:
                1.  Search for restaurants.
                2.  Select the best one based on ratings.
                3.  Open Mail app.
                4.  Draft the email.

        ### 2. Intelligent Tool Use
        *   **Actions:** For any direct command, *always* use the appropriate tool.
        *   **Creation:** When asked to write or compose, use the `typeText` tool.
        *   **Knowledge:** For general questions, facts, or real-time info, *default* to `googleSearch`.
        *   **Specifics:** Use `getCurrentDateTime` for time/date queries and `searchYouTube` for video requests.

        ### 3. Natural Language Generation (CRITICAL)
        *   **Time/Date:** Parse raw strings (e.g., "2025-11-30...") into natural speech ("It's Sunday, November 30th").
        *   **Tool Outputs:** Don't parrot tool output. If `openApplication` succeeds, say "I've opened that for you."

        ### 4. Handling Ambiguity
        *   If a request is vague (e.g., "Summarize this"), ask **one concise clarifying question** (e.g., "Should I summarize the text in the foreground app?").
        *   Do not guess on irreversible actions.

        ### 5. File Handling & Robustness
        *   **Typos & Extensions:** Users make mistakes (e.g., asking for a ".tax" file instead of ".txt"). If a file isn't found, **search for similar names or extensions** using `searchFiles`.
        *   **Folders:** To open a directory (e.g., "Downloads"), use `openPath`.
        *   **Inspection:** To count files or find specific types in a folder, **FIRST use `listDirectory`**, THEN analyze the output yourself.
        *   **No Hallucinations:** Never say "I found these files" followed by a placeholder. Only list files you actually see in the tool output.
        *   **Verification:** Always `searchFiles` before claiming a file doesn't exist.

        ### 6. Strict Tool Usage (CRITICAL)
        *   **NO Pseudo-Code:** NEVER output code blocks like `tool_code` or `print(...)` to perform actions. You are NOT a python interpreter.
        *   **Use Defined Tools:** ONLY use the provided tools (e.g., `runShellCommand`, `openPath`) via the standard tool calling mechanism.
        *   **Shell Commands:** For file operations like moving/copying/creating directories, use `runShellCommand`.

        ### 7. Limitations
        *   If you lack a tool, state it clearly and **offer an alternative**.
        """)

    private var history: [ChatMessage] = []
    
    
    init(historyManager: HistoryManager) {
        self.historyManager = historyManager
        self.conversationID = UUID() // Assign a unique ID for this session
        AetherAgent.checkAndRequestPermissions()
        
        history.append(systemPrompt)
        messages.append(ChatMessage(id: UUID(), role: "assistant", content: "Hello! Enter your query to start."))
        currentAgentStatus = .idle
    }
        
    private static func checkAndRequestPermissions() {
        let accessibilityOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if AXIsProcessTrustedWithOptions(accessibilityOptions) {
            print("[AetherAgent] Accessibility access has been granted.")
        } else {
            print("[AetherAgent] Accessibility access not granted. The system should prompt the user.")
        }
        
    }
    
    private var toolSchemas: [ToolSchema] {
        return [
            ToolSchema(function: FunctionDetails(
                name: "getCurrentDateTime",
                description: "Retrieves the current system date, time, and timezone. Use this when the user asks 'what time is it?' or 'what is the date?'",
                parameters: ParameterSchema(properties: [:], required: []))),

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
                description: "Summarizes the selected text in the frontmost application. If no text is selected, it summarizes all the text. The summary then replaces the original text. Use this when the user asks to summarize the current content.",
                parameters: ParameterSchema(properties: [:], required: []))),
            ToolSchema(function: FunctionDetails(
                name: "selectAllText",
                description: "Selects all text in the active text field or document of the frontmost application (simulates Command-A).",
                parameters: ParameterSchema(properties: [:], required: []))),
            ToolSchema(function: FunctionDetails(
                name: "copySelection",
                description: "Copies the currently selected text to the clipboard (simulates Command-C).",
                parameters: ParameterSchema(properties: [:], required: []))),
            
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
                ))),
            ToolSchema(function: FunctionDetails(
                name: "openPath",
                description: "Opens a file or directory at the specified path using the default application or Finder.",
                parameters: ParameterSchema(
                    properties: ["path": PropertyDetails(type: "string", description: "The absolute or relative path to open (e.g., '~/Downloads', '/Users/name/file.txt').")],
                    required: ["path"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "searchFiles",
                description: "Searches for files matching a query using Spotlight (mdfind). Use this to find files when the exact path is unknown or to handle fuzzy requests.",
                parameters: ParameterSchema(
                    properties: [
                        "query": PropertyDetails(type: "string", description: "The filename or search term to look for."),
                        "searchScope": PropertyDetails(type: "string", description: "Optional. The specific folder to search in (e.g., '~/Downloads'). If omitted, searches the entire system.")
                    ],
                    required: ["query"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "listDirectory",
                description: "Lists all files and subdirectories in the specified directory path. Use this to count files or see what's inside a folder.",
                parameters: ParameterSchema(
                    properties: ["path": PropertyDetails(type: "string", description: "The absolute or relative path of the directory to list (e.g., '~/Downloads').")],
                    required: ["path"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "readFileContent",
                description: "Reads the text content of a file at the specified path. Use this to analyze code files, read notes, or check configuration files.",
                parameters: ParameterSchema(
                    properties: ["path": PropertyDetails(type: "string", description: "The absolute or relative path of the file to read (e.g., '~/Documents/notes.txt').")],
                    required: ["path"]
                ))),
            ToolSchema(function: FunctionDetails(
                name: "writeToFile",
                description: "Writes text content to a file at the specified path. Creates the file if it doesn't exist, and overwrites it if it does. Use this for creating new files or editing existing ones.",
                parameters: ParameterSchema(
                    properties: [
                        "path": PropertyDetails(type: "string", description: "The absolute or relative path of the file to write to (e.g., '~/Documents/notes.txt')."),
                        "content": PropertyDetails(type: "string", description: "The text content to write to the file.")
                    ],
                    required: ["path", "content"]
                )))
        ]
    }
    
    
    func sendMessage(text: String) {
        guard !isProcessing else { return }
        
        let userMessage = ChatMessage(id: UUID(), role: "user", content: text)
        messages.append(userMessage)
        history.append(userMessage)
        
        Task {
            isProcessing = true
            currentAgentStatus = .thinking
            await processResponse()
            isProcessing = false
            if case .thinking = currentAgentStatus {
                currentAgentStatus = .idle
            }
        }
    }
    
    func startNewChat() {
        // Save current conversation one last time to be sure
        saveConversation()
        
        // Reset state
        self.conversationID = UUID()
        self.history = [systemPrompt]
        self.messages = [ChatMessage(id: UUID(), role: "assistant", content: "Hello! Enter your query to start.")]
        self.currentAgentStatus = .idle
        self.spokenResponse = nil
        
        print("[AetherAgent] Started new chat session: \(self.conversationID)")
    }
    
    
    private func processResponse() async {
        // Check if provider is configured
        let settings = LLMSettings.load()
        let providerType = settings.selectedProvider
        let config = settings.config(for: providerType)
        
        // Check API key if required
        if providerType.requiresAPIKey {
            guard let apiKey = config.apiKey, !apiKey.isEmpty else {
                addAssistantMessage(content: "Please configure your \(providerType.displayName) API key in the Settings tab.")
                currentAgentStatus = .error("API Key Missing")
                return
            }
        }

        do {
            var conversationHistory = history
            
            for _ in 0..<5 {
                currentAgentStatus = .responding
                // Call LLM with tools for general conversation
                let (responseMessage, completionError) = try await callLLM(with: conversationHistory, includeTools: true)
                
                if let error = completionError {
                    let errorMessage = error.localizedDescription
                    
                    // Check if error is because model doesn't support tools
                    if errorMessage.contains("does not support tools") || errorMessage.contains("toolsNotSupported") {
                        print("[AetherAgent] Model doesn't support tools, retrying without tools...")
                        // Retry without tools
                        let (retryResponse, retryError) = try await callLLM(with: conversationHistory, includeTools: false)
                        
                        if let retryErr = retryError {
                            addAssistantMessage(content: "API Error: \(retryErr.localizedDescription)")
                            currentAgentStatus = .error("API Error")
                            return
                        }
                        
                        guard let response = retryResponse else {
                            addAssistantMessage(content: "Received an empty response from the AI.")
                            currentAgentStatus = .error("Empty AI Response")
                            return
                        }
                        
                        // Continue with the response (no tool calls available)
                        let finalContent = response.content ?? "I processed your request, but the final response was empty."
                        addAssistantMessage(content: "Note: This model doesn't support tool calling, so I can only provide information.\n\n\(finalContent)")
                        history = conversationHistory + [response]
                        currentAgentStatus = .idle
                        return
                    }
                    
                    addAssistantMessage(content: "API Error: \(error.localizedDescription)")
                    currentAgentStatus = .error("API Error")
                    return
                }
                
                guard let response = responseMessage else {
                    addAssistantMessage(content: "Received an empty response from the AI.")
                    currentAgentStatus = .error("Empty AI Response")
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
        saveConversation()
    }

    private func saveConversation() {
        let filteredHistory = history.filter { $0.role != "system" }
        if !filteredHistory.isEmpty {
            let messagesToSave = filteredHistory.map { Message(id: $0.id ?? UUID(), content: $0.content ?? "", role: $0.role, timestamp: $0.timestamp) }
            let conversation = Conversation(id: self.conversationID, messages: messagesToSave, timestamp: Date())
            historyManager.saveConversation(conversation)
        }
    }

    // MARK: - Tool Execution
    
    private func summarizeText() async -> Result<String, ToolExecutionError> {
        var textToSummarize: String?
        
        // Try to get selected text first
        let selectedTextResult = await systemTools.getSelectedText()
        if case .success(let selectedText) = selectedTextResult, !selectedText.isEmpty {
            textToSummarize = selectedText
        } else {
            // If selected text is empty or there was an error, get all text
            if case .failure(let error) = selectedTextResult {
                print("Could not get selected text: \(error.localizedDescription). Falling back to all text.")
            }
            
            let allTextResult = await systemTools.getTextFromFrontmostApplication()
            switch allTextResult {
            case .success(let allText):
                textToSummarize = allText
            case .failure(let error):
                return .failure(error) // If getting all text fails, we can't proceed
            }
        }
        
        guard let finalTextToSummarize = textToSummarize, !finalTextToSummarize.isEmpty else {
            return .failure(.summarizationFailed("The document is empty, nothing to summarize."))
        }

        let summaryPrompt = "Please summarize the following text concisely: \(finalTextToSummarize)"
        print(summaryPrompt)
        let promptMessage = ChatMessage(role: "user", content: summaryPrompt)
        
        do {
            // Call LLM *without* tools for summarization
            let (response, error) = try await callLLM(with: [systemPrompt, promptMessage], includeTools: false)
            
            if let error = error {
                return .failure(.summarizationFailed("API call failed: \(error.localizedDescription)"))
            }
            
            // This is the crucial guard. If response.content is nil, it means the AI tried to call a tool instead.
            guard let summary = response?.content, !summary.isEmpty else {
                // If the response was empty but there were tool calls, we should report that.
                if let toolCalls = response?.toolCalls, !toolCalls.isEmpty {
                    return .failure(.summarizationFailed("AI attempted to call a tool for summarization: \(toolCalls.first?.function.name ?? "unknown tool"). This should not happen when tools are disabled for summarization."))
                }
                return .failure(.summarizationFailed("Summarization failed or returned an empty result."))
            }
            
            let replaceResult = await systemTools.replaceAllText(with: summary)
            
            switch replaceResult {
            case .success:
                return .success("Successfully summarized and replaced the text.")
            case .failure(let error):
                return .failure(error)
            }
        } catch {
            return .failure(.summarizationFailed("An unexpected error occurred during summarization: \(error.localizedDescription)"))
        }
    }

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
                finalResult = await summarizeText()
            
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
                
            case "openPath":
                guard let path = args["path"] as? String else { throw ToolExecutionError.missingArgument("path") }
                finalResult = systemTools.openPath(path: path)
                
            case "searchFiles":
                guard let query = args["query"] as? String else { throw ToolExecutionError.missingArgument("query") }
                let searchScope = args["searchScope"] as? String
                finalResult = systemTools.searchFiles(query: query, searchScope: searchScope)
                
            case "listDirectory":
                guard let path = args["path"] as? String else { throw ToolExecutionError.missingArgument("path") }
                finalResult = systemTools.listDirectory(path: path)

            case "readFileContent":
                guard let path = args["path"] as? String else { throw ToolExecutionError.missingArgument("path") }
                finalResult = systemTools.readFileContent(path: path)

            case "writeToFile":
                guard let path = args["path"] as? String, let content = args["content"] as? String else { throw ToolExecutionError.missingArgument("path or content") }
                finalResult = systemTools.writeToFile(path: path, content: content)
                
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
    
    // MARK: - LLM Network Call

    private func callLLM(with messages: [ChatMessage], includeTools: Bool) async throws -> (ChatMessage?, Error?) {
        // Load settings and create AIService
        let settings = LLMSettings.load()
        
        guard let aiService = try? AIService() else {
            throw NSError(domain: "AIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AI service"])
        }
        
        // Convert messages to LLMMessage format
        let llmMessages = messages.map { message -> LLMMessage in
            LLMMessage(
                role: message.role,
                content: message.content,
                toolCalls: message.toolCalls,
                toolCallId: message.toolCallId,
                name: message.name
            )
        }
        
        // Prepare tools if needed
        let tools: [ToolSchema]? = includeTools ? toolSchemas : nil

        
        do {
            // Call AIService with tools - use nil for model to use provider's configured default
            let llmResponse = try await aiService.sendMessageWithTools(
                messages: llmMessages,
                model: nil,
                temperature: nil,
                maxTokens: nil,
                tools: tools
            )
            
            #if DEBUG
            print("[AetherAgent] LLM Response: content=\(llmResponse.content ?? "nil"), toolCalls=\(llmResponse.toolCalls?.count ?? 0)")
            #endif
            
            // Convert LLMResponse back to ChatMessage
            let chatMessage = ChatMessage(
                id: UUID(),
                role: "assistant",
                content: llmResponse.content,
                toolCalls: llmResponse.toolCalls,
                toolCallId: nil,
                name: nil
            )
            
            return (chatMessage, nil)
        } catch {
            #if DEBUG
            print("[AetherAgent] LLM Error: \(error.localizedDescription)")
            #endif
            return (nil, error)
        }
    }
}

