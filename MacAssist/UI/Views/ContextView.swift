import SwiftUI

struct ContextView: View {
    @EnvironmentObject var contextManager: ContextManager
    
    var body: some View {
        NavigationStack {
            VStack {
                if contextManager.contexts.isEmpty {
                    ContentUnavailableView(
                        "No Contexts",
                        systemImage: "doc.text",
                        description: Text("Add context items to help the AI understand you better.\nThese will be sent with every new chat.")
                    )
                } else {
                    List {
                        ForEach($contextManager.contexts) { $context in
                            ContextItemRow(context: $context)
                                .listRowSeparator(.visible)
                                .padding(.vertical, 4)
                        }
                        .onDelete(perform: contextManager.deleteContext)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Context")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        contextManager.addContext(text: "")
                    }) {
                        Label("Add Context", systemImage: "plus")
                    }
                }
            }
        }
    }
}

struct ContextItemRow: View {
    @Binding var context: ContextItem
    @EnvironmentObject var contextManager: ContextManager
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Toggle("", isOn: $context.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                    .onChange(of: context.isEnabled) {
                        contextManager.updateContext(context)
                    }
                
                TextEditor(text: $context.text)
                    .font(.body)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .focused($isFocused)
                    .onChange(of: context.text) {
                        contextManager.updateContext(context)
                    }
                
                Button(action: {
                    contextManager.deleteContext(context)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .onAppear {
            if context.text.isEmpty {
                isFocused = true
            }
        }
    }
}

#Preview {
    let manager = ContextManager()
    manager.contexts = [
        ContextItem(text: "My name is Senpai.", isEnabled: true),
        ContextItem(text: "I am a software engineer.", isEnabled: false)
    ]
    return ContextView()
        .environmentObject(manager)
}
