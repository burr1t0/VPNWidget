import XCTest
@testable import VPNCore

final class ParsingTests: XCTestCase {
    func testSubscriptionPlainList() {
        let body = """
        vless://uuid@de.example.com:443?security=reality&type=tcp#%D0%93%D0%B5%D1%80%D0%BC%D0%B0%D0%BD%D0%B8%D1%8F
        trojan://pw@fi.example.com:8443#Finland
        """
        let servers = Subscription.parse(body: body)
        XCTAssertEqual(servers.map(\.name), ["Германия", "Finland"])
        XCTAssertEqual(servers.map(\.port), [443, 8443])
    }

    func testSubscriptionBase64() {
        let raw = "vless://uuid@ee.example.com:443#Estonia"
        let encoded = Data(raw.utf8).base64EncodedString()
        XCTAssertEqual(Subscription.parse(body: encoded).first?.host, "ee.example.com")
    }

    func testUserInfoHeader() {
        let info = Subscription.parseHeaders { $0 == "subscription-userinfo" ? "upload=10; download=90; total=1000; expire=1788000000" : nil }
        XCTAssertEqual(info.usedBytes, 100)
        XCTAssertEqual(info.totalBytes, 1000)
        XCTAssertNotNil(info.expires)
    }

    func testScutilStatus() {
        let text = """
        Connected
        Extended Status <dictionary> {
          DNSServers : <array> {
            0 : 1.1.1.1
          }
          IPv4 : <dictionary> {
            InterfaceName : utun36
          }
          LastStatusChangeTime : 10/29/2026 23:05:35
        }
        """
        let r = TunnelReader.parse(text, service: "X")
        XCTAssertEqual(r.status, .connected)
        XCTAssertEqual(r.interface, "utun36")
        XCTAssertEqual(r.dns, "1.1.1.1")
        XCTAssertNotNil(r.since)
    }

    func testServiceLookupByBundle() {
        let list = "* (Connected)      080084A9-1694-413F-A73C-8F4E8E03E147 VPN (su.ffg.happ)  \"Happ\"   [VPN:su.ffg.happ]"
        XCTAssertEqual(TunnelReader.serviceID(in: list, bundleID: "su.ffg.happ"), "080084A9-1694-413F-A73C-8F4E8E03E147")
    }

    func testActiveServerIsTheEndpointMatchingExternalIP() {
        let lsof = """
        Tunnel 1 user 10u IPv4 0x1 0t0 TCP 192.168.1.10:65220->203.0.113.27:443 (ESTABLISHED)
        Tunnel 1 user 11u IPv4 0x2 0t0 TCP 192.168.1.10:65133->198.51.100.7:443 (ESTABLISHED)
        Tunnel 1 user 12u IPv4 0x3 0t0 TCP 127.0.0.1:65367->127.0.0.1:10808 (ESTABLISHED)
        """
        let hit = ActiveServer.endpoint(in: lsof, matching: "203.0.113.27")
        XCTAssertEqual(hit?.host, "203.0.113.27")
        XCTAssertEqual(hit?.port, 443)
        XCTAssertNil(ActiveServer.endpoint(in: lsof, matching: "9.9.9.9"))
    }

    func testCloudflareTrace() {
        let text = "fl=1\nip=203.0.113.10\nloc=EE\ncolo=TLL\n"
        let r = Probes.parseTrace(text)
        XCTAssertEqual(r?.ip, "203.0.113.10")
        XCTAssertEqual(r?.country, "EE")
        XCTAssertNil(Probes.parseTrace("nothing useful"))
    }

    func testExitChangeIsAnAlertUntilDismissed() {
        var s = VPNState(status: .connected, tunnelMs: 100, external: ExternalIP(ip: "1.1.1.1", country: "DE"),
                         servers: [ServerPing(server: Server(name: "EE", host: "h", port: 1), ms: 30)],
                         baselineCountry: "EE", alert: ExitAlert(from: "EE", to: "DE"))
        XCTAssertEqual(s.verdict, .exitChanged)
        XCTAssertTrue(s.detail.contains("EE → DE"))
        s.external = ExternalIP(ip: "2.2.2.2", country: "EE")
        XCTAssertTrue(s.detail.contains("снова EE"))
        s.alert = nil
        XCTAssertEqual(s.verdict, .ok)
    }

    func testReportGroupsOutagesByExitAddress() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            Event(t: t0, kind: .connected, ip: "1.1.1.1", country: "EE"),
            Event(t: t0.addingTimeInterval(60), kind: .problem, ip: "1.1.1.1", country: "EE", verdict: .noTraffic, tunnelMs: nil, serverMs: 17),
            Event(t: t0.addingTimeInterval(180), kind: .recovered, ip: "1.1.1.1", seconds: 120),
            Event(t: t0.addingTimeInterval(300), kind: .connected, ip: "2.2.2.2", country: "EE"),
        ]
        let text = Report.text(events: events, since: t0)
        XCTAssertTrue(text.contains("Подключений: 2, сбоев: 1"))
        XCTAssertTrue(text.contains("1.1.1.1 (EE): подключений 1, сбоев 1"))
        XCTAssertTrue(text.contains("2.2.2.2 (EE): подключений 1, сбоев 0"))
        XCTAssertTrue(text.contains("сервер отвечает, туннель нет"))
    }

    func testVerdict() {
        var s = VPNState(status: .connected, tunnelMs: 120, servers: [ServerPing(server: Server(name: "EE", host: "h", port: 1), ms: 30)])
        XCTAssertEqual(s.verdict, .ok)
        s.tunnelMs = nil
        XCTAssertEqual(s.verdict, .noTraffic)
        s.servers[0].ms = nil
        XCTAssertEqual(s.verdict, .serverDown)
        s.tunnelMs = 100
        s.external = ExternalIP(ip: "1.2.3.4", country: "RU")
        XCTAssertEqual(s.verdict, .leak)
    }
}
