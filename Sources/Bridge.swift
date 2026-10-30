import AppKit
import WebKit

/// 提示词面板的 JS ⇄ Swift 桥；桌宠由原生 AppKit 绘制。
final class Bridge: NSObject, WKScriptMessageHandler {
    weak var panel: PanelWindow?
    weak var pet: PetWindow?

    var onTogglePanel: (() -> Void)?
    var onShowPanel: (() -> Void)?
    var onHidePanel: (() -> Void)?
    var onPin: ((Bool) -> Void)?

    private let client = DeepSeekClient()
    private let projectDir = "/Users/admin/科研项目/肥鱼提示词工坊"

    init(panel: PanelWindow, pet: PetWindow) {
        self.panel = panel
        self.pet = pet
    }

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let cmd = body["cmd"] as? String else { return }

        switch cmd {
        case "copy":
            let text = body["text"] as? String ?? ""
            NSPasteboard.general.clearContents()
            let ok = !text.isEmpty && NSPasteboard.general.setString(text, forType: .string)
            emit(panel?.webView, "copied", ["ok": ok])

        case "generate":
            generate(body)

        case "cancel":
            client.cancel()

        case "hide":
            onHidePanel?()

        case "pin":
            let on = body["on"] as? Bool ?? true
            onPin?(on)
            emit(panel?.webView, "pinned", ["on": on])

        case "status":
            emit(panel?.webView, "status", [
                "hasKey": Credentials.apiKey != nil,
                "source": Credentials.sourceText,
                "model": Credentials.defaultModel
            ])

        case "saveKey":
            Credentials.manualKey = (body["key"] as? String) ?? ""
            emit(panel?.webView, "status", [
                "hasKey": Credentials.apiKey != nil,
                "source": Credentials.sourceText,
                "model": Credentials.defaultModel
            ])
            pet?.bubble(Credentials.apiKey != nil ? "收到，开始干活～" : "还是没有 key 呀")

        case "appearance":
            let opacity = (body["opacity"] as? Double).map { CGFloat($0 / 100) } ?? panel?.cardOpacity ?? 0.8
            let width = CGFloat((body["width"] as? Double) ?? Double(panel?.frame.width ?? 470))
            let height = CGFloat((body["height"] as? Double) ?? Double(panel?.frame.height ?? 726))
            panel?.applyAppearance(opacity: opacity, size: NSSize(width: width, height: height))

        case "openProject":
            NSWorkspace.shared.open(URL(fileURLWithPath: projectDir))

        default:
            break
        }
    }

    // MARK: - 生成

    private func generate(_ body: [String: Any]) {
        let raw = body["messages"] as? [[String: Any]] ?? []
        let messages = raw.compactMap { item -> ChatMessage? in
            guard let role = item["role"] as? String,
                  let content = item["content"] as? String else { return nil }
            return ChatMessage(role: role, content: content)
        }
        guard !messages.isEmpty else {
            emit(panel?.webView, "error", ["message": "没有要发送的内容"])
            return
        }

        emit(panel?.webView, "start", ["ok": true])
        pet?.setState("working")

        client.send(messages: messages,
                    model: body["model"] as? String ?? Credentials.defaultModel,
                    temperature: body["temperature"] as? Double ?? 0.55,
                    maxTokens: body["maxTokens"] as? Int ?? 3600,
                    onDelta: { [weak self] piece in
                        self?.emit(self?.panel?.webView, "chunk", ["text": piece])
                    },
                    onDone: { [weak self] full in
                        self?.emit(self?.panel?.webView, "done", ["text": full])
                        self?.pet?.setState("success")
                        self?.pet?.bubble("写好啦，点复制粘给 agent 🐟", seconds: 4)
                    },
                    onError: { [weak self] message in
                        self?.emit(self?.panel?.webView, "error", ["message": message])
                        self?.pet?.setState("idle")
                        self?.pet?.bubble(message, seconds: 5)
                    })
    }

    private func emit(_ webView: WKWebView?, _ function: String, _ payload: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            webView.evaluateJavaScript("window.__fish && window.__fish.\(function)(\(json));",
                                       completionHandler: nil)
        }
    }
}
