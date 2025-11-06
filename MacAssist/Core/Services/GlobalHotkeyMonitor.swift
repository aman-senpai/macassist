//
//  GlobalHotkeyMonitor.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import Foundation
import Carbon.HIToolbox

final class GlobalHotkeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private let onHotkeyPressed: () -> Void

    init(onHotkeyPressed: @escaping () -> Void) {
        self.onHotkeyPressed = onHotkeyPressed
        register()
    }

    deinit {
        unregister()
    }

    private func register() {
        let hotKeyID = EventHotKeyID(signature: FourCharCode("mact".utf16.reduce(0, {$0 << 8 + FourCharCode($1)})), id: 1)
        
        // Using Control + Space
        let keyCode = UInt32(kVK_Space)
        let modifiers = UInt32(controlKey)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            let this = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userData!).takeUnretainedValue()
            this.onHotkeyPressed()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("Error: Unable to register hotkey: \(status)")
        } else {
            print("Successfully registered global hotkey: Control+Space")
        }
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
