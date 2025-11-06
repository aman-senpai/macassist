
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
        // TODO: Implement send message logic
    }
}
