import WidgetKit
import SwiftUI
import AppIntents
import VPNCore
import VPNUI

/// Runs when the power or refresh button on the widget is pressed. The widget is sandboxed and cannot control the VPN,
/// so it only leaves a command for the agent, which does the actual work and rewrites the state.
struct SendCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Команда VPN"
    static let description = IntentDescription("Включает или выключает VPN, обновляет подписку.")

    @Parameter(title: "Команда")
    var command: String

    init() {}

    init(command: Command) {
        self.command = command.rawValue
    }

    func perform() async throws -> some IntentResult {
        if let cmd = Command(rawValue: command) {
            Storage.save(cmd, to: Paths.command)
            // Show "Включаю…" right away; the agent replaces it with the real state within a couple of seconds.
            if var state = Storage.loadState() {
                state.busy = cmd == .toggle ? "Переключаю…" : "Обновляю подписку…"
                Storage.save(state, to: Paths.state)
            }
            WidgetCenter.shared.reloadTimelines(ofKind: VPNStatusWidget.kind)
        }
        return .result()
    }
}

struct VPNEntry: TimelineEntry {
    let date: Date
    let state: VPNState
}

struct VPNProvider: TimelineProvider {
    func placeholder(in context: Context) -> VPNEntry {
        VPNEntry(date: Date(), state: Mock.state())
    }

    func getSnapshot(in context: Context, completion: @escaping (VPNEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries().first!)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VPNEntry>) -> Void) {
        completion(Timeline(entries: entries(), policy: .after(Date().addingTimeInterval(60))))
    }

    /// The host app asks for a reload on every change, but if the agent is not running the widget must not keep claiming
    /// "all fine": later entries carry a later date, so they flip to "no fresh data" on their own.
    private func entries() -> [VPNEntry] {
        let state = Storage.loadState() ?? VPNState(updated: .distantPast)
        let now = Date()
        return [0, VPNState.staleAfter + 5, 600].map { VPNEntry(date: now.addingTimeInterval($0), state: state) }
    }
}

struct VPNWidgetView: View {
    let entry: VPNEntry

    private let button: ActionButtonBuilder = { command, label in
        AnyView(Button(intent: SendCommandIntent(command: command)) { label }.buttonStyle(.plain))
    }

    var body: some View {
        VPNMediumView(state: entry.state, button: button)
            .widgetURL(URL(string: "vpnwidget://open"))
    }
}

struct VPNStatusWidget: Widget {
    static let kind = "VPNStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: VPNProvider()) { entry in
            VPNWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("VPN")
        .description("Состояние VPN, пинг до сервера и подписка. Включение и выключение одной кнопкой. Ставьте над большим виджетом NetWatch.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct VPNWidgetBundle: WidgetBundle {
    var body: some Widget {
        VPNStatusWidget()
    }
}
