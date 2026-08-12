@preconcurrency import Network
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
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        guard let message,
              JSONSerialization.isValidJSONObject(message),
              let encoded = try? JSONSerialization.data(withJSONObject: message) else {
            context.completeRequest(returningItems: nil)
            return
        }

        var framed = encoded
        framed.append(0x0A)
        let data = framed
        let completion = ExtensionRequestCompletion(context)
        let connection = NWConnection(host: "127.0.0.1", port: 47_832, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                    completion.finish()
                })
            case .failed, .cancelled:
                completion.finish()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
    }
}
