
import SwiftUI
import Combine
import Foundation

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatModel] = []
    
    private let aiService: AIService
    private let toolExecutionManager: ToolExecutionManager
    
    init(aiService: AIService, toolExecutionManager: ToolExecutionManager) {
        self.aiService = aiService
        self.toolExecutionManager = toolExecutionManager
    }
    
    func sendMessage(_ message: String) {
        let userMessage = ChatModel(sender: "user", content: message, timestamp: Date(), toolUsed: nil)
        objectWillChange.send()
        messages.append(userMessage)

        Task {
            do {
                let chatMessages = self.messages.compactMap { message -> AIService.ChatMessage? in
                    guard let role = AIService.ChatRole(rawValue: message.sender) else { return nil }
                    return AIService.ChatMessage(role: role, content: message.content)
                }
                let aiResponseContent = try await aiService.getChatCompletion(messages: chatMessages)
                let aiMessage = ChatModel(sender: "assistant", content: aiResponseContent, timestamp: Date(), toolUsed: nil)
                
                DispatchQueue.main.async {
                    self.messages.append(aiMessage)
                }
            } catch {
                let errorMessage = ChatModel(sender: "assistant", content: "Error: \(error.localizedDescription)", timestamp: Date(), toolUsed: nil)
                DispatchQueue.main.async {
                    self.messages.append(errorMessage)
                }
            }
        }
    }
}
