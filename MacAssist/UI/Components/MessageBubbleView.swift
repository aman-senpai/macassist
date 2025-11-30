
import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var isHovering = false
    @State private var showCheckmark = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == "user" {
                Spacer(minLength: 20)
                
                Text(.init(message.content ?? "No message"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.primary)
                    .cornerRadius(16)
                    .overlay(alignment: .leading) {
                        if isHovering {
                            copyButton
                                .offset(x: -40) // Position to the left of the bubble
                        }
                    }
            } else {
                Text(.init(message.content ?? "No message"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundColor(.primary)
                    .overlay(alignment: .trailing) {
                        if isHovering {
                            copyButton
                                .offset(x: 40) // Position to the right of the bubble
                        }
                    }
                
                Spacer(minLength: 20)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    
    private var copyButton: some View {
        Button(action: copyToClipboard) {
            Image(systemName: showCheckmark ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.system(size: 14))
                .foregroundColor(showCheckmark ? .green : .secondary)
                .padding(6)
                .background(.regularMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale))
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content ?? "", forType: .string)
        
        withAnimation {
            showCheckmark = true
        }
        
        // Reset checkmark after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCheckmark = false
            }
        }
    }
}
