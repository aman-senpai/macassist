import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var historyManager: HistoryManager
    @State private var selectedConversationId: UUID?

    var body: some View {
        NavigationView {
            List {
                ForEach(historyManager.conversationHistory.sorted(by: { $0.timestamp > $1.timestamp })) { conversation in
                    NavigationLink(destination: ConversationDetailView(conversation: conversation, onDelete: {
                        self.selectedConversationId = nil
                        // Delay the deletion slightly to allow the navigation to pop back
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            historyManager.deleteConversation(conversation)
                        }
                    }), tag: conversation.id, selection: $selectedConversationId) {
                        VStack(alignment: .leading) {
                            Text(conversation.title) // Use the computed title (stored or fallback)
                                .font(.headline)
                            Text("Conversation from \(conversation.timestamp, formatter: itemFormatter)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("History")

            Text("Select a conversation to view its details.")
                .foregroundColor(.gray)
        }
    }
}

struct ConversationDetailView: View {
    @EnvironmentObject var historyManager: HistoryManager
    let conversation: Conversation
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(conversation.title)
                    .font(.title)
                    .bold()
                Text("Timestamp: \(conversation.timestamp, formatter: itemFormatter)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                if let summary = conversation.summary {
                    Text(summary)
                        .font(.body)
                        .italic()
                        .padding(.vertical, 4)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                ForEach(conversation.messages, id: \.id) { message in
                    MessageBubbleView(message: ChatMessage(id: message.id, role: message.role, content: message.content, timestamp: message.timestamp))
                }
            }
            .padding()
        }
        .navigationTitle("Details")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button(action: {
                        Task {
                            await regenerateTitleAndSummary()
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .help("Regenerate Title & Summary")
                    }
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
    
    // Function to manually regenerate title and summary
    private func regenerateTitleAndSummary() async {
        do {
            let aiService = try AIService()
            let chatMessages = conversation.messages.map { message in
                AIService.ChatMessage(role: AIService.ChatRole(rawValue: message.role) ?? .user, content: message.content)
            }
            
            let (title, summary) = try await aiService.generateTitleAndSummary(for: chatMessages)
            
            // Update the conversation using HistoryManager
            await MainActor.run {
                var updatedConversation = conversation
                updatedConversation.storedTitle = title
                updatedConversation.summary = summary
                historyManager.saveConversation(updatedConversation)
                print("Regenerated title: \(title)")
            }
        } catch {
            print("Error regenerating: \(error)")
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()
