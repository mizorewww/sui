import Foundation
import GameController

@MainActor
final class ControllerService {
    struct Device: Hashable {
        let key: String
        let name: String
        let controller: GCController

        static func == (lhs: Device, rhs: Device) -> Bool { lhs.key == rhs.key }
        func hash(into hasher: inout Hasher) { hasher.combine(key) }
    }

    var onDevicesChanged: (([Device]) -> Void)?
    var onButtonChanged: ((String, Bool) -> Void)?

    private var devices: [Device] = []
    private var observers: [NSObjectProtocol] = []
    private var selectedKey: String?

    init() {
        GCController.shouldMonitorBackgroundEvents = true
    }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        GCController.startWirelessControllerDiscovery {}
        reload()
    }

    func select(key: String?) {
        selectedKey = key
        attachHandlers()
    }

    private func reload() {
        devices = GCController.controllers().enumerated().map { index, controller in
            Device(
                key: "\(controller.vendorName ?? controller.productCategory)-\(index)",
                name: controller.vendorName ?? controller.productCategory,
                controller: controller
            )
        }
        if selectedKey == nil || !devices.contains(where: { $0.key == selectedKey }) {
            selectedKey = devices.first?.key
        }
        attachHandlers()
        onDevicesChanged?(devices)
    }

    private func attachHandlers() {
        for device in devices {
            guard let gamepad = device.controller.extendedGamepad else { continue }
            gamepad.buttonA.pressedChangedHandler = nil
            gamepad.buttonB.pressedChangedHandler = nil
            gamepad.buttonY.pressedChangedHandler = nil
        }
        guard let controller = devices.first(where: { $0.key == selectedKey })?.controller,
              let gamepad = controller.extendedGamepad else { return }

        bind(gamepad.buttonA, name: "A")
        bind(gamepad.buttonB, name: "B")
        bind(gamepad.buttonY, name: "Y")
    }

    private func bind(_ button: GCControllerButtonInput, name: String) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.onButtonChanged?(name, pressed) }
        }
    }
}

