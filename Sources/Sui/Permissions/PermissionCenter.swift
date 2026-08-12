import AppKit
import AVFoundation
import Speech
import ApplicationServices

@MainActor
final class PermissionCenter {
    enum State: Equatable {
        case granted
        case needsRequest
        case denied

        var label: String {
            switch self {
            case .granted: "Allowed"
            case .needsRequest: "Not requested"
            case .denied: "Open Settings"
            }
        }
    }

    struct Snapshot: Equatable {
        let microphone: State
        let speech: State
        let accessibility: State
        var isReady: Bool { microphone == .granted && speech == .granted && accessibility == .granted }
    }

    var snapshot: Snapshot {
        Snapshot(
            microphone: Self.microphoneState,
            speech: Self.speechState,
            accessibility: AXIsProcessTrusted() ? .granted : .needsRequest
        )
    }

    func requestAll() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
            }
        }
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    func openSettings(for kind: Kind) {
        let anchor: String
        switch kind {
        case .microphone: anchor = "Privacy_Microphone"
        case .speech: anchor = "Privacy_SpeechRecognition"
        case .accessibility: anchor = "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    enum Kind { case microphone, speech, accessibility }

    private static var microphoneState: State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .needsRequest
        default: .denied
        }
    }

    private static var speechState: State {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .notDetermined: .needsRequest
        default: .denied
        }
    }
}
