import AppKit
import ApplicationServices
import OSLog

@MainActor
final class NativeAutomationHost {
    private let logger = Logger(subsystem: "com.mizore.sui", category: "native-automation")
    struct Target {
        let application: NSRunningApplication
        let composer: AXUIElement
    }

    func isApplicationInstalled(bundleIdentifiers: [String]) -> Bool {
        bundleIdentifiers.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    func runningApplication(bundleIdentifiers: [String]) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return bundleIdentifiers.contains(bundleIdentifier)
        }
    }

    func prepare(bundleIdentifiers: [String], hints: [String]) async -> Target? {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission missing")
            return nil
        }
        guard let application = await activateApplication(bundleIdentifiers: bundleIdentifiers) else {
            logger.error("Target application could not be launched")
            return nil
        }
        for _ in 0..<100 where !application.isActive {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard application.isActive else {
            let bundleIdentifier = application.bundleIdentifier ?? "unknown"
            logger.error("Unable to bring \(bundleIdentifier, privacy: .public) to the foreground")
            return nil
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        for _ in 0..<30 {
            if let composer = findEditable(in: appElement, hints: hints) {
                logger.notice("Composer found in \(application.bundleIdentifier ?? "unknown", privacy: .public)")
                return Target(application: application, composer: composer)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        logger.error("No matching composer found in \(application.bundleIdentifier ?? "unknown", privacy: .public)")
        return nil
    }

    func execute(text: String, target: Target) async throws {
        guard let application = await activateApplication(bundleIdentifiers: [target.application.bundleIdentifier].compactMap { $0 }) else {
            throw SuiError.automation("无法把目标应用切换到前台。")
        }
        for _ in 0..<40 where !application.isActive {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard application.isActive else {
            throw SuiError.automation("无法把目标应用切换到前台。")
        }
        let focusError = AXUIElementSetAttributeValue(target.composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard focusError == .success || boolAttribute(kAXFocusedAttribute, of: target.composer) == true else {
            throw SuiError.automation("无法聚焦目标输入框。")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        try await Task.sleep(for: .milliseconds(120))
        postKey(9, flags: .maskCommand)
        // Codex's React editor applies a paste asynchronously. Give it one frame
        // plus event propagation time before Return so the freshly pasted text is
        // the content that gets submitted.
        try await Task.sleep(for: .milliseconds(250))
        postKey(36, flags: [])
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func open(bundleIdentifiers: [String]) {
        guard let url = bundleIdentifiers.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func activateApplication(bundleIdentifiers: [String]) async -> NSRunningApplication? {
        guard let url = bundleIdentifiers.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else {
            return nil
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.hides = false
        do {
            // Relinquish the foreground first. NSRunningApplication.activate can be
            // rejected when sui is active even though this came from a controller
            // press. Opening with activates=true after hiding sui is deterministic.
            NSApp.hide(nil)
            logger.notice("Opening target application at \(url.path, privacy: .public)")
            return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            logger.error("Launch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func findEditable(in root: AXUIElement, hints: [String]) -> AXUIElement? {
        let childAttributes = [
            kAXFocusedUIElementAttribute,
            kAXWindowsAttribute,
            kAXChildrenAttribute,
            kAXContentsAttribute,
            kAXVisibleChildrenAttribute,
            kAXRowsAttribute
        ]
        let focusedElement: AXUIElement? = {
            guard let value = valueAttribute(kAXFocusedUIElementAttribute, of: root),
                  CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(value, to: AXUIElement.self)
        }()
        // Telegram exposes an AXTextArea with no useful labels. Codex's Chromium
        // editor can instead expose a focused AXGroup whose AXValue is settable.
        // Accept the latter only when its metadata matches the plugin hints so a
        // focused terminal or search control never becomes the send target.
        if let focusedElement, boolAttribute(kAXEnabledAttribute, of: focusedElement) ?? true {
            let role = stringAttribute(kAXRoleAttribute, of: focusedElement) ?? ""
            if role == kAXTextAreaRole as String {
                return focusedElement
            }
            if isValueSettable(focusedElement), metadata(of: focusedElement, role: role, hints: hints).matches {
                logger.notice("Using focused value-settable composer with role \(role, privacy: .public)")
                return focusedElement
            }
        }

        let searchRoot: AXUIElement = {
            for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                guard let value = valueAttribute(attribute, of: root),
                      CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
                return unsafeDowncast(value, to: AXUIElement.self)
            }
            return root
        }()
        var queue: [AXUIElement] = [searchRoot]
        var visited = Set<CFHashCode>()
        var fallback: AXUIElement?
        var unlabeledTextAreas: [AXUIElement] = []
        var inspected = 0

        while !queue.isEmpty, inspected < 5_000 {
            let element = queue.removeFirst()
            let hash = CFHash(element)
            guard visited.insert(hash).inserted else { continue }
            inspected += 1
            let role = stringAttribute(kAXRoleAttribute, of: element) ?? ""
            let enabled = boolAttribute(kAXEnabledAttribute, of: element) ?? true
            let textRole = role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
            let valueSettable = isValueSettable(element)
            if (textRole || valueSettable) && enabled {
                let match = metadata(of: element, role: role, hints: hints)
                if hints.isEmpty || match.matches {
                    logger.notice(
                        "Matched composer role \(role, privacy: .public), valueSettable=\(valueSettable)"
                    )
                    return element
                }
                if fallback == nil, boolAttribute(kAXFocusedAttribute, of: element) == true {
                    fallback = element
                }
                let isTextArea = role == kAXTextAreaRole as String
                let isHidden = boolAttribute(kAXHiddenAttribute, of: element) == true
                let disallowed = ["search", "find", "filter", "terminal", "搜索"]
                if isTextArea, !isHidden,
                   !disallowed.contains(where: { match.text.contains($0) }) {
                    unlabeledTextAreas.append(element)
                }
            }
            for attribute in childAttributes {
                guard let value = valueAttribute(attribute, of: element) else { continue }
                if CFGetTypeID(value) == AXUIElementGetTypeID() {
                    queue.append(unsafeDowncast(value, to: AXUIElement.self))
                } else if let children = value as? [AXUIElement] {
                    queue.append(contentsOf: children)
                }
            }
        }
        logger.debug("Inspected \(inspected) accessibility elements")
        if let candidate = unlabeledTextAreas.last {
            logger.notice(
                "Using last visible unlabeled text area from \(unlabeledTextAreas.count) candidate(s) in the focused window"
            )
            return candidate
        }
        return fallback
    }

    private func metadata(of element: AXUIElement, role: String, hints: [String]) -> (text: String, matches: Bool) {
        let text = [
            role,
            stringAttribute(kAXSubroleAttribute, of: element),
            stringAttribute(kAXRoleDescriptionAttribute, of: element),
            stringAttribute(kAXDescriptionAttribute, of: element),
            stringAttribute(kAXTitleAttribute, of: element),
            stringAttribute(kAXHelpAttribute, of: element),
            stringAttribute(kAXPlaceholderValueAttribute, of: element),
            stringAttribute(kAXIdentifierAttribute, of: element),
            stringAttribute(kAXDOMIdentifierAttribute, of: element)
        ].compactMap { $0 }.joined(separator: " ").lowercased()
        return (text, hints.contains { text.contains($0.lowercased()) })
    }

    private func isValueSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private func valueAttribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        valueAttribute(name, of: element) as? String
    }

    private func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        valueAttribute(name, of: element) as? Bool
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
