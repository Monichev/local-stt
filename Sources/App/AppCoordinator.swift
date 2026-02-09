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
        statusBarController = StatusBarController(stateManager: stateManager, transcriptionEngine: transcriptionEngine)
        statusBarController?.onModelSelected = { [weak self] modelName in
            self?.switchModel(to: modelName)
        }
        statusBarController?.setup()

        // Set up global hotkey
        hotkeyMonitor = HotkeyMonitor(
            onRecordingStarted: { [weak self] in
                self?.startRecording()
            },
            onRecordingStopped: { [weak self] in
                self?.stopRecordingAndTranscribe()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onCopy: { [weak self] in
                self?.copyResult()
            }
        )
        hotkeyMonitor?.start()

        // Request microphone permission on launch, then load model
        Task {
            let granted = await permissionManager.requestMicrophonePermission()
            print("[LocalSTT] Microphone permission: \(granted ? "granted" : "denied")")
            await loadModel()
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

    private func stopRecordingAndTranscribe() {
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
                    if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        stateManager.state = .result(text: "No speech detected.", language: result.language)
                    } else {
                        stateManager.state = .result(text: result.text, language: result.language)
                    }
                    statusBarController?.showPopover()
                }
            } catch {
                await MainActor.run {
                    stateManager.state = .error(message: "Transcription failed: \(error.localizedDescription)")
                    statusBarController?.showPopover()
                }
            }
        }
    }
}
