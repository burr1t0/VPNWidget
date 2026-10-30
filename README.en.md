<p align="center"><img src="docs/icon.png" width="128" alt="VPNWidget"></p>

<h1 align="center">VPNWidget</h1>

<p align="center">
  <b>A VPN widget for the macOS desktop: status, ping, a power button and an alarm when the exit country changes.</b><br>
  A layer on top of Happ: it still holds the tunnel, and this shows what is going on with it.
</p>

<p align="center">
  <a href="README.md">Русский</a> · English
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20WidgetKit-F05138?logo=swift&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

<p align="center"><img src="docs/widget-power.gif" width="408" alt="The widget: the VPN is switched off and on again with the button"></p>

---

## What it is

The VPN on a Mac is almost never switched off, yet the client's window takes a chunk of the screen. VPNWidget replaces that window with a
widget: you see whether the tunnel works and, if it does not, where exactly it breaks. It does not replace or fork the VPN client: the tunnel,
the servers and the rules stay with Happ.

> An unofficial project, not affiliated with the Happ developers. The app is named only to make clear what it works with.

| Part | What it does |
|---|---|
| <img src="docs/icons/status.svg" width="22" height="22" align="absmiddle"> **Status** | Whether the tunnel is up, how long, the exit address and country, the ping to the server and the response time through the tunnel |
| <img src="docs/icons/widget.svg" width="22" height="22" align="absmiddle"> **Power button** | Switches the VPN on and off right from the desktop; the widget follows the transition and changes the moment the tunnel does |
| <img src="docs/icons/alert.svg" width="22" height="22" align="absmiddle"> **Country-change alarm** | If the exit to the internet changes country (or a Russian address shows up), the widget turns red and a notification with a sound arrives, until you press "accept" |
| <img src="docs/icons/journal.svg" width="22" height="22" align="absmiddle"> **Quiet journal** | Failures and connections are written to a file together with the exit address; a report shows whether one particular address is to blame |
| <img src="docs/icons/subscription.svg" width="22" height="22" align="absmiddle"> **Subscription (optional)** | The subscription link gives the server list, traffic and expiry. Without it the widget works from the server it finds by itself |

License: [MIT](LICENSE).

---

## How it works

1. **The host app** (no Dock icon, starts at login) runs the agent inside: every couple of seconds it reads the VPN state through `scutil --nc`, no administrator rights needed.
2. **Measurements.** The TCP ping to the server is bound to the physical interface (otherwise the tunnel answers the handshake itself and shows a couple of milliseconds), the response time through the tunnel is an HTTPS request to `gstatic.com/generate_204`, the exit address and country come from Cloudflare's `cdn-cgi/trace` page every 5 seconds.
3. **The server is found by itself:** the tunnel extension has an open connection to the server, and its address matches the external one websites see. Nothing is sent to the provider.
4. **The widget** only draws what the agent wrote, and its buttons leave a command in a file for the agent: the widget is sandboxed and never touches the VPN itself.

---

## What it looks like

The animations are drawn in code from synthetic data (`scripts/make-gifs.sh`), so they contain nothing about a real connection.

### <img src="docs/icons/status.svg" width="24" height="24" align="absmiddle"> Trouble inside the tunnel

The network itself is fine: first the tunnel slows down, then requests stop going through, then the server is silent altogether. The widget tells these cases apart and says what to do.

<p align="center"><img src="docs/widget-incident.gif" width="408" alt="The widget: the tunnel slows down, requests fail, the server is silent, everything recovers"></p>

### <img src="docs/icons/alert.svg" width="24" height="24" align="absmiddle"> Exit country changes

The exit address changed country: services will see a different one. The widget stays red until you press "Accept".

<p align="center"><img src="docs/widget-exit-alert.gif" width="408" alt="The widget turns red when the exit country changes and calms down once confirmed"></p>

It sits nicely above the large widget of [NetWatch](https://github.com/burr1t0/NetWatch): that one shows graphs and incidents along the whole path (router, provider, DNS, VPN), this one is about the tunnel itself.

---

## Requirements

- macOS 15 or newer.
- Happ with its VPN profile installed in the system (visible in `scutil --nc list`). Tested with Happ 5.7.0 on macOS 26.
- Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen) to build the app and the widget.
- An Apple Development certificate (a free Apple ID is enough).

