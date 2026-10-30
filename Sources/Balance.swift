import Foundation

/// DeepSeek 余额查询（官方 /user/balance）。
enum BalanceService {
    private static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

    static func fetch(completion: @escaping (String) -> Void) {
        guard let key = Credentials.apiKey else {
            completion("还没有 API Key，没法查余额")
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { data, response, error in
            let text: String
            if let error {
                text = "余额查询失败：\(error.localizedDescription)"
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                text = "余额查询失败：HTTP \(http.statusCode)"
            } else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                text = format(json)
            } else {
                text = "余额查询失败：返回格式无法解析"
            }
            DispatchQueue.main.async { completion(text) }
        }.resume()
    }

    private static func format(_ json: [String: Any]) -> String {
        guard let infos = json["balance_infos"] as? [[String: Any]], let first = infos.first else {
            return "余额接口没有返回可用信息"
        }
        let symbol = (first["currency"] as? String) == "USD" ? "$" : "¥"
        let total = first["total_balance"] as? String ?? "0"
        let granted = first["granted_balance"] as? String ?? "0"
        let topped = first["topped_up_balance"] as? String ?? "0"
        let available = (json["is_available"] as? Bool) ?? true
        let suffix = available ? "" : "（当前不可用）"
        return "余额 \(symbol)\(total)\(suffix)　充值 \(symbol)\(topped) / 赠送 \(symbol)\(granted)"
    }
}
