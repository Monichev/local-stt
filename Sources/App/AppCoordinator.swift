import AppKit
import Combine

@MainActor
final class AppCoordinator {
    let stateManager = StateManager()
    let audioRecorder = AudioRecorder()
    let transcriptionEngine = TranscriptionEngine()
    let permissionManager = PermissionManager()

    private var statusBarController: StatusBarController?
    private var hotkeyMonitor: HotkeyMonitor?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        // Set up the menubar
        statusBarController = StatusBarController(stateManager: stateManager, transcriptionEngine: transcriptionEngine, permissionManager: permissionManager)
        statusBarController?.onModelSelected = { [weak self] modelName in
            self?.switchModel(to: modelName)
        }
        statusBarController?.setup()

        // Set up global hotkey
        hotkeyMonitor = HotkeyMonitor(
            onRecordingStarted: { [weak self] in
                self?.startRecording()
            },
            onRecordingStopped: { [weak self] shouldAutoPaste in
                self?.stopRecordingAndTranscribe(shouldAutoPaste: shouldAutoPaste)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onCopy: { [weak self] in
                self?.copyResult()
            }
        )
        hotkeyMonitor?.start()

        // Request microphone permission on launch, then load model, then check accessibility
        Task {
            let granted = await permissionManager.requestMicrophonePermission()
            print("[LocalSTT] Microphone permission: \(granted ? "granted" : "denied")")
            await loadModel()
            checkAccessibilityOnboarding()
        }
    }

    func stop() {
        hotkeyMonitor?.stop()
    }

    private func loadModel(name: String = Constants.Model.defaultName) async {
        do {
            stateManager.state = .idle
            try await transcriptionEngine.loadModel(modelName: name)
            print("[LocalSTT] Model '\(name)' loaded successfully")
        } catch {
            print("[LocalSTT] Failed to load model '\(name)': \(error)")
            stateManager.state = .error(message: "Failed to load model '\(name)': \(error.localizedDescription)")
        }
    }

    private func switchModel(to modelName: String) {
        guard transcriptionEngine.currentModelName != modelName else { return }
        stateManager.state = .transcribing // reuse as "loading" indicator
        statusBarController?.showPopover()
        Task {
            await loadModel(name: modelName)
        }
    }

    private func dismiss() {
        statusBarController?.closePopover()
        stateManager.state = .idle
    }

    private func copyResult() {
        if case .result(let text, _) = stateManager.state,
           text != "No speech detected."
        {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        dismiss()
    }

    private func startRecording() {
        // Allow starting a new recording from idle, result, or error states
        switch stateManager.state {
        case .idle, .result, .error:
            break
        case .recording, .transcribing:
            return // Already busy
        }

        guard permissionManager.hasMicrophonePermission else {
            stateManager.state = .error(message: "Microphone permission required. Check System Settings > Privacy & Security > Microphone.")
            statusBarController?.showPopover()
            return
        }

        do {
            statusBarController?.closePopover()
            try audioRecorder.startRecording()
            stateManager.state = .recording
            statusBarController?.showPopover()
        } catch {
            stateManager.state = .error(message: "Failed to start recording: \(error.localizedDescription)")
            statusBarController?.showPopover()
        }
    }

    private func stopRecordingAndTranscribe(shouldAutoPaste: Bool = false) {
        guard case .recording = stateManager.state else { return }

        let audioBuffer = audioRecorder.stopRecording()

        guard !audioBuffer.isEmpty else {
            stateManager.state = .idle
            return
        }

        stateManager.state = .transcribing

        Task {
            do {
                let result = try await transcriptionEngine.transcribe(audioBuffer: audioBuffer)
                await MainActor.run {
                    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("[LocalSTT] shouldAutoPaste=\(shouldAutoPaste) autoPasteEnabled=\(self.permissionManager.autoPasteEnabled) hasAccessibility=\(self.permissionManager.hasAccessibilityPermission) canAutoPaste=\(self.permissionManager.canAutoPaste)")
                    if text.isEmpty {
                        stateManager.state = .result(text: "No speech detected.", language: result.language)
                        statusBarController?.showPopover()
                    } else if shouldAutoPaste && self.permissionManager.canAutoPaste {
                        stateManager.state = .result(text: result.text, language: result.language)
                        pasteToFocusedApp(result.text)
                    } else {
                        stateManager.state = .result(text: result.text, language: result.language)
                        statusBarController?.showPopover()
                    }
                }
            } catch {
                await MainActor.run {
                    stateManager.state = .error(message: "Transcription failed: \(error.localizedDescription)")
                    statusBarController?.showPopover()
                }
            }
        }
    }

    private func checkAccessibilityOnboarding() {
        guard permissionManager.autoPasteEnabled, !permissionManager.hasAccessibilityPermission else { return }
        let granted = permissionManager.showAccessibilityOnboarding()
        if !granted {
            permissionManager.autoPasteEnabled = false
            statusBarController?.updateAutoPasteMenuItem()
        }
    }

    private func pasteToFocusedApp(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusBarController?.closePopover()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)
            let vKeyCode: UInt16 = 0x09  // kVK_ANSI_V
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
