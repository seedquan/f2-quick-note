import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let clipboardTracker = ClipboardTracker()
    private let notesSearchController = AppleNotesSearchController()
    private var hotKeyManager: HotKeyManager?
    private var loginItemMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NoteCapture.cleanUpStaleTemporaryFiles()
        setUpStatusItem()
        clipboardTracker.start()

        let manager = HotKeyManager(
            f2Callback: { [weak self] in self?.captureNote() },
            commandF2Callback: { [weak self] in self?.searchNotes() }
        )
        hotKeyManager = manager
        let registration = manager.registerHotKeys()
        NSLog(
            "F2QuickNote: hotkeys registered; F2 = %@, Command-F2 = %@",
            registration.f2 ? "true" : "false",
            registration.commandF2 ? "true" : "false"
        )
        if !registration.f2 {
            showError(title: "Could not register F2",
                      message: "Another app may already own the F2 hotkey. Quit it or change its binding, then relaunch F2 Quick Note.")
        }
        if !registration.commandF2 {
            showError(title: "Could not register Command-F2",
                      message: "Another app may already own the Command-F2 hotkey. Quit it or change its binding, then relaunch F2 Quick Note.")
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

        let searchItem = NSMenuItem(title: "Search Apple Notes (⌘F2)",
                                    action: #selector(searchFromMenu), keyEquivalent: "")
        searchItem.target = self
        menu.addItem(searchItem)
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

    @objc private func searchFromMenu() {
        searchNotes()
    }

    private func searchNotes() {
        notesSearchController.openAndFocusSearch { [weak self] result in
            switch result {
            case .focused:
                break
            case .accessibilityPermissionRequired:
                self?.showError(
                    title: "Accessibility permission needed",
                    message: "Allow \"F2 Quick Note\" in System Settings → Privacy & Security → Accessibility, then press Command-F2 again."
                )
            case .notesUnavailable:
                self?.showError(
                    title: "Could not open Apple Notes",
                    message: "Apple Notes could not be found or launched."
                )
            case .searchFieldNotFound:
                self?.showError(
                    title: "Could not focus Notes search",
                    message: "Apple Notes opened, but its search field was not available. Open a Notes window and press Command-F2 again."
                )
            }
        }
    }

    private func captureNote() {
        let fresh = clipboardTracker.isFresh(within: NoteCapture.freshnessWindow)
        var payload: NoteCapture.Payload?
        do {
            payload = try NoteCapture.prepare(fresh: fresh)
            guard var prepared = payload else { return }
            defer { prepared.cleanUpTemporaryFiles() }
            if !prepared.attachmentURLs.isEmpty,
               !confirmAttachmentCapture(count: prepared.attachmentURLs.count) {
                return
            }
            try NoteCapture.capture(prepared)
        } catch NoteCapture.CaptureError.appleScript(let code) {
            // -1743: user denied Apple Events permission
            if code == -1743 {
                showError(title: "Notes automation not allowed",
                          message: "Open System Settings → Privacy & Security → Automation and allow \"F2 Quick Note\" to control \"Notes\".")
            } else {
                showError(title: "Could not create note",
                          message: "Apple Notes rejected the request (error \(code)). Clipboard content and file paths were not included in this message.")
            }
        } catch NoteCapture.CaptureError.contentTooLarge {
            showError(title: "Clipboard content is too large",
                      message: "The capture was blocked before anything was sent to Apple Notes.")
        } catch NoteCapture.CaptureError.unsafeAttachment {
            showError(title: "Unsafe clipboard attachment",
                      message: "Only regular, non-symbolic-link files within the privacy limits can be attached.")
        } catch NoteCapture.CaptureError.temporaryFileFailure {
            showError(title: "Could not protect temporary image",
                      message: "The capture was blocked before anything was sent to Apple Notes.")
        } catch {
            showError(title: "Could not create note",
                      message: "The request failed without exposing clipboard content or local file paths.")
        }
    }

    private func confirmAttachmentCapture(count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Attach clipboard content to Apple Notes?"
        alert.informativeText = "This capture contains \(count) attachment(s). Apple Notes may sync them through your configured account. No file names or paths are shown or logged."
        alert.addButton(withTitle: "Create Note")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
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
