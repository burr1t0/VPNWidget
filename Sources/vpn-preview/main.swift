import SwiftUI
import AppKit
import VPNCore
import VPNUI

// Usage: vpn-preview [output-dir]
// Writes PNGs of the widget views, one set from the real state file and one from synthetic data.
let outDir = CommandLine.arguments.dropFirst().first ?? "."

@MainActor
func save<V: View>(_ view: V, size: CGSize, name: String) {
    let framed = WidgetFrame { view }.frame(width: size.width, height: size.height)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        print("render failed: \(name)")
        return
    }
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("saved \(outDir)/\(name).png")
}

await MainActor.run {
    let now = Date()
    if let real = Storage.loadState() {
        save(VPNMediumView(state: real), size: WidgetSizes.medium, name: "medium-real")
    }
    let ok = Mock.state(now: now)
    save(VPNMediumView(state: Mock.state(now: now, exitChanged: true)), size: WidgetSizes.medium, name: "medium-exitchanged")
    save(VPNMediumView(state: Mock.state(now: now, exitChanged: true)).environment(\.forceMonochrome, true).saturation(0), size: WidgetSizes.medium, name: "medium-exitchanged-mono")
    save(VPNMediumView(state: Mock.state(now: now, withSubscription: false)), size: WidgetSizes.medium, name: "medium-nosub")
    save(VPNMediumView(state: Mock.state(now: now, tunnelMs: nil)), size: WidgetSizes.medium, name: "medium-notraffic")
    save(VPNMediumView(state: Mock.state(now: now, tunnelMs: nil, serverDown: true)), size: WidgetSizes.medium, name: "medium-serverdown")
    save(VPNMediumView(state: Mock.state(now: now.addingTimeInterval(-600))), size: WidgetSizes.medium, name: "medium-stale")
    save(VPNMediumView(state: Mock.state(now: now)).environment(\.forceMonochrome, true).saturation(0), size: WidgetSizes.medium, name: "medium-mono")
    save(VPNMediumView(state: ok), size: WidgetSizes.medium, name: "medium-ok")
    save(VPNMediumView(state: Mock.state(now: now, status: .disconnected)), size: WidgetSizes.medium, name: "medium-off")
}
