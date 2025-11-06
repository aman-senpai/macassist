//
//  MacAssistApp.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import SwiftUI

@main
struct MacAssistApp: App {
    // Use the App Delegate to manage the app's lifecycle and background services
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Get a reference to the single controller instance from the app delegate
    private var voiceAssistantController: VoiceAssistantController {
        appDelegate.voiceAssistantController
    }

    var body: some Scene {
        // Main window for the chat interface, which is now optional
        Window("MacAssist", id: "main") {
            ContentView()
                .environmentObject(voiceAssistantController) // Pass controller to the view
                .frame(minWidth: 380, idealWidth: 450, maxWidth: 600, minHeight: 400, idealHeight: 500, maxHeight: 800)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        // The menu bar icon and its content
        MenuBarExtra {
            MenuBarContentView() // Use a dedicated view for the menu content
        } label: {
            // Determine if the assistant is active (listening or processing) to show a glow.
            let isAssistantActive = voiceAssistantController.isRecording || voiceAssistantController.agent.isProcessing

            // The icon that appears in the menu bar.
            Image(systemName: "waveform.circle.fill")
                .resizable() // Allow frame modifications
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18) // Standard menu bar icon size
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    // Green when continuous mode is on, otherwise primary color
                    voiceAssistantController.isContinuousConversationActive ? Color.green : Color.primary,
                    // Secondary color for the inner part of the symbol
                    Color.secondary.opacity(0.5)
                )
                // Add a multi-layered shadow for a "glow" effect when active
                .shadow(color: isAssistantActive ? .accentColor.opacity(0.7) : .clear, radius: 3)
                .shadow(color: isAssistantActive ? .accentColor.opacity(0.4) : .clear, radius: 6)
                // Animate the glow effect for smooth transitions
                .animation(.easeInOut(duration: 0.5), value: isAssistantActive)
        }
    }
}

// A new, dedicated view for the MenuBarExtra content.
// This allows us to access the environment to get the openWindow action.
struct MenuBarContentView: View {
    // This environment value is available on macOS 12+ and is the compatible way to open a window.
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Chat Window") {
            // This will create the window if it doesn't exist, or bring it to the front.
            openWindow(id: "main")
        }
        
        Divider()
        
        Button("Quit MacAssist") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
