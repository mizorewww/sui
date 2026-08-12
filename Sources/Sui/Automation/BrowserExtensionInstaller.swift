import Foundation

enum BrowserExtensionInstaller {
    static let extensionID = "khknllalpdcffgcpcmhmlbfllabepigc"
    static let hostName = "com.mizore.sui.browserbridge"

    static func installNativeMessagingManifests() {
        let helper = Bundle.main.bundleURL.appending(path: "Contents/MacOS/Helpers/sui-browser-bridge").path
        guard FileManager.default.isExecutableFile(atPath: helper) else { return }

        let payload: [String: Any] = [
            "name": hostName,
            "description": "sui browser bridge",
            "path": helper,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        let directories = [
            "Google/Chrome/NativeMessagingHosts",
            "Chromium/NativeMessagingHosts",
            "Microsoft Edge/NativeMessagingHosts",
            "BraveSoftware/Brave-Browser/NativeMessagingHosts"
        ]
        for directory in directories {
            let url = library.appending(path: directory, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? data.write(to: url.appending(path: "\(hostName).json"), options: .atomic)
        }
    }
}
