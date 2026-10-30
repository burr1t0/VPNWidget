import Foundation

public enum TunnelStatus: String, Codable, Sendable {
    case connected, connecting, disconnecting, disconnected, unknown
}

/// What the widget should tell the user, ordered by how urgent it is.
public enum Verdict: String, Codable, Sendable {
    case ok, noTraffic, serverDown, leak, exitChanged, off, unknown
}

public struct Server: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var host: String
    public var port: Int
    public var id: String { "\(host):\(port)#\(name)" }

    public init(name: String, host: String, port: Int) {
        self.name = name
        self.host = host
        self.port = port
    }
}

public struct ServerPing: Codable, Equatable, Sendable, Identifiable {
    public var server: Server
    /// TCP connect time to the server, nil when it did not answer.
    public var ms: Double?
    public var id: String { server.id }

    public init(server: Server, ms: Double?) {
        self.server = server
        self.ms = ms
    }
}

public struct SubscriptionInfo: Codable, Equatable, Sendable {
    public var title: String?
    public var usedBytes: Int64?
    public var totalBytes: Int64?
    public var expires: Date?
    public var fetched: Date?
    /// Human-readable reason the last refresh failed; the old server list stays in use.
    public var error: String?

    public init(title: String? = nil, usedBytes: Int64? = nil, totalBytes: Int64? = nil,
                expires: Date? = nil, fetched: Date? = nil, error: String? = nil) {
        self.title = title
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.expires = expires
        self.fetched = fetched
        self.error = error
    }
}

/// The country the internet sees us in changed from the one the user accepted. Stays until the user dismisses it.
public struct ExitAlert: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
    public var at: Date

    public init(from: String, to: String, at: Date = Date()) {
        self.from = from
        self.to = to
        self.at = at
    }
}

public struct ExternalIP: Codable, Equatable, Sendable {
    public var ip: String
    public var country: String?

    public init(ip: String, country: String?) {
        self.ip = ip
        self.country = country
    }
}

/// Everything the widget draws. The agent writes it, the widget only reads it.
public struct VPNState: Codable, Equatable, Sendable {
    public var updated: Date
    public var status: TunnelStatus
    public var since: Date?
    public var interface: String?
    public var dns: String?
    /// Latency of a full HTTPS request over the default route, i.e. what apps get through the tunnel.
    public var tunnelMs: Double?
    public var external: ExternalIP?
    public var servers: [ServerPing]
    public var pinned: String?
    public var subscription: SubscriptionInfo
    /// Result of the last network analysis step, e.g. "DNS 4 мс · интернет 14 мс" from NetWatch, when available.
    public var path: String?
    /// A toggle or refresh the user asked for that has not finished yet.
    public var busy: String?
    /// The exit country the user is used to; a different one raises `alert`.
    public var baselineCountry: String?
    public var alert: ExitAlert?

    public init(updated: Date = Date(), status: TunnelStatus = .unknown, since: Date? = nil, interface: String? = nil,
                dns: String? = nil, tunnelMs: Double? = nil, external: ExternalIP? = nil, servers: [ServerPing] = [],
                pinned: String? = nil, subscription: SubscriptionInfo = SubscriptionInfo(), path: String? = nil, busy: String? = nil,
                baselineCountry: String? = nil, alert: ExitAlert? = nil) {
        self.updated = updated
        self.status = status
        self.since = since
        self.interface = interface
        self.dns = dns
        self.tunnelMs = tunnelMs
        self.external = external
        self.servers = servers
        self.pinned = pinned
        self.subscription = subscription
        self.path = path
        self.busy = busy
        self.baselineCountry = baselineCountry
        self.alert = alert
    }

    public static let staleAfter: TimeInterval = 45

    public func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(updated) > Self.staleAfter }

    /// The server the user actually uses: the pinned one by name, else the first.
    public var activeServer: ServerPing? {
        if let pinned, let hit = servers.first(where: { $0.server.name.localizedCaseInsensitiveContains(pinned) }) { return hit }
        return servers.first
    }

    public var verdict: Verdict {
        switch status {
        case .unknown: return .unknown
        case .disconnected, .disconnecting: return .off
        case .connecting: return .unknown
        case .connected:
            if let c = external?.country, c.uppercased() == "RU" { return .leak }
            if alert != nil { return .exitChanged }
            if tunnelMs == nil {
                return activeServer.map { $0.ms == nil } == true ? .serverDown : .noTraffic
            }
            return .ok
        }
    }

    public var headline: String {
        if isStale() { return "Нет свежих данных" }
        switch verdict {
        case .ok: return "VPN работает"
        case .noTraffic: return "Подключён, но трафика нет"
        case .serverDown: return "Сервер не отвечает"
        case .leak: return "Утечка: виден российский адрес"
        case .exitChanged: return "Сменилась страна выхода"
        case .off: return status == .disconnecting ? "Отключается…" : "VPN выключен"
        case .unknown: return status == .connecting ? "Подключается…" : "Состояние неизвестно"
        }
    }

    public var detail: String {
        switch verdict {
        case .ok: return "Туннель \(tunnelMs.map { String(format: "%.0f мс", $0) } ?? "—")" + (external.map { " · \($0.country ?? $0.ip)" } ?? "")
        case .noTraffic: return "Туннель поднят, запросы не проходят. Попробуйте переподключить"
        case .serverDown: return "До сервера не достучаться: проблема на стороне сервера или сети"
        case .leak: return "Трафик идёт мимо туннеля. Отключите сеть и переподключите VPN"
        case .exitChanged:
            guard let a = alert else { return "" }
            return external?.country == a.from
                ? "Была смена \(a.from) → \(a.to), сейчас снова \(a.from)"
                : "\(a.from) → \(a.to): сервисы видят другую страну"
        case .off: return "Включите VPN кнопкой справа"
        case .unknown: return "Подождите несколько секунд"
        }
    }
}

/// A request from the widget to the agent, passed through a file because the widget is sandboxed.
public enum Command: String, Codable, Sendable {
    case toggle, refreshSubscription, dismissAlert
}

public struct Config: Codable, Equatable, Sendable {
    public var subscriptionURL: String?
    /// Part of the server name the user normally connects through, e.g. "Эстония".
    public var pinned: String?
    /// Bundle id of the VPN configuration to watch and control.
    public var vpnBundleID: String
    public var refreshHours: Double

    public init(subscriptionURL: String? = nil, pinned: String? = nil, vpnBundleID: String = "su.ffg.happ", refreshHours: Double = 1) {
        self.subscriptionURL = subscriptionURL
        self.pinned = pinned
        self.vpnBundleID = vpnBundleID
        self.refreshHours = refreshHours
    }
}
