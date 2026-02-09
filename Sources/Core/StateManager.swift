import Foundation

@MainActor
@Observable
final class StateManager {
    enum AppState: Equatable {
        case idle
        case recording
        case transcribing
        case result(text: String, language: String)
        case error(message: String)
    }

    var state: AppState = .idle

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = state { return true }
        return false
    }
}
