//
//  ContentView.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import SwiftUI
import Combine
import Speech
import AVFoundation

struct ContentView: View {
    // The controller is now the source of truth, passed from the environment.
    @EnvironmentObject var controller: VoiceAssistantController
    
    @State private var selectedTab: Int = 0
    @AppStorage("openAIApiKey") private var openAIApiKey: String = ""
    
    // Computed property to determine if the assistant is actively listening or processing.
    private var isAssistantActive: Bool {
        controller.isRecording || controller.agent.isProcessing
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                // MARK: Chat View
                chatView
                    .tag(0)
                    .tabItem {
                        Label("Chat", systemImage: "message.fill")
                    }
                
                // MARK: Settings View
                settingsView
                    .tag(1)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(0)
        .onAppear {
            controller.requestSpeechAuthorization() // Request permissions on appear
        }
        .alert("Speech Recognition Error", isPresented: $controller.showingSpeechErrorAlert, actions: {
            Button("OK") { controller.showingSpeechErrorAlert = false }
        }, message: {
            Text(controller.speechErrorMessage)
        })
    }

    // MARK: - Chat View Body
    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(controller.agent.messages) { message in
                    messageRow(for: message)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .id(message.safeId)
                }
                .listStyle(.plain)
                .padding(.horizontal, 12)
                .onChange(of: controller.agent.messages.count) {
                    if let lastMessage = controller.agent.messages.last {
                        proxy.scrollTo(lastMessage.safeId, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            inputBar
        }
        .padding(.top, 6)
    }

    // MARK: - Input Bar Body
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Aether...", text: $controller.currentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .lineLimit(1...5)
                // Add a Siri-like glow effect when the assistant is active
                .shadow(color: isAssistantActive ? .accentColor.opacity(0.6) : .clear, radius: 4)
                .shadow(color: isAssistantActive ? .accentColor.opacity(0.4) : .clear, radius: 8)
                .animation(.easeInOut(duration: 0.5), value: isAssistantActive)
                .onSubmit(controller.sendMessage)
                .disabled(controller.isRecording)
            
            Button(action: controller.toggleContinuousConversation) {
                Image(systemName: controller.isContinuousConversationActive ? "stop.circle.fill" : "mic.circle.fill")
                    .resizable().frame(width: 24, height: 24)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(controller.isContinuousConversationActive ? .red : .accentColor)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 4)
            .offset(y: -4)
            .disabled(controller.speechAuthorizationStatus != .authorized || controller.agent.isProcessing)
            
            if controller.agent.isProcessing {
                ProgressView().padding(.trailing, 8)
            } else {
                Button(action: controller.sendMessage) {
                    Image(systemName: "arrow.up.circle.fill").resizable().frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(controller.currentInput.isEmpty || controller.isRecording)
                .foregroundColor(.primary)
                .padding(.trailing, 8)
                .offset(y: -4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    // MARK: - Message Row
    @ViewBuilder
    private func messageRow(for message: ChatMessage) -> some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
            HStack {
                let isUser = message.role == "user"
                if isUser { Spacer(minLength: 20) }
                
                let messageContent = Text(message.content ?? "")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 450, alignment: isUser ? .trailing : .leading)
                    .foregroundColor(.primary)

                if isUser {
                    messageContent
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.gray.opacity(0.3))
                        )
                } else {
                    messageContent
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                
                if !isUser { Spacer(minLength: 20) }
            }
            
            Text(Self.formattedTimestamp(for: message))
                .font(.caption2)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                .padding(message.role == "user" ? .trailing : .leading, 14)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Settings View Body
    private var settingsView: some View {
        VStack(alignment: .center, spacing: 24) {
            VStack(alignment: .center, spacing: 6) {
                Text("OpenAI API Key").font(.headline).bold()
                SecureField("Enter your OpenAI API Key", text: $openAIApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle").foregroundColor(.secondary).font(.body).padding(.top, 2)
                Text("Your key is stored securely on your Mac. It is required to use the AI features.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 250)
    }
    
    static func formattedTimestamp(for message: ChatMessage) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(VoiceAssistantController())
}
