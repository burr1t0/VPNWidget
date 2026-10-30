import AppKit
import SwiftUI
import ServiceManagement
import WidgetKit
import UserNotifications
import VPNCore

/// Hosts the agent (the widget is sandboxed and cannot run it) and keeps the widget fresh.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let agent = Agent()
    private var window: NSWindow?
    private var lastKey = ""
    private var lastReload = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        Task.detached { [agent] in
            await agent.setOnUpdate { [weak self] state in self?.reloadWidgetIfNeeded(state) }
            await agent.setOnAlert { title, body in AppDelegate.notify(title: title, body: body) }
            await agent.run()
        }

        // First launch: start at login (the widget only stays live while this app runs) and open settings once,
        // which is also where the subscription link goes.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "onboarded") {
            defaults.set(true, forKey: "onboarded")
            try? SMAppService.mainApp.register()
            showWindow()
        }
    }

    /// A notification plus a system alert sound. The sound is played directly as well: a banner alone is easy to miss,
    /// and this is the one event the user wants to react to immediately.
    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        DispatchQueue.main.async { NSSound(named: "Sosumi")?.play() }
    }

    // Show the banner even while the app is frontmost (its settings window is open).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// WidgetKit refreshes on its own budget, far too slowly for a live status: ask for a reload when what the widget
    /// shows changes, and at most once a minute otherwise.
    private func reloadWidgetIfNeeded(_ s: VPNState) {
        let key = "\(s.status.rawValue)|\(s.verdict.rawValue)|\(s.busy ?? "")|\(s.servers.count)"
        let now = Date()
        guard key != lastKey || now.timeIntervalSince(lastReload) >= 60 else { return }
        lastKey = key
        lastReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// A tap on the widget arrives as vpnwidget://open and brings up Happ, which is where the user goes to change servers.
    /// Our own settings window opens only when the app itself is opened (see applicationShouldHandleReopen).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "vpnwidget" }) else { return }
        guard let happ = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "su.ffg.happ") else {
            showWindow()
            return
        }
        NSWorkspace.shared.openApplication(at: happ, configuration: NSWorkspace.OpenConfiguration())
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showWindow() {
        if window == nil {
            // Measure once off-window and fix the size: letting SwiftUI size the window can loop in AppKit layout.
            let size = NSHostingView(rootView: SettingsView()).fittingSize
            let host = NSHostingController(rootView: SettingsView())
            host.sizingOptions = []
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.contentViewController = host
            w.setContentSize(size)
            w.title = "VPN Widget"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
