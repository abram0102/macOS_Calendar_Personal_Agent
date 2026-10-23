import AppKit
import SwiftUI

// MARK: - Window

final class DeskWindow: NSWindow {
    override var canBecomeKey: Bool { true }      // no title bar, but it still has to accept typing
    override var canBecomeMain: Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let notes = NotesStore()
    private lazy var store = CalendarStore()

    private var window: DeskWindow!
    private var statusItem: NSStatusItem!
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)     // no Dock icon

        buildWindow()
        buildStatusItem()

        settings.onChange = { [weak self] in self?.applyWindowStyle() }
        applyWindowStyle()

        installFocusHandling()

        store.requestAccess()

        // re-group the days when the date rolls over
        scheduleMidnightRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notes.saveNow()
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: Leaving editing state

    /// Clicking anywhere outside a text field (or pressing Esc, or losing key focus) ends editing and saves.
    private func installFocusHandling() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self, let win = event.window, win === self.window else { return event }
            let hit = win.contentView?.hitTest(event.locationInWindow)
            if !self.isTextInput(hit) { self.endEditing() }
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }   // Esc
            guard let win = event.window, win === self.window else { return event }
            if win.firstResponder is NSText || win.firstResponder is NSTextView {
                self.endEditing()
                return nil                                              // swallow this Esc
            }
            return event
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main) {
                [weak self] _ in self?.endEditing()
            }
    }

    /// Whether the hit view is a text control (subviews of an NSTextView count too)
    private func isTextInput(_ view: NSView?) -> Bool {
        var node = view
        while let v = node {
            if v is NSTextView || v is NSTextField { return true }
            node = v.superview
        }
        return false
    }

    private func endEditing() {
        guard let win = window, win.firstResponder is NSText || win.firstResponder is NSTextView
        else { return }
        win.makeFirstResponder(nil)
        NotificationCenter.default.post(name: .deskEndEditing, object: nil)
        notes.saveNow()
    }

    // MARK: Window

    private func buildWindow() {
        let root = DeskView(store: store, notes: notes, settings: settings)
        let hosting = NSHostingView(rootView: root)

        let defaultFrame = NSRect(x: 0, y: 0, width: 360, height: 620)
        window = DeskWindow(contentRect: defaultFrame,
                            styleMask: [.borderless, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.minSize = NSSize(width: 280, height: 220)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DeskWindowFrame")

        if window.setFrameUsingName("DeskWindowFrame") == false {
            // First launch: park it in the top-right corner of the main screen
            if let screen = NSScreen.main {
                let v = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: v.maxX - defaultFrame.width - 24,
                                              y: v.maxY - defaultFrame.height - 24))
            }
        }
        window.orderFrontRegardless()
    }

    private func applyWindowStyle() {
        window.level = settings.layer.level
        window.alphaValue = CGFloat(settings.opacity)
        window.isMovable = !settings.lockPosition
        window.styleMask = settings.lockPosition
            ? [.borderless, .fullSizeContentView]
            : [.borderless, .resizable, .fullSizeContentView]
        window.orderFrontRegardless()
        rebuildStatusMenu()
    }

    // MARK: Status bar item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "calendar", accessibilityDescription: "CalendarDesk")
        statusItem.button?.image?.isTemplate = true
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(title: window.isVisible ? "隐藏窗口" : "显示窗口",
                                action: #selector(toggleWindow), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let refresh = NSMenuItem(title: "刷新日程", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "显示范围", action: nil, keyEquivalent: ""))
        for r in DeskRange.allCases {
            let item = NSMenuItem(title: "   " + r.title,
                                  action: #selector(pickRange(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = r.rawValue
            item.state = (store.range == r) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "窗口层级", action: nil, keyEquivalent: ""))
        for l in WindowLayer.allCases {
            let item = NSMenuItem(title: "   " + l.title,
                                  action: #selector(pickLayer(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = l.rawValue
            item.state = (settings.layer == l) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let center = NSMenuItem(title: "把窗口放回屏幕右上角",
                                action: #selector(resetPosition), keyEquivalent: "")
        center.target = self
        menu.addItem(center)

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func toggleWindow() {
        if window.isVisible { window.orderOut(nil) }
        else {
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
        rebuildStatusMenu()
    }

    @objc private func refresh() { store.reload() }

    @objc private func pickRange(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let r = DeskRange(rawValue: raw) else { return }
        store.range = r
        rebuildStatusMenu()
    }

    @objc private func pickLayer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let l = WindowLayer(rawValue: raw) else { return }
        settings.layer = l
    }

    @objc private func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        var f = window.frame
        f.origin = NSPoint(x: v.maxX - f.width - 24, y: v.maxY - f.height - 24)
        window.setFrame(f, display: true, animate: true)
        window.orderFrontRegardless()
    }

    @objc private func quit() {
        notes.saveNow()
        NSApp.terminate(nil)
    }

    // MARK: Midnight refresh

    private func scheduleMidnightRefresh() {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .day, value: 1,
                                  to: cal.startOfDay(for: Date())) else { return }
        let timer = Timer(fireAt: next.addingTimeInterval(5), interval: 0, target: self,
                          selector: #selector(midnightFired), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func midnightFired() {
        store.reload()
        scheduleMidnightRefresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
