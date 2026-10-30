import Foundation

/// The background loop. It only observes and writes `state.json`; the tunnel is switched only when the user
/// asks through the widget (a `toggle` command), never on its own.
///
/// Commands (the power button) are handled by their own fast loop: the measuring loop can be busy for ten seconds
/// waiting on network timeouts, and a button press must not wait behind it.
public actor Agent {
    private var config = Storage.loadConfig()
    private var state = Storage.loadState() ?? VPNState()
    private var subscribed: [Server] = Storage.load([Server].self, from: Paths.servers) ?? []
    /// The server seen in the tunnel's connections; remembered so it is still pinged while the VPN is off.
    private var discovered: Server? = Storage.load(Server.self, from: Paths.discovered)

    /// The subscription list, plus the discovered server when the list does not already contain that host.
    private var servers: [Server] {
        guard let d = discovered, !subscribed.contains(where: { $0.host == d.host }) else { return subscribed }
        return [d] + subscribed
    }
    private var lastPing = Date.distantPast
    private var lastFetch = Date.distantPast
    private var lastConfigStamp: Date?
    private var recorder = EventRecorder()
    private var onUpdate: (@Sendable (VPNState) -> Void)?
    private var onAlert: (@Sendable (_ title: String, _ body: String) -> Void)?

    /// Only the long-running agent keeps the journal; one-off CLI runs must not add duplicate "connected" lines.
    private let journal: Bool

    public init(journal: Bool = true) {
        self.journal = journal
    }

    public func setOnUpdate(_ handler: @escaping @Sendable (VPNState) -> Void) {
        onUpdate = handler
    }

    /// Called when something needs the user's attention right now (the exit country changed, a leak).
    public func setOnAlert(_ handler: @escaping @Sendable (_ title: String, _ body: String) -> Void) {
        onAlert = handler
    }

    public func run() async {
        Task { await self.commandLoop() }
        Task { await self.exitLoop() }
        while true {
            await step()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func commandLoop() async {
        while true {
            if let cmd = takeCommand() { await handle(cmd) }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// Checks the exit address every few seconds while the tunnel is up. A change of country is what the user must hear about
    /// at once, so this runs apart from the slower measurements.
    private func exitLoop() async {
        while true {
            await checkExit()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    public func checkExit() async {
        guard state.status == .connected, let found = await Probes.externalIP(), state.status == .connected else { return }
        let before = state
        state.external = found
        if let hit = ActiveServer.discover(externalIP: found.ip) {
            let server = Server(name: ActiveServer.name(forCountry: found.country), host: hit.host, port: hit.port)
            if server != discovered {
                discovered = server
                Storage.save(server, to: Paths.discovered)
                lastPing = .distantPast
            }
        }
        evaluateExit(found)
        if state != before { publish() }
    }

    /// The first country seen becomes the one the user accepts; any other raises an alert that stays until dismissed.
    private func evaluateExit(_ found: ExternalIP) {
        guard let country = found.country?.uppercased() else { return }
        // Right after connecting the address can still be the old one for a moment; do not cry wolf about that.
        if let since = state.since, Date().timeIntervalSince(since) < 10 { return }
        guard let baseline = state.baselineCountry else {
            if country != "RU" { state.baselineCountry = country } // a Russian first reading is a leak, not a norm
            return
        }
        if country == "RU" {
            // A Russian address through the tunnel is a leak; the widget shows it by itself, here only the sound.
            if state.alert?.to != country {
                state.alert = ExitAlert(from: baseline, to: country)
                onAlert?("Утечка: виден российский адрес", "Трафик идёт мимо VPN. Проверьте подключение.")
            }
        } else if country != baseline, state.alert?.to != country {
            state.alert = ExitAlert(from: baseline, to: country)
            onAlert?("Сменилась страна выхода: \(baseline) → \(country)", "Сервисы видят другую страну. Откройте виджет, чтобы принять или переподключиться.")
        }
    }

    private func handle(_ cmd: Command) async {
        switch cmd {
        case .toggle:
            let reader = TunnelReader(bundleID: config.vpnBundleID)
            let on = state.status == .disconnected || state.status == .unknown
            state.busy = on ? "Включаю…" : "Выключаю…"
            publish()
            reader.setEnabled(on)
            // Follow the real transition instead of guessing a delay, so the widget changes the moment the tunnel does.
            let target: TunnelStatus = on ? .connected : .disconnected
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let r = reader.read() else { continue }
                if r.status != state.status {
                    apply(r)
                    publish()
                }
                if r.status == target { break }
            }
        case .refreshSubscription:
            state.busy = "Обновляю подписку…"
            publish()
            await refreshSubscription()
        case .dismissAlert:
            // Accepting means: this is the country I am in now, stop comparing against the old one.
            if let current = state.external?.country?.uppercased(), current != "RU" { state.baselineCountry = current }
            state.alert = nil
        }
        state.busy = nil
        lastPing = .distantPast
        publish()
    }

    private func apply(_ r: TunnelReader.Reading) {
        state.status = r.status
        state.since = r.status == .connected ? r.since : nil
        state.interface = r.interface
        state.dns = r.dns
        if r.status != .connected {
            state.external = nil
            state.tunnelMs = nil
        }
    }

    public func step() async {
        reloadConfigIfChanged()
        let reader = TunnelReader(bundleID: config.vpnBundleID)

        if let r = reader.read() {
            apply(r)
        } else {
            state.status = .unknown
        }
        state.pinned = config.pinned
        state.updated = Date()
        publish() // the status first: the slow measurements below must not delay it

        if Date().timeIntervalSince(lastFetch) > config.refreshHours * 3600 { await refreshSubscription() }

        let now = Date()
        if now.timeIntervalSince(lastPing) >= 15 {
            lastPing = now
            // Right after connecting the first requests through the tunnel are slow (routes and DNS are still warming up);
            // one throwaway request keeps that from showing up as a 3-second "tunnel latency".
            let fresh = state.since.map { now.timeIntervalSince($0) < 60 } ?? false
            let connected = state.status == .connected
            async let http: Double? = connected ? Probes.httpsMs(warmUp: fresh) : nil
            let pings = await pingAll()
            state.servers = pings
            state.tunnelMs = await http
        }
        state.path = NetWatchBridge.summary()
        state.updated = Date()
        publish()
    }

    private func pingAll() async -> [ServerPing] {
        await withTaskGroup(of: (Int, Double?).self) { group in
            for (i, s) in servers.enumerated() {
                group.addTask { (i, await Probes.tcpPing(host: s.host, port: s.port)) }
            }
            var ms = [Int: Double?]()
            for await (i, v) in group { ms[i] = v }
            return servers.enumerated().map { ServerPing(server: $1, ms: ms[$0] ?? nil) }
        }
    }

    public func refreshSubscription() async {
        lastFetch = Date()
        // The link is optional: without it the widget still works from the server discovered in the tunnel.
        guard let url = config.subscriptionURL else {
            state.subscription.error = nil // an error saved by an older run would otherwise stay on the widget forever
            return
        }
        if let result = await Subscription.fetch(urlString: url) {
            subscribed = result.servers
            Storage.save(subscribed, to: Paths.servers)
            state.subscription = result.info
        } else {
            // Keep the old list and info: a failed refresh must not empty the widget.
            state.subscription.error = "Не удалось обновить подписку"
        }
    }

    private func reloadConfigIfChanged() {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: Paths.config.path)[.modificationDate]) as? Date
        guard stamp != lastConfigStamp else { return }
        lastConfigStamp = stamp
        let old = config.subscriptionURL
        config = Storage.loadConfig()
        if config.subscriptionURL != old { lastFetch = .distantPast }
    }

    /// A command file is consumed once: the widget writes it, the agent reads and removes it.
    private func takeCommand() -> Command? {
        guard let cmd = Storage.load(Command.self, from: Paths.command) else { return nil }
        try? FileManager.default.removeItem(at: Paths.command)
        return cmd
    }

    private func publish() {
        if journal { recorder.record(state, server: discovered?.host) }
        Storage.save(state, to: Paths.state)
        onUpdate?(state)
    }
}

/// Reads the newest measurement of the NetWatch agent, if it runs, to show which part of the path is slow.
enum NetWatchBridge {
    static func summary() -> String? {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let file = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/NetWatch/samples-\(f.string(from: Date())).jsonl")
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 8192 ? size - 8192 : 0)
        guard let tail = try? handle.readToEnd(), let text = String(data: tail, encoding: .utf8),
              let last = text.split(separator: "\n").last,
              let obj = try? JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any] else { return nil }
        func ms(_ v: Any?) -> String? { (v as? Double).map { $0 < 10 ? String(format: "%.1f", $0) : String(format: "%.0f", $0) } }
        let parts = [
            ms((obj["gw"] as? [String: Any])?["avgMs"]).map { "роутер \($0)" },
            ms((obj["direct"] as? [String: Any])?["avgMs"]).map { "интернет \($0)" },
            ms(obj["dnsMs"]).map { "DNS \($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + " мс"
    }
}
