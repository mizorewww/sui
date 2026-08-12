import AppKit

enum PluginID: String, CaseIterable, Codable, Sendable {
    case none
    case telegram
    case x
    case codex
}

struct PluginDescriptor: Sendable {
    let id: PluginID
    let name: String
    let symbolName: String
    let detail: String
}

enum PluginAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

enum PluginPreparation: Sendable {
    case ready
    case notReady(title: String, message: String, actionTitle: String?, action: PluginRecoveryAction?)
}

enum PluginRecoveryAction: Sendable {
    case openApplication(bundleIdentifiers: [String])
    case openURL(URL)
    case openAccessibilitySettings
    case openExtensionsFolder
}

@MainActor
protocol SuiPlugin: AnyObject {
    var descriptor: PluginDescriptor { get }
    func availability() -> PluginAvailability
    func prepare() async -> PluginPreparation
    func execute(text: String) async throws
}

enum SuiError: LocalizedError {
    case permission(String)
    case unavailable(String)
    case automation(String)
    case speech(String)
    case bridge(String)

    var errorDescription: String? {
        switch self {
        case .permission(let message), .unavailable(let message), .automation(let message),
             .speech(let message), .bridge(let message):
            message
        }
    }
}
