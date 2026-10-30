import Foundation
import Network

public enum Probes {
    /// TCP connect time to host:port in milliseconds, nil on timeout or refusal.
    public static func tcpPing(host: String, port: Int, timeout: TimeInterval = 3) async -> Double? {
        // Pinned to the physical interface: over the default route the tunnel would answer the handshake itself
        // (a "2 ms" ping to a server hundreds of km away) instead of the server.
        async let wifi = tcpPing(host: host, port: port, timeout: timeout, via: .wifi)
        async let wired = tcpPing(host: host, port: port, timeout: timeout, via: .wiredEthernet)
        let (a, b) = await (wifi, wired)
        return [a, b].compactMap { $0 }.min()
    }

    static func tcpPing(host: String, port: Int, timeout: TimeInterval, via type: NWInterface.InterfaceType) async -> Double? {
        guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        let params = NWParameters.tcp
        params.requiredInterfaceType = type
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: params)
        let start = DispatchTime.now()
        return await withCheckedContinuation { cont in
            let once = Once()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.fire() {
                        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
                        conn.cancel()
                        cont.resume(returning: ms)
                    }
                case .failed, .cancelled:
                    if once.fire() { cont.resume(returning: nil) }
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.fire() {
                    conn.cancel()
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Full HTTPS round trip over the default route: through the tunnel when it is up, which is what apps experience.
    public static func httpsMs(timeout: TimeInterval = 6, warmUp: Bool = false) async -> Double? {
        if warmUp { _ = await httpsMs(timeout: timeout, warmUp: false) }
        var req = URLRequest(url: URL(string: "https://www.gstatic.com/generate_204")!, timeoutInterval: timeout)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        let start = DispatchTime.now()
        guard let (_, resp) = try? await URLSession(configuration: cfg).data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode, code == 204 || code == 200 else { return nil }
        return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
    }

    /// The address and country other services see; a Russian one while the VPN is on is a leak.
    /// Cloudflare's trace page is a tiny text file with no rate limit worth mentioning, so it can be asked every few seconds.
    public static func externalIP(timeout: TimeInterval = 4) async -> ExternalIP? {
        var req = URLRequest(url: URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!, timeoutInterval: timeout)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        guard let (data, _) = try? await URLSession(configuration: cfg).data(for: req) else { return nil }
        return parseTrace(String(decoding: data, as: UTF8.self))
    }

    static func parseTrace(_ text: String) -> ExternalIP? {
        var fields = [String: String]()
        for line in text.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { fields[kv[0]] = kv[1] }
        }
        guard let ip = fields["ip"] else { return nil }
        return ExternalIP(ip: ip, country: fields["loc"])
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
