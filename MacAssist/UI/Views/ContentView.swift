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
    @EnvironmentObject var controller: VoiceAssistantController
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var contextManager: ContextManager // NEW: Inject ContextManager
    
    @State private var selectedTab: Int = 0
    @State private var selectedConversationId: UUID? // State for sidebar selection
    @AppStorage("openAIApiKey") private var openAIApiKey: String = ""
    
    private var isAssistantActive: Bool {
        controller.isRecording || controller.agent.isProcessing
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                chatView
                    .tag(0)
                    .tabItem {
                        Label("Chat", systemImage: "message.fill")
                    }
                

                ContextView()
                    .tag(3)
                    .tabItem {
                        Label("Context", systemImage: "doc.text.fill")
                    }
                
                settingsView
                    .tag(2)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(0)
        .onAppear {
            controller.requestSpeechAuthorization()
        }
        .alert("Speech Recognition Error", isPresented: $controller.showingSpeechErrorAlert, actions: {
            Button("OK") { controller.showingSpeechErrorAlert = false }
        }, message: {
            Text(controller.speechErrorMessage)
        })
        .environmentObject(controller.contextManager) // Inject ContextManager from controller
    }

    private var chatView: some View {
        NavigationSplitView {
            HistoryView(selectedConversationId: $selectedConversationId)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
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
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        controller.startNewChat()
                        selectedConversationId = nil // Clear selection on new chat
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("Start New Chat")
                }
            }
        }
    }

    private var providerNameView: some View {
        let settings = LLMSettings.load()
        return Text("Using \(settings.selectedProvider.displayName)")
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.bottom, -4)
    }
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            providerNameView
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask Aether...", text: $controller.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .lineLimit(1...5)
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
    }
    
    @ViewBuilder
    private func messageRow(for message: ChatMessage) -> some View {
        MessageBubbleView(message: message)
            .padding(.bottom, 4)
    }

    private var settingsView: some View {
        VStack(alignment: .center, spacing: 24) {
            // Legacy Notice (if old API key exists)
            if !openAIApiKey.isEmpty && !UserDefaults.standard.bool(forKey: "llm_settings_migrated") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Settings Migration")
                            .font(.headline)
                            .bold()
                    }
                    Text("Your OpenAI API key has been migrated to the new provider settings. You can now choose between OpenAI, Gemini, and Ollama.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .frame(maxWidth: 400)
            }
            
            ProviderSettingsView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    static func formattedTimestamp(for message: ChatMessage) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}

#Preview {
    let historyManager = HistoryManager()
    return ContentView()
        .environmentObject(VoiceAssistantController(historyManager: historyManager))
        .environmentObject(historyManager)
        .environmentObject(ContextManager())
}
