//
//  MacAssistApp.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import SwiftUI

@main
struct MacAssistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Removed @StateObject private var historyManager = HistoryManager()
    @Environment(\.scenePhase) private var scenePhase
    
    private var voiceAssistantController: VoiceAssistantController {
        appDelegate.voiceAssistantController
    }

    // Access the shared HistoryManager instance from the AppDelegate
    private var historyManager: HistoryManager {
        appDelegate.sharedHistoryManager
    }

    var body: some Scene {
        Window("MacAssist", id: "main") {
            ContentView()
                .environmentObject(voiceAssistantController) // Pass controller to the view
                .environmentObject(historyManager) // Use the shared instance
                .frame(minWidth: 380, idealWidth: 450, maxWidth: 600, minHeight: 400, idealHeight: 500, maxHeight: 800)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .inactive {
                historyManager.saveCurrentSessionHistory()
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        MenuBarExtra {
            MenuBarContentView()
        } label: {
            let isAssistantActive = voiceAssistantController.isRecording || voiceAssistantController.agent.isProcessing

            Image(systemName: "waveform.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 19, height: 19)
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    voiceAssistantController.isContinuousConversationActive ? Color.green : Color.primary,
                    Color.secondary.opacity(0.5)
                )
                .shadow(color: isAssistantActive ? .accentColor.opacity(0.7) : .clear, radius: 3)
                .shadow(color: isAssistantActive ? .accentColor.opacity(0.4) : .clear, radius: 6)
                .animation(.easeInOut(duration: 0.5), value: isAssistantActive)
        }
    }
}

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Chat Window") {
            openWindow(id: "main")
        }
        
        Divider()
        
        Button("Quit MacAssist") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

