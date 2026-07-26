import Cocoa
import Carbon

@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    private var hotKeyRef: EventHotKeyRef?

    func register() {
        let hotKeyID = EventHotKeyID(signature: OSType(fourCharCode("LCK1")), id: 1)
        
        // 37 is 'L', cmdKey is 256, optionKey is 2048
        // Carbon modifier flags: cmdKey = 1 << 8, optionKey = 1 << 11
        let modifiers = UInt32(cmdKey | optionKey)
        let keyCode = UInt32(37) // kVK_ANSI_L
        
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            print("Failed to register global hotkey")
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            // Handle the hotkey
            Task { @MainActor in
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.lockScreen()
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}

func fourCharCode(_ string: String) -> Int {
    var result: Int = 0
    if let data = string.data(using: .macOSRoman) {
        for byte in data {
            result = (result << 8) + Int(byte)
        }
    }
    return result
}
