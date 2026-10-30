import SwiftUI
import VPNCore

/// Wraps a label in whatever makes it tappable. Only the widget can do that (it needs an App Intent button),
/// so the shared views take it as a closure; previews leave it out and the controls are just drawn.
public typealias ActionButtonBuilder = (Command, AnyView) -> AnyView

enum Fmt {
    static func ms(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v < 10 ? String(format: "%.1f мс", v) : String(format: "%.0f мс", v)
    }

    static func bytes(_ b: Int64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1000 { return String(format: "%.1f ТБ", gb / 1024) }
        if gb >= 1 { return String(format: "%.0f ГБ", gb) }
        return String(format: "%.0f МБ", Double(b) / 1_048_576)
    }

    /// 3:07:01, the way Happ and the live widget timer show it.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
    }

    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// Latency reads as a color: fast green, slow amber, none red.
    /// `slow` is where green turns amber: a full request through a tunnel is naturally several times a bare TCP connect.
    static func pingColor(_ ms: Double?, full: Bool, slow: Double = 100) -> Color {
        guard full else { return Theme.text }
        guard let ms else { return Theme.bad }
        return ms < slow ? Theme.ok : (ms < slow * 2.5 ? Theme.warn : Theme.bad)
    }
}

// MARK: Header

struct PowerButton: View {
    let state: VPNState
    let full: Bool

    private var on: Bool { state.status == .connected || state.status == .connecting }

    var body: some View {
        ZStack {
            Circle().fill(on ? Theme.ok.opacity(full ? 0.20 : 0.28) : Color.white.opacity(0.10))
            Circle().strokeBorder(on ? Theme.ok.opacity(full ? 0.8 : 0.9) : Color.white.opacity(0.25), lineWidth: 1.5)
            Image(systemName: "power")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? (full ? Theme.ok : Theme.text) : Theme.muted)
        }
        .frame(width: 40, height: 40)
        .opacity(state.busy == nil ? 1 : 0.5)
    }
}

struct StatusHeader: View {
    private let style = RenderStyle()
    let s: VPNState
    var button: ActionButtonBuilder?

    private var verdict: Verdict { s.isStale() ? .unknown : s.verdict }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: verdict.symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(verdict.tint(fullColor: style.full))
                .shadow(color: style.full ? verdict.tint(fullColor: true).opacity(0.7) : .clear, radius: 4)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.busy ?? s.headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(s.isStale() ? "Агент не отвечает, данные устарели" : s.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            wrapped(.toggle, PowerButton(state: s, full: style.full))
        }
    }

    private func wrapped<V: View>(_ cmd: Command, _ view: V) -> AnyView {
        button?(cmd, AnyView(view)) ?? AnyView(view)
    }
}

// MARK: Metrics

struct Metric: View {
    let title: String
    let value: String
    var color: Color = Theme.text
    var size: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricsRow: View {
    private let style = RenderStyle()
    @Environment(\.staticNow) private var staticNow
    let s: VPNState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Metric(title: "До сервера", value: Fmt.ms(s.activeServer?.ms), color: Fmt.pingColor(s.activeServer?.ms, full: style.full))
            Metric(title: "Туннель", value: Fmt.ms(s.tunnelMs), color: s.status == .connected ? Fmt.pingColor(s.tunnelMs, full: style.full, slow: 300) : Theme.muted)
            Metric(title: s.external?.country.map { "Адрес · \($0)" } ?? "Адрес", value: s.external?.ip ?? "—", size: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text("В сети").font(.system(size: 10)).foregroundStyle(Theme.muted)
                if let since = s.since, s.status == .connected {
                    Group {
                        if let staticNow {
                            Text(Fmt.clock(staticNow.timeIntervalSince(since)))
                        } else {
                            Text(timerInterval: since...Date.distantFuture, pauseTime: nil, countsDown: false, showsHours: true)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                } else {
                    Text("—").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(s.isStale() ? 0.4 : 1)
    }
}

// MARK: Servers

struct ServerRow: View {
    private let style = RenderStyle()
    let ping: ServerPing
    let active: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(active ? Theme.accent : Color.clear)
                .overlay(Circle().strokeBorder(active ? Color.clear : Theme.faint, lineWidth: 1))
                .frame(width: 7, height: 7)
            Text(ping.server.name)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.text : Theme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            PingBar(ms: ping.ms, color: Fmt.pingColor(ping.ms, full: style.full))
            Text(ping.ms.map { String(format: "%.0f", $0) } ?? "×")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Fmt.pingColor(ping.ms, full: style.full))
                .frame(width: 28, alignment: .trailing)
        }
    }
}

/// A short bar whose length is the latency (full at 300 ms), so a list of servers is comparable at a glance.
struct PingBar: View {
    let ms: Double?
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.faint).frame(width: 54, height: 3)
            if let ms { Capsule().fill(color).frame(width: max(3, 54 * min(ms / 300, 1)), height: 3) }
        }
    }
}

// MARK: Exit alert

/// Replaces the bottom line while a country change is pending. Pressing it accepts the new country.
struct AlertRow: View {
    private let style = RenderStyle()
    let alert: ExitAlert
    let current: String?
    var button: ActionButtonBuilder?

    var body: some View {
        let accept = HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold))
            Text(current == alert.from ? "Понятно, всё снова \(alert.from)" : "Принять \(current ?? alert.to) как обычную")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(style.full ? Theme.text : Theme.text)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background((style.full ? Theme.bad : Color.white).opacity(0.22), in: Capsule())
        if let button { button(.dismissAlert, AnyView(accept)) } else { accept }
    }
}

// MARK: Subscription

struct SubscriptionRow: View {
    private let style = RenderStyle()
    let s: VPNState
    var button: ActionButtonBuilder?

    var body: some View {
        let sub = s.subscription
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(sub.title ?? (sub.fetched == nil ? "Подписка не подключена" : "Подписка"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let e = sub.error {
                        Text(e).font(.system(size: 10)).foregroundStyle(style.full ? Theme.warn : Theme.text).lineLimit(1)
                    } else if let f = sub.fetched {
                        Text("обновлена \(Fmt.time(f))").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                if let total = sub.totalBytes, let used = sub.usedBytes {
                    TrafficBar(fraction: Double(used) / Double(max(total, 1)))
                    Text("\(Fmt.bytes(used)) из \(Fmt.bytes(total))" + (sub.expires.map { " · до \(Fmt.date($0))" } ?? ""))
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                } else if let exp = sub.expires {
                    Text("до \(Fmt.date(exp))").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 4)
            let refresh = ZStack {
                Circle().fill(Color.white.opacity(0.10))
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
            }.frame(width: 28, height: 28)
            if let button { button(.refreshSubscription, AnyView(refresh)) } else { refresh }
        }
    }
}

struct TrafficBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.faint)
                Capsule().fill(Theme.accent).frame(width: max(3, g.size.width * min(fraction, 1)))
            }
        }
        .frame(height: 4)
    }
}
