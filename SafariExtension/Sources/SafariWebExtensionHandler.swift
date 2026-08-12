@preconcurrency import Network
import OSLog
import SafariServices

private final class ExtensionRequestCompletion: @unchecked Sendable {
    private let context: NSExtensionContext
    private let lock = NSLock()
    private var finished = false

    init(_ context: NSExtensionContext) { self.context = context }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        context.completeRequest(returningItems: nil)
    }
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let logger = Logger(subsystem: "com.mizore.sui", category: "safari-extension")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        logger.notice("Native response received: id=\(String(describing: message?["id"]), privacy: .public), ok=\(String(describing: message?["ok"]), privacy: .public)")
        guard var message else {
            context.completeRequest(returningItems: nil)
            return
        }

        if message["ok"] as? Bool == nil {
            message["ok"] = false
            message["message"] = "Safari 扩展返回了无效响应。"
        }
        guard JSONSerialization.isValidJSONObject(message),
              let encoded = try? JSONSerialization.data(withJSONObject: message) else {
            context.completeRequest(returningItems: nil)
            return
        }

        var framed = encoded
        framed.append(0x0A)
        let data = framed
        let completion = ExtensionRequestCompletion(context)
        let logger = logger
        let connection = NWConnection(host: "127.0.0.1", port: 47_832, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                logger.notice("Forwarding Safari response to sui")
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                    completion.finish()
                })
            case .failed(let error):
                logger.error("Unable to forward Safari response: \(error.localizedDescription, privacy: .public)")
                completion.finish()
            case .cancelled:
                completion.finish()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
    }
}
