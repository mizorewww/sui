@preconcurrency import Network
import AppKit
import OSLog
import SafariServices

@MainActor
final class BrowserBridge {
    private let logger = Logger(subsystem: "com.mizore.sui", category: "browser-bridge")
    var onConnectionChanged: ((Bool) -> Void)?
    private struct Command: Codable {
        let id: UUID
        let command: String
        let text: String?
    }

    private struct Response: Codable {
        let id: UUID
        let ok: Bool
        let message: String?
    }

    private var listener: NWListener?
    private var safariListener: NWListener?
    private var connection: NWConnection?
    private var incoming = Data()
    private var safariIncoming: [ObjectIdentifier: Data] = [:]
    private var pending: [UUID: CheckedContinuation<Response, Never>] = [:]
    private var safariInstalled: Bool {
        guard let url = Bundle.main.builtInPlugInsURL?.appending(path: "sui Browser Bridge.appex") else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var isConnected: Bool { connection != nil || safariInstalled }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: 47_831)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    Task { @MainActor in self?.logger.error("Listener failed: \(error.localizedDescription, privacy: .public)") }
                }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
            startSafariResponseListener()
        } catch {
            logger.error("Unable to start listener: \(error.localizedDescription, privacy: .public)")
        }
    }

    func prepareX() async -> PluginPreparation {
        guard isConnected else {
            return .notReady(
                title: "Safari 扩展未启用",
                message: "请在 Safari 设置的“扩展”中勾选 sui Browser Bridge。",
                actionTitle: "打开 Safari 设置",
                action: .openSafariSettings
            )
        }
        if connection != nil {
            NSWorkspace.shared.open(URL(string: "https://x.com/compose/post")!)
        }
        let response = await send(command: "prepareX", text: nil)
        if response.ok { return .ready }
        if response.message == "Safari 扩展响应超时。" {
            return .notReady(
                title: "Safari 扩展未启用",
                message: "请在 Safari 设置的“扩展”中勾选 sui Browser Bridge。",
                actionTitle: "打开 Safari 设置",
                action: .openSafariSettings
            )
        }
        return .notReady(
                title: "X.com 未准备好",
                message: response.message ?? "请在浏览器中登录 X 后重试。",
                actionTitle: "打开 X.com",
                action: .openURL(URL(string: "https://x.com/compose/post")!)
            )
    }

    func postToX(_ text: String) async throws {
        let response = await send(command: "postX", text: text)
        guard response.ok else { throw SuiError.bridge(response.message ?? "浏览器扩展发布失败。") }
    }

    private func accept(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        onConnectionChanged?(true)
        incoming.removeAll(keepingCapacity: true)
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in
                    self?.logger.error("Bridge connection failed: \(error.localizedDescription, privacy: .public)")
                    self?.connection = nil
                    self?.onConnectionChanged?(false)
                }
            }
            if case .cancelled = state {
                Task { @MainActor in self?.connection = nil; self?.onConnectionChanged?(false) }
            }
        }
        connection.start(queue: .global(qos: .utility))
        receive(on: connection)
    }

    private func startSafariResponseListener() {
        guard safariListener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: 47_832)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.acceptSafariResponse(connection) }
            }
            listener.start(queue: .global(qos: .utility))
            safariListener = listener
        } catch {
            logger.error("Unable to start Safari response listener: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func acceptSafariResponse(_ connection: NWConnection) {
        safariIncoming[ObjectIdentifier(connection)] = Data()
        connection.start(queue: .global(qos: .utility))
        receiveSafariResponse(on: connection)
    }

    private func receiveSafariResponse(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, _ in
            Task { @MainActor in
                guard let self else { return }
                let key = ObjectIdentifier(connection)
                if let data { self.consumeSafari(data, key: key) }
                if isComplete {
                    self.safariIncoming[key] = nil
                } else {
                    self.receiveSafariResponse(on: connection)
                }
            }
        }
    }

    private func consumeSafari(_ data: Data, key: ObjectIdentifier) {
        safariIncoming[key, default: Data()].append(data)
        guard var buffer = safariIncoming[key] else { return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let packet = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let response = try? JSONDecoder().decode(Response.self, from: packet) else { continue }
            pending.removeValue(forKey: response.id)?.resume(returning: response)
        }
        safariIncoming[key] = buffer
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, _ in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.consume(data) }
                if isComplete { self.connection = nil; self.onConnectionChanged?(false) }
                else { self.receive(on: connection) }
            }
        }
    }

    private func consume(_ data: Data) {
        incoming.append(data)
        while let newline = incoming.firstIndex(of: 0x0A) {
            let packet = incoming.prefix(upTo: newline)
            incoming.removeSubrange(...newline)
            guard let response = try? JSONDecoder().decode(Response.self, from: packet) else { continue }
            pending.removeValue(forKey: response.id)?.resume(returning: response)
        }
    }

    private func send(command: String, text: String?) async -> Response {
        let payload = Command(id: UUID(), command: command, text: text)
        if let connection {
            return await sendToChromium(payload, connection: connection)
        }
        guard safariInstalled else { return Response(id: payload.id, ok: false, message: "扩展未安装。") }
        return await sendToSafari(payload)
    }

    private func sendToChromium(_ payload: Command, connection: NWConnection) async -> Response {
        guard var data = try? JSONEncoder().encode(payload) else {
            return Response(id: payload.id, ok: false, message: "无法编码浏览器命令。")
        }
        data.append(0x0A)
        return await withCheckedContinuation { continuation in
            pending[payload.id] = continuation
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard error != nil else { return }
                Task { @MainActor in
                    self?.pending.removeValue(forKey: payload.id)?.resume(
                        returning: Response(id: payload.id, ok: false, message: "无法连接浏览器扩展。")
                    )
                }
            })
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.pending.removeValue(forKey: payload.id)?.resume(
                    returning: Response(id: payload.id, ok: false, message: "浏览器扩展响应超时。")
                )
            }
        }
    }

    private func sendToSafari(_ payload: Command) async -> Response {
        await withCheckedContinuation { continuation in
            pending[payload.id] = continuation
            var userInfo: [String: Any] = [
                "id": payload.id.uuidString,
                "command": payload.command
            ]
            if let text = payload.text { userInfo["text"] = text }
            SFSafariApplication.dispatchMessage(
                withName: "sui-command",
                toExtensionWithIdentifier: "com.mizore.sui.SafariExtension",
                userInfo: userInfo,
                completionHandler: nil
            )
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(7))
                self?.pending.removeValue(forKey: payload.id)?.resume(
                    returning: Response(id: payload.id, ok: false, message: "Safari 扩展响应超时。")
                )
            }
        }
    }

}
