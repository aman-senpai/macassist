
import SwiftUI

struct InputBarView: View {
    @State private var messageText = ""
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        HStack {
            TextField("Message", text: $messageText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: {
                viewModel.sendMessage(messageText)
                messageText = ""
            }) {
                Text("Send")
            }
        }
        .padding()
    }
}
