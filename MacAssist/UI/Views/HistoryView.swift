import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var historyManager: HistoryManager
    @State private var selectedConversationId: UUID?

    var body: some View {
        NavigationView {
            List {
                ForEach(historyManager.conversationHistory) { conversation in
                    NavigationLink(destination: ConversationDetailView(conversation: conversation, onDelete: {
                        self.selectedConversationId = nil
                        // Delay the deletion slightly to allow the navigation to pop back
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            historyManager.deleteConversation(conversation)
                        }
                    }), tag: conversation.id, selection: $selectedConversationId) {
                        VStack(alignment: .leading) {
                            Text("Conversation from \(conversation.timestamp, formatter: itemFormatter)")
                            Text(conversation.messages.first?.content ?? "No messages")
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
    let conversation: Conversation
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Conversation Details")
                    .font(.title)
                    .bold()
                Text("Timestamp: \(conversation.timestamp, formatter: itemFormatter)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
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
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()
