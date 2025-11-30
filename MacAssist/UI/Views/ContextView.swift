import SwiftUI

struct ContextView: View {
    @EnvironmentObject var contextManager: ContextManager
    @State private var selectedContextId: UUID?
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedContextId) {
                    ForEach($contextManager.contexts) { $context in
                        NavigationLink(value: context.id) {
                            ContextSidebarRow(context: $context)
                        }
                    }
                    .onDelete(perform: contextManager.deleteContext)
                }
                
                Divider()
                
                Button(action: {
                    let newId = UUID()
                    contextManager.addContext(text: "")
                    if let last = contextManager.contexts.last {
                        selectedContextId = last.id
                    }
                }) {
                    Label("Add Context", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding()
                .background(.thinMaterial)
            }
            .navigationTitle("Contexts")
        } detail: {
            if let selectedId = selectedContextId,
               let index = contextManager.contexts.firstIndex(where: { $0.id == selectedId }) {
                ContextDetailView(context: $contextManager.contexts[index])
                    .id(selectedId) // Force recreation when selection changes
            } else {
                ContentUnavailableView(
                    "Select a Context",
                    systemImage: "doc.text",
                    description: Text("Select a context item from the sidebar to edit, or create a new one.")
                )
            }
        }
    }
}

struct ContextSidebarRow: View {
    @Binding var context: ContextItem
    @EnvironmentObject var contextManager: ContextManager
    
    var body: some View {
        HStack {
            Text(context.title.isEmpty ? "New Context" : context.title)
                .lineLimit(1)
                .font(.body)
            
            Spacer()
            
            if context.isEnabled {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct ContextDetailView: View {
    @Binding var context: ContextItem
    @EnvironmentObject var contextManager: ContextManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Title", text: $context.title)
                    .font(.title2)
                    .textFieldStyle(.roundedBorder)
                
                Toggle("", isOn: $context.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .onChange(of: context.isEnabled) {
                        contextManager.updateContext(context)
                    }
            }
            .padding(.horizontal, 10)
            .onChange(of: context.title) {
                contextManager.updateContext(context)
            }
            
            MacEditorTextView(text: $context.text, onCommit: {
                // Focus handling if needed
            })
            .font(.body)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .frame(maxHeight: .infinity) // Fill available space
            .onChange(of: context.text) {
                contextManager.updateContext(context)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Edit Context")
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(action: {
                    contextManager.deleteContext(context)
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
