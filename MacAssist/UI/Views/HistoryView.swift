import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var controller: VoiceAssistantController
    @Binding var selectedConversationId: UUID?

    var body: some View {
        List(selection: $selectedConversationId) {
            ForEach(historyManager.conversationHistory.sorted(by: { $0.timestamp > $1.timestamp })) { conversation in
                HistoryRowView(conversation: conversation, selectedConversationId: $selectedConversationId)
                    .tag(conversation.id)
                    .onTapGesture {
                        selectedConversationId = conversation.id
                        controller.loadConversation(conversation)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            historyManager.deleteConversation(conversation)
                            if selectedConversationId == conversation.id {
                                selectedConversationId = nil
                                controller.startNewChat()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("History")
    }
}

struct HistoryRowView: View {
    let conversation: Conversation
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var controller: VoiceAssistantController
    @Binding var selectedConversationId: UUID?
    @State private var isHovering = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
            
            if isHovering || showingDeleteConfirmation {
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.red) // Red for delete action
                        .padding(4)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .confirmationDialog("Delete Conversation?", isPresented: $showingDeleteConfirmation) {
                    Button("Delete", role: .destructive) {
                        historyManager.deleteConversation(conversation)
                        if selectedConversationId == conversation.id {
                            selectedConversationId = nil
                            controller.startNewChat()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to delete this conversation? This action cannot be undone.")
                }
            } else {
                // Invisible placeholder to prevent layout jumpiness
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .padding(4)
                    .opacity(0)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovering ? Color.gray.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}



private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()
