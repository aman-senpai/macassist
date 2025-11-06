
import SwiftUI

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(viewModel.messages, id: \.timestamp) { message in
                    MessageBubbleView(message: message)
                }
            }
            InputBarView(viewModel: viewModel)
        }
    }
}
