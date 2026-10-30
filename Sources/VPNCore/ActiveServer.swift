import Foundation

/// Finds the server the VPN app is connected to by looking at the tunnel process's open connections.
/// Needs no subscription link and sends nothing to the provider, so it cannot use up a device slot.
public enum ActiveServer {
    /// The tunnel extension also holds direct connections (split routing sends Russian sites outside the tunnel),
    /// so the server is the remote endpoint whose address is the one the internet sees us as.
    public static func discover(externalIP: String?) -> (host: String, port: Int)? {
        guard let externalIP, let pid = tunnelPID(),
              let out = Shell.run("/usr/sbin/lsof", ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:ESTABLISHED"]) else { return nil }
        return endpoint(in: out, matching: externalIP)
    }

    static func endpoint(in lsof: String, matching ip: String) -> (host: String, port: Int)? {
        for line in lsof.split(separator: "\n") {
            guard let r = line.range(of: #"->(\d+\.\d+\.\d+\.\d+):(\d+)"#, options: .regularExpression) else { continue }
            let parts = line[r].dropFirst(2).split(separator: ":")
            if parts.count == 2, parts[0] == ip, let port = Int(parts[1]) { return (String(parts[0]), port) }
        }
        return nil
    }

    private static func tunnelPID() -> Int32? {
        Shell.run("/usr/bin/pgrep", ["-f", "Happ.app/Contents/PlugIns/Tunnel.appex"])?
            .split(separator: "\n").first.flatMap { Int32($0) }
    }

    /// "Эстония" for "EE": the name the user knows the server by.
    public static func name(forCountry code: String?) -> String {
        guard let code else { return "Активный сервер" }
        return Locale(identifier: "ru").localizedString(forRegionCode: code) ?? code
    }
}
