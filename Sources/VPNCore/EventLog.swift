import Foundation

/// One line of the quiet journal: what happened, on which exit address, how the tunnel and the server looked at that moment.
public struct Event: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case connected, disconnected, problem, recovered
    }

    public var t: Date
    public var kind: Kind
    public var ip: String?
    public var country: String?
    public var server: String?
    /// For `problem`: which kind of failure; for `recovered`: how it ended.
    public var verdict: Verdict?
    public var tunnelMs: Double?
    public var serverMs: Double?
    /// For `recovered`: how long the problem lasted.
    public var seconds: Double?

    public init(t: Date = Date(), kind: Kind, ip: String? = nil, country: String? = nil, server: String? = nil,
                verdict: Verdict? = nil, tunnelMs: Double? = nil, serverMs: Double? = nil, seconds: Double? = nil) {
        self.t = t
        self.kind = kind
        self.ip = ip
        self.country = country
        self.server = server
        self.verdict = verdict
        self.tunnelMs = tunnelMs
        self.serverMs = serverMs
        self.seconds = seconds
    }
}

/// Append-only JSON Lines journal. It exists to answer "is one particular server address to blame?" after a few days;
/// nothing in the widget reads it.
public enum EventLog {
    public static var url: URL { Paths.dir.appendingPathComponent("events.jsonl") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func append(_ event: Event) {
        try? FileManager.default.createDirectory(at: Paths.dir, withIntermediateDirectories: true)
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0a)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    public static func load(since: Date) -> [Event] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? decoder.decode(Event.self, from: Data($0.utf8)) }
            .filter { $0.t >= since }
    }
}

/// Turns the state the agent publishes into journal lines, remembering only what it needs to spot a change.
struct EventRecorder {
    private var connection: String?
    private var problemStart: Date?
    private var wasConnected = false

    /// A fresh connection reports "no traffic" until its first measurement arrives; that is not a problem.
    private static let grace: TimeInterval = 20

    mutating func record(_ s: VPNState, server: String?, now: Date = Date()) {
        let connected = s.status == .connected
        if connected {
            let key = "\(s.since.map { String($0.timeIntervalSince1970) } ?? "-")|\(s.external?.ip ?? "-")"
            if s.external != nil, key != connection {
                connection = key
                wasConnected = true
                EventLog.append(Event(t: now, kind: .connected, ip: s.external?.ip, country: s.external?.country, server: server))
            }
        } else if wasConnected {
            wasConnected = false
            connection = nil
            EventLog.append(Event(t: now, kind: .disconnected))
        }

        let age = s.since.map { now.timeIntervalSince($0) } ?? .infinity
        let bad = connected && (s.verdict == .noTraffic || s.verdict == .serverDown) && age >= Self.grace && !s.isStale(now: now)
        if bad, problemStart == nil {
            problemStart = now
            EventLog.append(Event(t: now, kind: .problem, ip: s.external?.ip, country: s.external?.country, server: server,
                                  verdict: s.verdict, tunnelMs: s.tunnelMs, serverMs: s.activeServer?.ms))
        } else if !bad, let start = problemStart {
            problemStart = nil
            EventLog.append(Event(t: now, kind: .recovered, ip: s.external?.ip, country: s.external?.country, server: server,
                                  seconds: now.timeIntervalSince(start)))
        }
    }
}
