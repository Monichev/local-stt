import AVFAudio
import AppKit

final class PermissionManager {
    /// Check if microphone permission is granted
    var hasMicrophonePermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// Check if accessibility permission is granted (needed for global hotkey)
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Request microphone permission
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Whether auto-paste is enabled (user preference, persisted)
    var autoPasteEnabled: Bool {
        get {
            // Default to true if key has never been set
            if UserDefaults.standard.object(forKey: Constants.autoPasteEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Constants.autoPasteEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.autoPasteEnabledKey)
        }
    }

    /// Whether auto-paste can actually be performed (enabled + has permission)
    var canAutoPaste: Bool {
        autoPasteEnabled && hasAccessibilityPermission
    }

    /// Show an alert explaining why Accessibility permission is needed for auto-paste.
    /// Returns `true` if the user chose "Grant Permission" (opens System Settings).
    @MainActor
    func showAccessibilityOnboarding() -> Bool {
        // Bring our app to front so the alert is visible (.accessory apps don't auto-activate)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Enable Auto-Paste?"
        alert.informativeText = "Local STT can automatically paste transcribed text into the active app when you use Cmd+Right Option.\n\nThis requires Accessibility permission in System Settings."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Grant Permission")
        alert.addButton(withTitle: "No Thanks")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Use system API to prompt — it correctly identifies the current process
            // and pre-adds it to the Accessibility list (user just needs to toggle it on)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return true
        }
        return false
    }

    /// Open System Settings to the Accessibility pane
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Open System Settings to the Microphone pane
    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
