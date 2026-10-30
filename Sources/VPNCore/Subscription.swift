import Foundation

/// Downloads a subscription link and extracts the server list plus the account info providers put in headers.
public enum Subscription {
    public struct Result {
        public var servers: [Server]
        public var info: SubscriptionInfo
    }

    public static func fetch(urlString: String) async -> Result? {
        guard let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        // Providers often serve different content to unknown clients; announce ourselves like a normal VPN app.
        req.setValue("Happ/5.7.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let servers = parse(body: String(decoding: data, as: UTF8.self))
        guard !servers.isEmpty else { return nil }
        var info = parseHeaders { http.value(forHTTPHeaderField: $0) }
        info.fetched = Date()
        return Result(servers: servers, info: info)
    }

    /// `subscription-userinfo: upload=0; download=123; total=456; expire=1788000000`
    static func parseHeaders(_ header: (String) -> String?) -> SubscriptionInfo {
        var info = SubscriptionInfo()
        if let raw = header("subscription-userinfo") {
            var up: Int64 = 0, down: Int64 = 0
            for part in raw.split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2, let n = Int64(kv[1]) else { continue }
                switch kv[0] {
                case "upload": up = n
                case "download": down = n
                case "total": info.totalBytes = n > 0 ? n : nil
                case "expire": info.expires = n > 0 ? Date(timeIntervalSince1970: TimeInterval(n)) : nil
                default: break
                }
            }
            info.usedBytes = up + down
        }
        if let title = header("profile-title") {
            if title.hasPrefix("base64:"), let d = Data(base64Encoded: String(title.dropFirst(7))) {
                info.title = String(decoding: d, as: UTF8.self)
            } else {
                info.title = title
            }
        }
        return info
    }

    /// Plain list or base64 of one link per line; vless, trojan, ss and vmess are understood.
    public static func parse(body: String) -> [Server] {
        let text = decodeBase64(body.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.contains("://") ? $0 : nil } ?? body
        return text.split(whereSeparator: \.isNewline).compactMap { server(from: String($0).trimmingCharacters(in: .whitespaces)) }
    }

    static func server(from line: String) -> Server? {
        if line.hasPrefix("vmess://") {
            guard let json = decodeBase64(String(line.dropFirst(8))),
                  let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let host = obj["add"] as? String else { return nil }
            let port = (obj["port"] as? Int) ?? Int(obj["port"] as? String ?? "") ?? 443
            return Server(name: (obj["ps"] as? String) ?? host, host: host, port: port)
        }
        guard ["vless://", "trojan://", "ss://", "hysteria2://", "hy2://", "tuic://"].contains(where: line.hasPrefix),
              let c = URLComponents(string: line), let host = c.host, !host.isEmpty else { return nil }
        let name = c.fragment?.removingPercentEncoding ?? host
        return Server(name: name, host: host, port: c.port ?? 443)
    }

    static func decodeBase64(_ s: String) -> String? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t).flatMap { String(data: $0, encoding: .utf8) }
    }
}
