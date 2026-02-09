import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusMenu: NSMenu?
    private let stateManager: StateManager
    private let transcriptionEngine: TranscriptionEngine
    private let permissionManager: PermissionManager
    private var eventMonitor: Any?
    private var observation: Any?
    private var translateMenuItem: NSMenuItem?
    private var autoPasteMenuItem: NSMenuItem?
    private var modelMenuItems: [String: NSMenuItem] = [:]

    /// Called when the user picks a different model from the menu
    var onModelSelected: ((String) -> Void)?

    init(stateManager: StateManager, transcriptionEngine: TranscriptionEngine, permissionManager: PermissionManager) {
        self.stateManager = stateManager
        self.transcriptionEngine = transcriptionEngine
        self.permissionManager = permissionManager
    }

    func setup() {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: Constants.appName)
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.animates = false
        updatePopoverContent()

        // Build the right-click menu
        let menu = NSMenu()

        let translateItem = NSMenuItem(title: "Translate to English", action: #selector(toggleTranslate(_:)), keyEquivalent: "")
        translateItem.target = self
        translateItem.state = transcriptionEngine.translateToEnglish ? .on : .off
        menu.addItem(translateItem)
        self.translateMenuItem = translateItem

        let autoPasteItem = NSMenuItem(title: "Auto-Paste", action: #selector(toggleAutoPaste(_:)), keyEquivalent: "")
        autoPasteItem.target = self
        autoPasteItem.state = permissionManager.autoPasteEnabled ? .on : .off
        menu.addItem(autoPasteItem)
        self.autoPasteMenuItem = autoPasteItem

        // Model submenu
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for model in Constants.Model.available {
            let item = NSMenuItem(title: model.name, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.id
            item.state = model.id == transcriptionEngine.currentModelName ? .on : .off
            modelMenu.addItem(item)
            modelMenuItems[model.id] = item
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit \(Constants.appName)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        self.statusMenu = menu

        // Observe state changes to update the icon
        observeState()
    }

    private func observeState() {
        observation = withObservationTracking {
            _ = stateManager.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                // Close and re-show popover so it re-anchors to the correct position
                if self?.popover?.isShown == true {
                    self?.closePopover()
                    self?.showPopover()
                }
                self?.observeState()
            }
        }
    }

    func showPopover() {
        guard let button = statusItem?.button, let popover else { return }

        // Refresh the content so the hosting controller picks up current state and resizes
        updatePopoverContent()

        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        // Monitor for clicks outside to close
        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func updatePopoverContent() {
        let contentView = PopoverContentView(stateManager: stateManager)
        let hostingController = NSHostingController(rootView: contentView)
        // Let SwiftUI compute intrinsic height (fixedSize on ScrollView ensures it reports content size)
        let intrinsic = hostingController.sizeThatFits(in: NSSize(width: Constants.popoverWidth, height: 10000))
        // Cap at 1/3 of screen height
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maxHeight = max(Constants.popoverMinHeight, screenHeight / 3)
        let size = NSSize(width: intrinsic.width, height: min(intrinsic.height, maxHeight))
        hostingController.preferredContentSize = size
        popover?.contentSize = size
        popover?.contentViewController = hostingController
    }

    func closePopover() {
        popover?.performClose(nil)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            // Right-click: show menu
            closePopover()
            if let statusMenu {
                statusItem?.menu = statusMenu
                statusItem?.button?.performClick(nil)
                statusItem?.menu = nil // Reset so left-click works again
            }
        } else {
            // Left-click: toggle popover
            togglePopover()
        }
    }

    private func togglePopover() {
        if let popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    @objc private func toggleTranslate(_ sender: NSMenuItem) {
        transcriptionEngine.translateToEnglish.toggle()
        sender.state = transcriptionEngine.translateToEnglish ? .on : .off
    }

    @objc private func toggleAutoPaste(_ sender: NSMenuItem) {
        if permissionManager.autoPasteEnabled {
            // Turning off
            permissionManager.autoPasteEnabled = false
        } else {
            // Turning on — check if we have permission
            permissionManager.autoPasteEnabled = true
            if !permissionManager.hasAccessibilityPermission {
                let granted = permissionManager.showAccessibilityOnboarding()
                if !granted {
                    permissionManager.autoPasteEnabled = false
                }
            }
        }
        sender.state = permissionManager.autoPasteEnabled ? .on : .off
    }

    /// Update the auto-paste menu item state (called from AppCoordinator after onboarding)
    func updateAutoPasteMenuItem() {
        autoPasteMenuItem?.state = permissionManager.autoPasteEnabled ? .on : .off
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String,
              modelId != transcriptionEngine.currentModelName else { return }

        // Update checkmarks
        for (id, item) in modelMenuItems {
            item.state = id == modelId ? .on : .off
        }

        onModelSelected?(modelId)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func updateIcon() {
        let symbolName: String
        switch stateManager.state {
        case .idle:
            symbolName = "mic"
        case .recording:
            symbolName = "mic.fill"
        case .transcribing:
            symbolName = "ellipsis.circle"
        case .result:
            symbolName = "checkmark.circle.fill"
        case .error:
            symbolName = "exclamationmark.triangle"
        }

        statusItem?.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "\(Constants.appName) - \(stateManager.state)"
        )
    }
}
