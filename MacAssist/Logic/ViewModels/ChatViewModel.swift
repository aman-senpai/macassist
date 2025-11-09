
import SwiftUI
import Combine
import Foundation

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    
    private let aiService: AIService
    private let toolExecutionManager: ToolExecutionManager
    
    init(aiService: AIService, toolExecutionManager: ToolExecutionManager) {
        self.aiService = aiService
        self.toolExecutionManager = toolExecutionManager
    }
    
    func sendMessage(_ message: String) {
        let userMessage = ChatMessage(id: UUID(), role: "user", content: message, timestamp: Date())
        objectWillChange.send()
        messages.append(userMessage)

        Task {
            do {
                let chatMessages = self.messages.compactMap { message -> AIService.ChatMessage? in
                    guard let role = AIService.ChatRole(rawValue: message.role) else { return nil }
                    return AIService.ChatMessage(role: role, content: message.content ?? "")
                }
                let aiResponseContent = try await aiService.getChatCompletion(messages: chatMessages)
                let aiMessage = ChatMessage(id: UUID(), role: "assistant", content: aiResponseContent, timestamp: Date())
                
                DispatchQueue.main.async {
                    self.messages.append(aiMessage)
                }
            } catch {
                let errorMessage = ChatMessage(id: UUID(), role: "assistant", content: "Error: \(error.localizedDescription)", timestamp: Date())
                DispatchQueue.main.async {
                    self.messages.append(errorMessage)
                }
            }
        }
    }
}
