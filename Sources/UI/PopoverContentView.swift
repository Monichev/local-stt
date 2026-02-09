import SwiftUI
import AppKit

struct PopoverContentView: View {
    let stateManager: StateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch stateManager.state {
            case .idle:
                IdleView()
            case .recording:
                RecordingView()
            case .transcribing:
                TranscribingView()
            case .result(let text, let language):
                ResultView(text: text, language: language, stateManager: stateManager)
            case .error(let message):
                ErrorView(message: message, stateManager: stateManager)
            }
        }
        .padding()
        .frame(width: Constants.popoverWidth, alignment: .leading)
    }
}

// MARK: - Idle View

struct IdleView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
            Text("Hold Right Option to record")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Recording View

struct RecordingView: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }

            Text("Recording...")
                .font(.callout)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Transcribing View

struct TranscribingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Transcribing...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Result View

struct ResultView: View {
    let text: String
    let language: String
    let stateManager: StateManager
    @State private var copied = false

    private var languageDisplayName: String {
        Locale.current.localizedString(forLanguageCode: language) ?? language
    }

    /// Max height for the text area: 1/3 of screen minus chrome (padding, toolbar, divider ≈ 80pt)
    private var maxTextHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return max(100, screenHeight / 3 - 80)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: maxTextHeight)

            Divider()

            HStack {
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy")
                    }
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(text == "No speech detected.")

                Spacer()

                Text("\(languageDisplayName) · \(text.split(separator: " ").count) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button("Dismiss") {
                    stateManager.state = .idle
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.copyConfirmationDuration) {
            copied = false
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let stateManager: StateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Error")
                    .font(.callout)
                    .fontWeight(.semibold)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Dismiss") {
                stateManager.state = .idle
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
    }
}
