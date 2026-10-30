import Foundation

struct ChatMessage {
    let role: String
    let content: String
}

/// DeepSeek 流式客户端（SSE）。
final class DeepSeekClient {
    private var task: Task<Void, Never>?
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 300
        session = URLSession(configuration: cfg)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func send(messages: [ChatMessage],
              model: String = Credentials.defaultModel,
              temperature: Double = 0.55,
              maxTokens: Int = 3600,
              onDelta: @escaping (String) -> Void,
              onDone: @escaping (String) -> Void,
              onError: @escaping (String) -> Void) {
        cancel()

        guard let key = Credentials.apiKey else {
            onError("没找到 DeepSeek 凭据：请在设置里填一个 key，或确认 ~/.dsh/.credentials.yaml 里有 DEEPSEEK_API_KEY。")
            return
        }
        guard let url = URL(string: Credentials.endpoint) else {
            onError("接口地址无效")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            onError("请求构造失败")
            return
        }
        request.httpBody = data

        let session = self.session
        task = Task {
            var full = ""
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    onError("没有拿到 HTTP 响应")
                    return
                }
                if http.statusCode != 200 {
                    var text = ""
                    for try await line in bytes.lines {
                        text += line
                        if text.count > 500 { break }
                    }
                    onError("DeepSeek 返回 \(http.statusCode)：\(text.isEmpty ? "未知错误" : text)")
                    return
                }
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }
                    guard let raw = payload.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                          let choices = obj["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let piece = delta["content"] as? String,
                          !piece.isEmpty else { continue }
                    full += piece
                    onDelta(piece)
                }
                onDone(full)
            } catch is CancellationError {
                onDone(full)
            } catch {
                if (error as NSError).code == NSURLErrorCancelled {
                    onDone(full)
                } else {
                    onError("网络错误：\(error.localizedDescription)")
                }
            }
        }
    }
}