## Installation

```bash
scripts/install-app.sh    # app + widget → ~/Applications/VPNWidget.app (needs xcodegen)
```

Signing needs an Apple Development certificate: the team is detected from it automatically, or set it by hand:
`VPNWIDGET_TEAM=ABCDE12345 scripts/install-app.sh`. Replace the bundle identifiers (`com.egor.*`) with your own in `project.yml`.

To add the widget: right-click the desktop → "Edit Widgets" → VPN (medium size). A tap on the widget opens Happ.
The settings window (subscription link, main server) opens when you launch the app itself from `~/Applications`.

## Usage

The agent runs inside the app, but it can be used from the terminal too:

```bash
swift build -c release
.build/release/vpnd once                    # one pass: status, pings, exit country
.build/release/vpnd report --hours 72       # the quiet journal: which exit addresses had how many failures
.build/release/vpnd subscription <link>     # connect a subscription (optional)
.build/release/vpnd pin Estonia             # which server to treat as the main one
.build/release/vpnd servers                 # servers from the last subscription download
```

Data lives in `~/Library/Application Support/VPNWidget/` (state, settings, the `events.jsonl` journal).

## <img src="docs/icons/journal.svg" width="30" height="30" align="absmiddle"> Journal and report

Everything worth remembering is written to a file quietly: no notifications, no changes in the widget. For each failure the time, the exit address,
whether the server answered and how long it lasted are recorded. After a couple of days the report answers "is one of the addresses Happ lands on to blame":

```
By exit address:
  203.0.113.10 (EE): connections 3, failures 4, no traffic 6 min 12 s
  203.0.113.27 (EE): connections 5, failures 0, no traffic 0 s
```

The first 20 seconds after connecting do not count: right after switching on, the tunnel is still warming up.

## <img src="docs/icons/alert.svg" width="30" height="30" align="absmiddle"> What counts as a problem

| Verdict | Condition |
|---|---|
| Leak | the exit country is RU while the tunnel is on |
| Exit country changed | the country differs from the one you accepted as usual (the first one seen) |
| Server not answering | the tunnel is up, requests through it do not go, the server cannot be reached |
| Connected, but no traffic | the tunnel is up, the server answers, but requests through the tunnel do not |
| No fresh data | the agent has not refreshed the state for more than 45 seconds |

## Structure

- `Sources/VPNCore` — the core: status reading, pings, subscription, the agent, the journal and the report.
- `Sources/VPNUI` — the widget screen, shared by the widget and the previews.
- `Sources/vpnd` — the command-line tool.
- `App/` and `Widget/` — the host app (agent, notifications, settings) and the widget extension.
- `Tests/` — tests for subscription and status parsing, verdicts, country change and the report.
- `scripts/` — app installation, rebuilding the animations.

Also: `swift run vpn-preview build/previews` draws the widget into PNG files without WidgetKit; the app icon is drawn in code
(`swift run vpn-icon App/Assets.xcassets/AppIcon.appiconset`, README logo: `swift run vpn-icon --docs docs/icon.png`).

## Limitations

- There is no tunnel of its own and no traffic blocking (kill switch): the widget **notices** a country change or a leak and raises the alarm, but does not cut the network. Blocking needs administrator rights and a separate watchdog.
- The alarm comes after the change: some requests manage to leave with the new address.
- It works with a VPN profile in the system (a Network Extension), by default Happ (`su.ffg.happ`); another client is set in `config.json` (`vpnBundleID`).
- The widget is sandboxed and reads and writes the agent's folder through a temporary exception
  (`com.apple.security.temporary-exception.files.home-relative-path.read-write`). That does not suit the App Store, but is fine for a personal install.
- The switch button calls `scutil --nc start/stop`. Tested with Happ 5.7.0; another client may not react.

## Privacy

Data stays on your Mac. The app contacts `cloudflare.com` (exit address and country), `gstatic.com` (response time through the tunnel)
and the VPN server (TCP ping), plus the subscription link if you set one. Nowhere else. The subscription link is stored in the settings file
readable only by your user.

> If your provider limits the number of devices, note that a subscription request from a new client may take a slot. The subscription link is optional.
