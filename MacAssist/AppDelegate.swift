//
//  AppDelegate.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // The single source of truth for all voice and agent logic
    @MainActor
    let voiceAssistantController = VoiceAssistantController()
    
    private var hotkeyMonitor: GlobalHotkeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the global hotkey monitor to call our controller
        hotkeyMonitor = GlobalHotkeyMonitor { [weak self] in
            print("Global hotkey pressed!")
            // The line that brought the app to the front has been removed.
            // The assistant will now activate in the background without stealing focus.
            self?.voiceAssistantController.toggleContinuousConversation()
        }
    }
}
