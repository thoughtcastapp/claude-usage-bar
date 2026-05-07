import AppKit
import Combine
import SwiftUI
import os

private let kClaudeBundleID = "com.anthropic.claudefordesktop"
private let kClaudeAppPath = "/Applications/Claude.app"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let store = UsageStore()
    private let log = Logger(subsystem: "com.irysagency.claudeusagebar", category: "AppDelegate")
    private var workspaceObservers: [NSObjectProtocol] = []

    private var popover: NSPopover?
    private var rightClickMenu: NSMenu?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading

        configureStatusItemButton()
        installCombineSubscriptions()
        installWorkspaceObservers()

        applyClaudeRunningState(isRunning: claudeIsRunning())
    }

    func applicationWillTerminate(_ notification: Notification) {
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
        store.stopRefreshing()
    }

    // MARK: - Status item wiring

    private func configureStatusItemButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemAction(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showRightClickMenu()
        } else {
            togglePopover()
        }
    }

    private func installCombineSubscriptions() {
        // Re-render the status item icon/title whenever published state changes. We collapse all
        // the relevant publishers into a single sink to keep the wiring simple. Using
        // `objectWillChange` would also work but `merge3` style is more explicit about deps.
        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.renderStatusItem() }
            }
            .store(in: &cancellables)

        store.$error
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.renderStatusItem() }
            }
            .store(in: &cancellables)

        store.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.renderStatusItem() }
            }
            .store(in: &cancellables)

        store.$claudeIsRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.renderStatusItem() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Workspace observation

    private func installWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        let launchToken = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == kClaudeBundleID {
                MainActor.assumeIsolated {
                    self.applyClaudeRunningState(isRunning: true)
                }
            }
        }
        workspaceObservers.append(launchToken)

        let terminateToken = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == kClaudeBundleID {
                MainActor.assumeIsolated {
                    self.applyClaudeRunningState(isRunning: false)
                }
            }
        }
        workspaceObservers.append(terminateToken)
    }

    private func claudeIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == kClaudeBundleID }
    }

    private func applyClaudeRunningState(isRunning: Bool) {
        statusItem.isVisible = isRunning
        store.setClaudeRunning(isRunning)
        if isRunning {
            store.startRefreshing()
        } else {
            store.stopRefreshing()
        }
    }

    // MARK: - Status item rendering

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }

        if let err = store.error, store.snapshot == nil {
            applySymbol(button: button, name: "exclamationmark.triangle.fill", tint: .systemRed)
            button.title = " ⚠"
            button.toolTip = err
            return
        }

        guard let snap = store.snapshot,
              let five = snap.usage.five_hour,
              let pct = five.utilization else {
            applySymbol(button: button, name: "circle.dashed", tint: .secondaryLabelColor)
            button.title = " …"
            button.toolTip = store.isLoading ? "Chargement…" : "En attente de données"
            return
        }

        let symbolName = Formatting.iconName(forPercent: pct)
        let tint = Formatting.tintColor(forPercent: pct)
        applySymbol(button: button, name: symbolName, tint: tint)
        button.title = " " + Formatting.percent(pct)
        button.toolTip = "Claude — Session 5h: \(Formatting.percent(pct)) — \(Formatting.resetLine(from: five.resetsAtDate))"
    }

    private func applySymbol(button: NSStatusBarButton, name: String, tint: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.isTemplate = false
            button.image = image.tinted(with: tint)
        } else {
            button.image = nil
        }
    }

    // MARK: - Popover

    private func ensurePopover() -> NSPopover {
        if let popover { return popover }
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true

        let root = ContentView(
            store: store,
            onRefresh: { [weak self] in self?.refreshNow() },
            onLaunchClaude: { [weak self] in self?.launchClaude() },
            onQuit: { [weak self] in self?.quit() }
        )
        let host = NSHostingController(rootView: root)
        // Both options together let SwiftUI's intrinsic size drive the popover's `contentSize`.
        // Without `.preferredContentSize` the popover sometimes picks an undersized initial frame
        // and clips content (especially with French strings longer than English ones).
        host.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        p.contentViewController = host
        popover = p
        return p
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        let p = ensurePopover()
        if p.isShown {
            p.performClose(nil)
        } else {
            // Activate so keyboard input (e.g. Esc to close) routes to our app even when launched
            // as an .accessory agent.
            NSApp.activate(ignoringOtherApps: true)
            // Nudge a fresh fetch on open so users always see current data, bypassing any backoff.
            store.refresh(forceImmediate: true)
            p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Right-click escape hatch

    private func showRightClickMenu() {
        if rightClickMenu == nil {
            let menu = NSMenu()
            menu.autoenablesItems = false
            let item = NSMenuItem(title: "Quitter", action: #selector(quit), keyEquivalent: "q")
            item.target = self
            item.keyEquivalentModifierMask = [.command]
            menu.addItem(item)
            rightClickMenu = menu
        }
        // Temporarily attach the menu so AppKit pops it directly under the status item, then
        // detach so left-click goes back to our action selector.
        statusItem.menu = rightClickMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        // User-triggered: bypass any active backoff window.
        store.refresh(forceImmediate: true)
    }

    @objc private func launchClaude() {
        let url = URL(fileURLWithPath: kClaudeAppPath)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { [weak self] _, error in
            if let error {
                self?.log.error("Failed to launch Claude: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let copy = NSImage(size: self.size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        copy.isTemplate = false
        return copy
    }
}
