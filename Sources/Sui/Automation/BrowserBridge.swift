@preconcurrency import Network
import AppKit
import OSLog

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
    private var connection: NWConnection?
    private var incoming = Data()
    private var pending: [UUID: CheckedContinuation<Response, Never>] = [:]

    var isConnected: Bool { connection != nil }

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
        } catch {
            logger.error("Unable to start listener: \(error.localizedDescription, privacy: .public)")
        }
    }

    func prepareX() async -> PluginPreparation {
        guard isConnected else {
            return .notReady(
                title: "X.com 扩展未连接",
                message: "请安装并启用 sui 浏览器扩展，然后重新按下手柄按键。",
                actionTitle: "打开扩展文件夹",
                action: .openExtensionsFolder
            )
        }
        NSWorkspace.shared.open(URL(string: "https://x.com/compose/post")!)
        let response = await send(command: "prepareX", text: nil)
        return response.ok
            ? .ready
            : .notReady(
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
        guard let connection else { return Response(id: UUID(), ok: false, message: "扩展未连接。") }
        let payload = Command(id: UUID(), command: command, text: text)
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
}
