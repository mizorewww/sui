import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: [
            "id": message?["id"] as Any,
            "ok": false,
            "message": "请保持 sui App 运行，并使用 Chromium bridge 完成 V0.1 发布。"
        ]]
        context.completeRequest(returningItems: [response])
    }
}

