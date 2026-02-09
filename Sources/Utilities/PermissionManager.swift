import AVFoundation
import AppKit

final class PermissionManager {
    /// Check if microphone permission is granted
    var hasMicrophonePermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Check if accessibility permission is granted (needed for global hotkey)
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Request microphone permission
    func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
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
