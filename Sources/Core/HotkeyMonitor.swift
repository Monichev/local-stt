import AppKit
import Carbon

/// Monitors the Right Option key for three gestures:
///   - Long press (hold ≥ threshold) → start/stop recording
///   - Single tap → copy + dismiss
///   - Double tap → dismiss only
final class HotkeyMonitor {
    private let onRecordingStarted: () -> Void
    private let onRecordingStopped: (_ shouldAutoPaste: Bool) -> Void
    private let onDismiss: () -> Void
    private let onCopy: () -> Void

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private enum State {
        case idle
        case waitingForHold       // key down, hold timer pending
        case recording            // hold threshold passed, recording
        case waitingForDoubleTap  // first tap done, waiting for second
        case ignoringRelease      // double-tap fired, waiting for key up
    }

    private var state: State = .idle
    private var holdTimer: DispatchWorkItem?
    private var doubleTapTimer: DispatchWorkItem?
    private var commandHeldAtStart = false

    private let holdThreshold: TimeInterval = 0.3
    private let doubleTapWindow: TimeInterval = 0.3

    init(
        onRecordingStarted: @escaping () -> Void,
        onRecordingStopped: @escaping (_ shouldAutoPaste: Bool) -> Void,
        onDismiss: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) {
        self.onRecordingStarted = onRecordingStarted
        self.onRecordingStopped = onRecordingStopped
        self.onDismiss = onDismiss
        self.onCopy = onCopy
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        cancelTimers()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let rightOptionFlag: UInt = 0x40 // NX_DEVICERALTKEYMASK
        let isRightOptionDown = (event.modifierFlags.rawValue & rightOptionFlag) != 0

        if isRightOptionDown {
            handleKeyDown()
        } else {
            handleKeyUp()
        }
    }

    private func handleKeyDown() {
        switch state {
        case .idle:
            // Start hold timer — if key stays down past threshold, begin recording
            state = .waitingForHold
            let timer = DispatchWorkItem { [weak self] in
                guard let self, self.state == .waitingForHold else { return }
                self.state = .recording
                self.commandHeldAtStart = NSEvent.modifierFlags.contains(.command)
                self.onRecordingStarted()
            }
            holdTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: timer)

        case .waitingForDoubleTap:
            // Second tap arrived — double tap detected → dismiss only
            cancelTimers()
            state = .ignoringRelease
            onDismiss()

        default:
            break
        }
    }

    private func handleKeyUp() {
        switch state {
        case .waitingForHold:
            // Released before hold threshold — this is a tap
            cancelTimers()
            state = .waitingForDoubleTap
            let timer = DispatchWorkItem { [weak self] in
                guard let self, self.state == .waitingForDoubleTap else { return }
                self.state = .idle
                self.onCopy()
            }
            doubleTapTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: timer)

        case .recording:
            // Release after hold — stop recording
            let autoPaste = commandHeldAtStart
            state = .idle
            cancelTimers()
            commandHeldAtStart = false
            onRecordingStopped(autoPaste)

        case .ignoringRelease:
            // Release after double-tap action already fired
            state = .idle

        default:
            break
        }
    }

    private func cancelTimers() {
        holdTimer?.cancel()
        holdTimer = nil
        doubleTapTimer?.cancel()
        doubleTapTimer = nil
    }
}
