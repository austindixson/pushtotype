import AppKit
import SwiftUI
import Combine

/// Hosting view that accepts the first click (no “activate then click again”).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

/// Menu-bar status item + keyable floating panel.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hosting: FirstMouseHostingView<AnyView>?
    private var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private let panelWidth: CGFloat = 372
    private let panelMaxHeight: CGFloat = 620

    func setup(appState: AppState) {
        self.appState = appState

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "PushToType")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "PushToType — hold Right ⌥ to dictate"
        }
        statusItem = item

        // Only refresh icon on state changes — do NOT resize/rebuild panel on every
        // objectWillChange (that re-laid-out the view mid-click and snapped selection back).
        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        refreshIcon()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let type = NSApp.currentEvent?.type
        if type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Start Dictation", action: #selector(menuStart), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Last", action: #selector(menuCopy), keyEquivalent: "")
        menu.addItem(withTitle: "Paste Last", action: #selector(menuPaste), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Open Panel…", action: #selector(menuOpenPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Advanced Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit PushToType", action: #selector(menuQuit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    @objc private func menuStart() { appState?.startDictation() }
    @objc private func menuCopy() { appState?.copyLast() }
    @objc private func menuPaste() { appState?.pasteLast() }
    @objc private func menuOpenPanel() { showPanel() }
    @objc private func menuSettings() {
        hidePanel()
        if let appState { SettingsWindowController.shared.show(appState: appState) }
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let appState else { return }
        if panel == nil {
            buildPanel(appState: appState)
        }
        // Always refresh root so selection state is current
        hosting?.rootView = AnyView(
            MenuBarView()
                .environmentObject(appState)
                .frame(width: panelWidth)
        )

        guard let panel, let button = statusItem?.button else { return }
        resizePanelToFit()
        positionPanel(under: button)
        // Key window so buttons / tabs / pickers get first-click selection
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(hosting)
        installClickMonitors()
    }

    func hidePanel() {
        panel?.orderOut(nil)
        removeClickMonitors()
    }

    private func installClickMonitors() {
        removeClickMonitors()
        // Dismiss when clicking outside — use local+global so it works while we are key
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            self?.dismissIfOutside(e)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            self?.dismissIfOutside(e)
            return e
        }
    }

    private func removeClickMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }

    private func dismissIfOutside(_ event: NSEvent) {
        guard let panel, panel.isVisible else { return }
        let loc = NSEvent.mouseLocation
        if panel.frame.contains(loc) { return }
        if let button = statusItem?.button, let win = button.window {
            let br = win.convertToScreen(button.convert(button.bounds, to: nil))
            if br.contains(loc) { return }
        }
        // Don't steal the click that is meant for a card — only dismiss truly outside
        hidePanel()
    }

    private func positionPanel(under button: NSStatusBarButton) {
        guard let panel, let window = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = window.convertToScreen(buttonRect)
        let panelSize = panel.frame.size
        var origin = NSPoint(
            x: screenRect.midX - panelSize.width / 2,
            y: screenRect.minY - panelSize.height - 8
        )
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panelSize.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panelSize.height - 8)
        }
        panel.setFrameOrigin(origin)
    }

    private func buildPanel(appState: AppState) {
        let root = AnyView(
            MenuBarView()
                .environmentObject(appState)
                .frame(width: panelWidth)
        )
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]
        let height = min(max(host.fittingSize.height, 360), panelMaxHeight)
        host.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)

        // IMPORTANT: do NOT use .nonactivatingPanel — it breaks first-click on buttons/tabs/cards
        let p = NSPanel(
            contentRect: host.frame,
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "PushToType"
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = host
        // Allow becoming key so SwiftUI selection works on first click
        p.becomesKeyOnlyIfNeeded = false

        hosting = host
        panel = p
    }

    private func resizePanelToFit() {
        guard let panel, let hosting, panel.isVisible || panel == self.panel else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let height = min(max(fitting.height, 360), panelMaxHeight)
        let width = panelWidth + 4
        var frame = panel.frame
        let oldMaxY = frame.maxY
        frame.size = NSSize(width: width, height: height + 28) // titlebar chrome
        frame.origin.y = oldMaxY - frame.size.height
        panel.setFrame(frame, display: true)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: panelWidth, height: height))
    }

    private func refreshIcon() {
        guard let button = statusItem?.button, let appState else { return }
        let name: String
        if appState.isEnhancing {
            name = "brain.head.profile"
        } else if appState.isTranscribing {
            name = "waveform"
        } else if appState.isRecording {
            name = "mic.fill"
        } else {
            name = "mic"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "PushToType")
        image?.isTemplate = true
        button.image = image
        button.toolTip = appState.statusText
    }

    // NSWindowDelegate
    func windowDidResignKey(_ notification: Notification) {
        // Keep panel open when interacting; only hide on outside click monitor
    }

    func windowWillClose(_ notification: Notification) {
        hidePanel()
    }
}
