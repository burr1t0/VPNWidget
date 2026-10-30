import Foundation

/// Files shared between the agent and the widget. Built from the real home directory: inside a sandboxed widget,
/// FileManager's Application Support points into its container.
public enum Paths {
    public static var dir: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/VPNWidget", isDirectory: true)
    }

    public static var state: URL { dir.appendingPathComponent("state.json") }
    public static var config: URL { dir.appendingPathComponent("config.json") }
    public static var command: URL { dir.appendingPathComponent("command.json") }
    public static var servers: URL { dir.appendingPathComponent("servers.json") }
    public static var discovered: URL { dir.appendingPathComponent("discovered.json") }
}

public enum Storage {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Atomic, so the widget never reads half a file.
    public static func save<T: Encodable>(_ value: T, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        // The config can hold a subscription link that works like a password.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func loadState() -> VPNState? { load(VPNState.self, from: Paths.state) }
    public static func loadConfig() -> Config { load(Config.self, from: Paths.config) ?? Config() }
}
