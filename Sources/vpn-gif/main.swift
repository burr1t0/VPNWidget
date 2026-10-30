import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import VPNCore
import VPNUI

// Usage: vpn-gif <output directory> [--frames]   (--frames also writes every frame as a PNG, for checking by eye)
// Draws the widget with synthetic data and writes the animations used in the README.

/// The widget on a dark backdrop, like a screenshot of the desktop. A solid backdrop also avoids the ragged edges
/// that GIF's one-bit transparency would give the rounded corners.
struct Frame: View {
    let state: VPNState
    let anchor: Date

    var body: some View {
        WidgetFrame { VPNMediumView(state: state) }
            .environment(\.staticNow, anchor)
            .frame(width: WidgetSizes.medium.width, height: WidgetSizes.medium.height)
            .padding(22)
            .background(Color(red: 0.035, green: 0.045, blue: 0.075))
    }
}

@MainActor
func render<V: View>(_ view: V) -> CGImage? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return renderer.cgImage
}

func writeGIF(_ frames: [(image: CGImage, seconds: Double)], to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return false }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in frames {
        CGImageDestinationAddImage(destination, frame.image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.seconds]] as CFDictionary)
    }
    return CGImageDestinationFinalize(destination)
}

func fileSize(_ url: URL) -> String {
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    return String(format: "%.0f KB", Double(bytes) / 1024)
}

// A fixed moment in a fixed time zone: the clock times inside the animations say nothing about when or where they were
// made, and the same input always gives the same files.
setenv("TZ", "UTC", 1)
tzset()
NSTimeZone.resetSystemTimeZone()
let anchor = ISO8601DateFormatter().date(from: "2026-03-12T18:40:00Z")!

guard let outPath = CommandLine.arguments.dropFirst().first else {
    print("usage: vpn-gif <output directory>")
    exit(64)
}
let outDir = URL(fileURLWithPath: outPath)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// A demo state. `updated` is the real clock so the widget never looks stale; everything else hangs off the fixed anchor.
@MainActor func state(status: TunnelStatus = .connected, tunnelMs: Double? = 107, serverDown: Bool = false, exitChanged: Bool = false,
           country: String = "EE", busy: String? = nil, connectedFor: TimeInterval = 3 * 3600 + 421) -> VPNState {
    Mock.state(now: anchor, status: status, tunnelMs: tunnelMs, serverDown: serverDown, withSubscription: true,
               exitChanged: exitChanged, country: country, busy: busy, connectedFor: connectedFor, updated: Date())
}

await MainActor.run {
    // 1. The power button: on, switching off, off, switching on, connecting, on again.
    let power: [(VPNState, Double)] = [
        (state(), 1.6),
        (state(busy: "Выключаю…"), 0.9),
        (state(status: .disconnected), 1.6),
        (state(status: .disconnected, busy: "Включаю…"), 0.9),
        (state(status: .connecting), 0.9),
        (state(tunnelMs: 214, connectedFor: 6), 0.9),
        (state(tunnelMs: 118, connectedFor: 12), 1.6),
    ]

    // 2. Trouble inside the tunnel while the network itself is fine: slow, nothing gets through, the server is silent, back to normal.
    let incident: [(VPNState, Double)] = [
        (state(), 1.2),
        (state(tunnelMs: 340), 0.9),
        (state(tunnelMs: nil), 1.6),
        (state(tunnelMs: nil, serverDown: true), 1.6),
        (state(tunnelMs: 150), 1.0),
        (state(), 1.4),
    ]

    // 3. The exit country changes: the widget turns red until the change is accepted.
    let exitAlert: [(VPNState, Double)] = [
        (state(), 1.4),
        (state(exitChanged: true), 2.4),
        (state(country: "DE"), 1.6),
    ]

    for (name, story) in [("widget-power", power), ("widget-incident", incident), ("widget-exit-alert", exitAlert)] {
        let frames = story.compactMap { s -> (image: CGImage, seconds: Double)? in
            render(Frame(state: s.0, anchor: anchor)).map { (image: $0, seconds: s.1) }
        }
        if CommandLine.arguments.contains("--frames") {
            for (i, f) in frames.enumerated() {
                let png = NSBitmapImageRep(cgImage: f.image).representation(using: .png, properties: [:])
                try? png?.write(to: outDir.appendingPathComponent("\(name)-\(i).png"))
            }
        }
        let url = outDir.appendingPathComponent("\(name).gif")
        let ok = writeGIF(frames, to: url)
        print(ok ? "wrote \(url.lastPathComponent): \(frames.count) frames, \(fileSize(url))" : "failed: \(name)")
    }
}
