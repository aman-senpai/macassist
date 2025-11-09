//
//  AppDelegate.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // The single, shared instance of HistoryManager
    @MainActor
    let sharedHistoryManager: HistoryManager
    
    @MainActor
    let voiceAssistantController: VoiceAssistantController
    
    private var hotkeyMonitor: GlobalHotkeyMonitor?
    
    override init() {
        // Initialize the shared HistoryManager first
        self.sharedHistoryManager = HistoryManager()
        // Then pass it to the VoiceAssistantController
        self.voiceAssistantController = VoiceAssistantController(historyManager: sharedHistoryManager)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the global hotkey monitor to call our controller
        hotkeyMonitor = GlobalHotkeyMonitor { [weak self] in
            print("Global hotkey pressed!")
            self?.voiceAssistantController.toggleContinuousConversation()
        }
    }
}

