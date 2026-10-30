import Foundation

/// 凭据：优先 App 设置里的 key，否则复用 DSH 已登录凭据（只读本机文件）。
enum Credentials {
    static let endpoint = "https://api.deepseek.com/chat/completions"
    static let defaultModel = "deepseek-flash"

    static var manualKey: String? {
        get {
            let value = UserDefaults.standard.string(forKey: "deepseek.apiKey") ?? ""
            return value.isEmpty ? nil : value
        }
        set { UserDefaults.standard.set(newValue ?? "", forKey: "deepseek.apiKey") }
    }

    static var dshKey: String? {
        let path = ("~/.dsh/.credentials.yaml" as NSString).expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("DEEPSEEK_API_KEY:") else { continue }
            let value = line.dropFirst("DEEPSEEK_API_KEY:".count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    static var apiKey: String? { manualKey ?? dshKey }

    static var sourceText: String {
        if manualKey != nil { return "自定义 Key" }
        if dshKey != nil { return "复用 DSH 凭据" }
        return "未找到凭据"
    }
}
