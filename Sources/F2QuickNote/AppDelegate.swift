import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let clipboardTracker = ClipboardTracker()
    private var hotKeyManager: HotKeyManager?
    private var loginItemMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        clipboardTracker.start()

        let manager = HotKeyManager { [weak self] in
            self?.captureNote()
        }
        hotKeyManager = manager
        let registered = manager.registerF2()
        NSLog("F2QuickNote: hotkey registered = %@", registered ? "true" : "false")
        if !registered {
            showError(title: "Could not register F2",
                      message: "Another app may already own the F2 hotkey. Quit it or change its binding, then relaunch F2 Quick Note.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardTracker.stop()
        hotKeyManager?.unregister()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text.badge.plus",
                                   accessibilityDescription: "F2 Quick Note")
        }

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "New Note from Clipboard",
                                     action: #selector(captureFromMenu), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Start at Login",
                                   action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)
        loginItemMenuItem = loginItem
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit F2 Quick Note",
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func captureFromMenu() {
        captureNote()
    }

    private func captureNote() {
        let fresh = clipboardTracker.isFresh(within: NoteCapture.freshnessWindow)
        do {
            try NoteCapture.capture(fresh: fresh)
        } catch NoteCapture.CaptureError.appleScript(let message, let code) {
            // -1743: user denied Apple Events permission
            if code == -1743 {
                showError(title: "Notes automation not allowed",
                          message: "Open System Settings → Privacy & Security → Automation and allow \"F2 Quick Note\" to control \"Notes\".")
            } else {
                showError(title: "Could not create note",
                          message: "\(message) (error \(code))")
            }
        } catch {
            showError(title: "Could not create note", message: "\(error)")
        }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showError(title: "Could not update login item", message: "\(error.localizedDescription)")
        }
        loginItemMenuItem?.state = (service.status == .enabled) ? .on : .off
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
