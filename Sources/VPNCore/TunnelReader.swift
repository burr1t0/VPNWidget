import Foundation

/// Reads the state of a Network Extension VPN through `scutil --nc`, which needs no privileges.
public struct TunnelReader {
    public struct Reading: Equatable {
        public var service: String
        public var status: TunnelStatus
        public var since: Date?
        public var interface: String?
        public var dns: String?
    }

    let bundleID: String

    public init(bundleID: String) {
        self.bundleID = bundleID
    }

    /// The service id (UUID) of the configuration, found by its bundle id so a renamed VPN is still recognised.
    func serviceID() -> String? {
        guard let list = Shell.run("/usr/sbin/scutil", ["--nc", "list"]) else { return nil }
        return Self.serviceID(in: list, bundleID: bundleID)
    }

    static func serviceID(in list: String, bundleID: String) -> String? {
        for line in list.split(separator: "\n") where line.contains("[VPN:\(bundleID)]") || line.contains("VPN (\(bundleID))") {
            if let r = line.range(of: #"[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}"#, options: .regularExpression) {
                return String(line[r])
            }
        }
        return nil
    }

    public func read() -> Reading? {
        guard let id = serviceID(), let text = Shell.run("/usr/sbin/scutil", ["--nc", "status", id]) else { return nil }
        return Self.parse(text, service: id)
    }

    static func parse(_ text: String, service: String) -> Reading {
        let first = text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let status: TunnelStatus
        switch first {
        case "Connected": status = .connected
        case "Connecting": status = .connecting
        case "Disconnecting": status = .disconnecting
        case "Disconnected": status = .disconnected
        default: status = .unknown
        }
        var since: Date?
        if let r = text.range(of: #"LastStatusChangeTime : (.+)"#, options: .regularExpression) {
            let raw = text[r].replacingOccurrences(of: "LastStatusChangeTime : ", with: "").trimmingCharacters(in: .whitespaces)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MM/dd/yyyy HH:mm:ss"
            since = f.date(from: raw)
        }
        let interface = text.range(of: #"InterfaceName : (utun\d+)"#, options: .regularExpression)
            .map { String(text[$0]).replacingOccurrences(of: "InterfaceName : ", with: "") }
        // DNS servers are listed as "0 : 1.1.1.1" right under "DNSServers".
        var dns: String?
        if let r = text.range(of: #"DNSServers : <array> \{\s*0 : \S+"#, options: .regularExpression) {
            dns = text[r].split(separator: " ").last.map(String.init)
        }
        return Reading(service: service, status: status, since: since, interface: interface, dns: dns)
    }

    /// Starts or stops the tunnel. Only ever called when the user presses the button, never by tests or the agent on its own.
    @discardableResult
    public func setEnabled(_ on: Bool) -> Bool {
        guard let id = serviceID() else { return false }
        return Shell.run("/usr/sbin/scutil", ["--nc", on ? "start" : "stop", id], timeout: 10) != nil
    }
}
