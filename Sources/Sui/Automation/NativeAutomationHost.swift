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

    func prepare(bundleIdentifiers: [String], hints: [String]) -> Target? {
        guard AXIsProcessTrusted(), let application = runningApplication(bundleIdentifiers: bundleIdentifiers) else {
            logger.error("Target unavailable or Accessibility permission missing")
            return nil
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let composer = findEditable(in: appElement, hints: hints) else {
            logger.error("No matching composer found in \(application.bundleIdentifier ?? "unknown", privacy: .public)")
            return nil
        }
        logger.notice("Composer found in \(application.bundleIdentifier ?? "unknown", privacy: .public)")
        return Target(application: application, composer: composer)
    }

    func execute(text: String, target: Target) async throws {
        target.application.activate(options: [.activateAllWindows])
        let focusError = AXUIElementSetAttributeValue(target.composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard focusError == .success else {
            throw SuiError.automation("无法聚焦目标输入框。")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        try await Task.sleep(for: .milliseconds(120))
        postKey(9, flags: .maskCommand)
        try await Task.sleep(for: .milliseconds(100))
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

    private func findEditable(in root: AXUIElement, hints: [String]) -> AXUIElement? {
        let childAttributes = [
            kAXFocusedUIElementAttribute,
            kAXWindowsAttribute,
            kAXChildrenAttribute,
            kAXContentsAttribute,
            kAXVisibleChildrenAttribute,
            kAXRowsAttribute
        ]
        var queue: [AXUIElement] = [root]
        var visited = Set<CFHashCode>()
        var fallback: AXUIElement?
        var inspected = 0

        while !queue.isEmpty, inspected < 5_000 {
            let element = queue.removeFirst()
            let hash = CFHash(element)
            guard visited.insert(hash).inserted else { continue }
            inspected += 1
            let role = stringAttribute(kAXRoleAttribute, of: element) ?? ""
            let enabled = boolAttribute(kAXEnabledAttribute, of: element) ?? true
            let editableRole = role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
            if editableRole && enabled {
            let haystack = [
                stringAttribute(kAXDescriptionAttribute, of: element),
                stringAttribute(kAXTitleAttribute, of: element),
                stringAttribute(kAXHelpAttribute, of: element),
                stringAttribute(kAXPlaceholderValueAttribute, of: element)
            ].compactMap { $0 }.joined(separator: " ").lowercased()
                if hints.isEmpty || hints.contains(where: { haystack.contains($0.lowercased()) }) {
                    return element
                }
                if fallback == nil, boolAttribute(kAXFocusedAttribute, of: element) == true {
                    fallback = element
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
        return fallback
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
