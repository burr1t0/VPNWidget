import Foundation

/// Text report over the journal: which exit addresses had trouble and how much.
public enum Report {
    public static func text(events: [Event], since: Date, now: Date = Date()) -> String {
        guard !events.isEmpty else { return "Журнал пока пуст: за этот период не было ни подключений, ни сбоев." }
        let time = DateFormatter()
        time.dateFormat = "dd.MM HH:mm"

        // Pair every problem with the recovery that closed it; an unfinished one lasts until now.
        struct Outage { var start: Date; var seconds: Double; var event: Event; var open: Bool }
        var outages: [Outage] = []
        var open: Event?
        for e in events.sorted(by: { $0.t < $1.t }) {
            switch e.kind {
            case .problem: open = e
            case .recovered:
                if let p = open {
                    outages.append(Outage(start: p.t, seconds: e.seconds ?? e.t.timeIntervalSince(p.t), event: p, open: false))
                    open = nil
                }
            default: break
            }
        }
        if let p = open { outages.append(Outage(start: p.t, seconds: now.timeIntervalSince(p.t), event: p, open: true)) }

        let connections = events.filter { $0.kind == .connected }
        let total = outages.reduce(0) { $0 + $1.seconds }
        var out = ["Журнал VPN с \(time.string(from: since))",
                   "Подключений: \(connections.count), сбоев: \(outages.count), суммарно без трафика: \(duration(total))", ""]

        // Per exit address: the question the journal exists for.
        let addresses = Set(connections.compactMap(\.ip) + outages.compactMap(\.event.ip)).sorted()
        if !addresses.isEmpty {
            out.append("По адресам выхода:")
            for ip in addresses {
                let c = connections.filter { $0.ip == ip }
                let o = outages.filter { $0.event.ip == ip }
                let country = (c.first?.country ?? o.first?.event.country).map { " (\($0))" } ?? ""
                out.append("  \(ip)\(country): подключений \(c.count), сбоев \(o.count), без трафика \(duration(o.reduce(0) { $0 + $1.seconds }))")
            }
            out.append("")
        }

        if outages.isEmpty {
            out.append("Сбоев не было.")
        } else {
            out.append("Сбои:")
            for o in outages {
                let what = o.event.verdict == .serverDown ? "сервер не отвечает" : "сервер отвечает, туннель нет"
                let details = [o.event.serverMs.map { "до сервера \(Int($0)) мс" }, o.event.tunnelMs.map { "туннель \(Int($0)) мс" }]
                    .compactMap { $0 }.joined(separator: ", ")
                out.append("  \(time.string(from: o.start))  \(duration(o.seconds))\(o.open ? " (ещё идёт)" : "")  \(o.event.ip ?? "—")  \(what)\(details.isEmpty ? "" : " (\(details))")")
            }
        }
        return out.joined(separator: "\n")
    }

    static func duration(_ s: Double) -> String {
        let n = Int(s.rounded())
        if n < 60 { return "\(n) с" }
        if n < 3600 { return "\(n / 60) мин \(n % 60) с" }
        return "\(n / 3600) ч \(n % 3600 / 60) мин"
    }
}
