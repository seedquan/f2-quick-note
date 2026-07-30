import AppKit
import ApplicationServices

/// Opens Apple Notes and focuses its search field. Focusing another app's UI
/// is intentionally gated by the user's macOS Accessibility permission.
final class AppleNotesSearchController {
    enum Result {
        case focused
        case accessibilityPermissionRequired
        case notesUnavailable
        case searchFieldNotFound
    }

    private static let notesBundleIdentifier = "com.apple.Notes"
    private let maximumFocusAttempts = 20
    private let retryDelay: TimeInterval = 0.2
    private var currentRequest = UUID()

    func openAndFocusSearch(completion: @escaping (Result) -> Void) {
        let request = UUID()
        currentRequest = request

        // The prompt is asynchronous. Notes is opened regardless so the
        // shortcut still performs its first, non-privileged responsibility.
        requestAccessibilityPermissionIfNeeded()

        guard let notesURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.notesBundleIdentifier
        ) else {
            completion(.notesUnavailable)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: notesURL,
            configuration: configuration
        ) { [weak self] application, error in
            DispatchQueue.main.async {
                guard let self, self.currentRequest == request else { return }
                guard error == nil, let application else {
                    completion(.notesUnavailable)
                    return
                }
                application.activate(options: [.activateAllWindows])
                guard AXIsProcessTrusted() else {
                    completion(.accessibilityPermissionRequired)
                    return
                }
                self.focusSearchField(
                    in: application,
                    request: request,
                    attempt: 0,
                    completion: completion
                )
            }
        }
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func focusSearchField(
        in application: NSRunningApplication,
        request: UUID,
        attempt: Int,
        completion: @escaping (Result) -> Void
    ) {
        guard currentRequest == request else { return }
        guard !application.isTerminated else {
            completion(.notesUnavailable)
            return
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        if let searchField = findSearchField(in: applicationElement),
           AXUIElementSetAttributeValue(
               searchField,
               kAXFocusedAttribute as CFString,
               kCFBooleanTrue
           ) == .success {
            completion(.focused)
            return
        }

        guard attempt + 1 < maximumFocusAttempts else {
            completion(.searchFieldNotFound)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            self?.focusSearchField(
                in: application,
                request: request,
                attempt: attempt + 1,
                completion: completion
            )
        }
    }

    private func findSearchField(in root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var index = 0
        var visited = Set<CFHashCode>()

        // Notes' search field is near the top of the accessibility tree. The
        // cap prevents a malformed or unexpectedly huge tree from stalling
        // the menu-bar app.
        while index < queue.count, index < 2_000 {
            let element = queue[index]
            index += 1
            guard visited.insert(CFHash(element)).inserted else { continue }

            if isSearchField(element) {
                return element
            }
            queue.append(contentsOf: elements(
                for: kAXChildrenAttribute as CFString,
                in: element
            ))
        }
        return nil
    }

    private func isSearchField(_ element: AXUIElement) -> Bool {
        let role = stringValue(for: kAXRoleAttribute as CFString, in: element)
        guard role == NSAccessibility.Role.textField.rawValue else {
            return false
        }
        let subrole = stringValue(for: kAXSubroleAttribute as CFString, in: element)
        if subrole == NSAccessibility.Subrole.searchField.rawValue {
            return true
        }

        let searchableLabels = [
            kAXIdentifierAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXPlaceholderValueAttribute,
        ].compactMap {
            stringValue(for: $0 as CFString, in: element)?.lowercased()
        }
        return searchableLabels.contains {
            $0.contains("search") || $0.contains("搜索")
        }
    }

    private func elements(
        for attribute: CFString,
        in element: AXUIElement
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let elements = value as? [AXUIElement] else {
            return []
        }
        return elements
    }

    private func stringValue(
        for attribute: CFString,
        in element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
