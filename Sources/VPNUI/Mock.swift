import Foundation
import VPNCore

/// Synthetic states for previews and tests; nothing here comes from a real subscription.
public enum Mock {
    static let servers: [Server] = [
        Server(name: "Европа (Быстрый)", host: "eu.example.net", port: 443),
        Server(name: "Германия", host: "de.example.net", port: 443),
        Server(name: "Финляндия", host: "fi.example.net", port: 443),
        Server(name: "Эстония", host: "ee.example.net", port: 443),
        Server(name: "Польша", host: "pl.example.net", port: 443),
        Server(name: "Нидерланды", host: "nl.example.net", port: 443),
        Server(name: "Франция", host: "fr.example.net", port: 443),
    ]

    public static func state(now: Date = Date(), status: TunnelStatus = .connected, tunnelMs: Double? = 107, serverDown: Bool = false, withSubscription: Bool = true, exitChanged: Bool = false,
                              country: String = "EE", busy: String? = nil, connectedFor: TimeInterval = 3 * 3600 + 421, updated: Date? = nil) -> VPNState {
        let ms: [Double?] = [64, 52, 38, 31, 70, 58, 210]
        let pings = zip(servers, ms).map { ServerPing(server: $0, ms: serverDown ? nil : $1) }
        return VPNState(
            updated: updated ?? now, status: status, since: status == .connected ? now.addingTimeInterval(-connectedFor) : nil,
            interface: "utun4", dns: "1.1.1.1", tunnelMs: status == .connected ? tunnelMs : nil,
            external: status == .connected ? ExternalIP(ip: "203.0.113.27", country: exitChanged ? "DE" : country) : nil,
            servers: Array(pings.prefix(withSubscription ? 7 : 1)), pinned: "Эстония",
            subscription: withSubscription
                ? SubscriptionInfo(title: "Моя подписка", usedBytes: 21_000_000_000, totalBytes: 1_000_000_000_000,
                                   expires: now.addingTimeInterval(14 * 86_400), fetched: now.addingTimeInterval(-1500))
                : SubscriptionInfo(),
            path: "роутер 3.8 · интернет 14 · DNS 21 мс",
            busy: busy,
            baselineCountry: exitChanged ? "EE" : country, alert: exitChanged ? ExitAlert(from: "EE", to: "DE", at: now) : nil
        )
    }
}
