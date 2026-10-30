import Foundation
import VPNCore

setvbuf(stdout, nil, _IOLBF, 0)

func usage() -> Never {
    print("""
    vpnd — агент виджета VPN (наблюдает за Happ, туннель сам не трогает)

      vpnd run                    фоновый цикл: статус, пинги, подписка → state.json
      vpnd once                   один проход и вывод состояния
      vpnd subscription <url>     запомнить ссылку подписки и сразу загрузить список серверов
      vpnd pin <часть названия>   какой сервер считать основным, например: vpnd pin Эстония
      vpnd servers                серверы из последней загрузки подписки
      vpnd report [--hours N]     тихий журнал сбоев VPN: по каким адресам выхода и сколько (по умолчанию 24 ч)

    Данные: \(Paths.dir.path)
    """)
    exit(64)
}

func describe(_ s: VPNState) {
    print("статус: \(s.status.rawValue)\(s.since.map { ", с \($0)" } ?? "")  интерфейс: \(s.interface ?? "—")  DNS: \(s.dns ?? "—")")
    print("вердикт: \(s.headline) — \(s.detail)")
    print("туннель: \(s.tunnelMs.map { String(format: "%.0f мс", $0) } ?? "—")  внешний адрес: \(s.external.map { "\($0.ip) (\($0.country ?? "?"))" } ?? "—")")
    print("путь: \(s.path ?? "—")")
    for p in s.servers { print(String(format: "  %@ %@:%d %@", p.server.name, p.server.host, p.server.port, p.ms.map { String(format: "%.0f мс", $0) } ?? "нет ответа")) }
    if let e = s.subscription.error { print("подписка: \(e)") }
}

let args = Array(CommandLine.arguments.dropFirst())

switch args.first ?? "run" {
case "run":
    let agent = Agent()
    print("vpnd запущен, данные: \(Paths.dir.path)")
    await agent.run()

case "once":
    let agent = Agent(journal: false)
    await agent.step()
    await agent.checkExit()
    if let s = Storage.loadState() { describe(s) }

case "subscription":
    guard args.count >= 2, URL(string: args[1])?.scheme?.hasPrefix("http") == true else { usage() }
    var config = Storage.loadConfig()
    config.subscriptionURL = args[1]
    Storage.save(config, to: Paths.config)
    let agent = Agent(journal: false)
    await agent.refreshSubscription()
    await agent.step()
    await agent.checkExit()
    if let s = Storage.loadState() { describe(s) }

case "pin":
    guard args.count >= 2 else { usage() }
    var config = Storage.loadConfig()
    config.pinned = args.dropFirst().joined(separator: " ")
    Storage.save(config, to: Paths.config)
    print("Основной сервер: \(config.pinned!)")

case "report":
    let hours = args.firstIndex(of: "--hours").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 24
    let since = Date().addingTimeInterval(-hours * 3600)
    print(Report.text(events: EventLog.load(since: since), since: since))

case "servers":
    let list = Storage.load([Server].self, from: Paths.servers) ?? []
    if list.isEmpty { print("Список пуст: задайте подписку командой vpnd subscription <url>") }
    for s in list { print("\(s.name)  \(s.host):\(s.port)") }

default:
    usage()
}
