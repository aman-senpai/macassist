//
//  AppDelegate.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    @MainActor
    let voiceAssistantController = VoiceAssistantController()
    
    private var hotkeyMonitor: GlobalHotkeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the global hotkey monitor to call our controller
        hotkeyMonitor = GlobalHotkeyMonitor { [weak self] in
            print("Global hotkey pressed!")
            self?.voiceAssistantController.toggleContinuousConversation()
        }
    }
}
