
import Foundation

struct ChatModel: Identifiable {
    let id: UUID
    let sender: String
    let content: String
    let timestamp: Date
    let toolUsed: String?

    init(id: UUID = UUID(), sender: String, content: String, timestamp: Date, toolUsed: String?) {
        self.id = id
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.toolUsed = toolUsed
    }
}
