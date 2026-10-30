import SwiftUI
import AppKit

// Usage: vpn-icon <AppIcon.appiconset directory> [--variant A..F] [--preview file.png]
//        vpn-icon --docs <file.png>   (the rounded README logo)
//        vpn-icon --sheet <file.png>
// The art fills the whole square; the system rounds it.

/// Corner radius the system applies to a macOS icon, as a fraction of its side.
private let cornerFraction: CGFloat = 0.2237

struct Sheet: View {
    var body: some View {
        VStack(spacing: 36) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 48) {
                    ForEach(variants[(row * 3)..<(row * 3 + 3)]) { v in
                        VStack(spacing: 14) {
                            v.art
                                .frame(width: 1024, height: 1024)
                                .scaleEffect(0.34)
                                .frame(width: 348, height: 348)
                                .clipShape(RoundedRectangle(cornerRadius: 348 * cornerFraction, style: .continuous))
                                .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                            Text("\(v.id) · \(v.name)").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
        }
        .padding(48)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
    }
}

@MainActor
func render(_ art: some View) -> CGImage? {
    let r = ImageRenderer(content: art.frame(width: 1024, height: 1024).clipped())
    r.proposedSize = ProposedViewSize(width: 1024, height: 1024)
    r.scale = 1
    return r.cgImage
}

func resized(_ image: CGImage, to n: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

let args = Array(CommandLine.arguments.dropFirst())

// vpn-icon --sheet <file.png>: all candidates side by side, rounded like the real icon.
if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count {
    await MainActor.run {
        let r = ImageRenderer(content: Sheet())
        r.scale = 1
        guard let image = r.cgImage else { print("render failed"); exit(1) }
        try? writePNG(image, to: URL(fileURLWithPath: args[i + 1]))
        print("wrote \(args[i + 1])")
    }
    exit(0)
}

// vpn-icon --docs <file.png> [--variant X]: the README logo, a 512 px tile with rounded corners and transparent surroundings.
if let i = args.firstIndex(of: "--docs"), i + 1 < args.count {
    await MainActor.run {
        let chosen = args.firstIndex(of: "--variant").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "C"
        guard let art = variants.first(where: { $0.id == chosen })?.art else { print("unknown variant"); exit(1) }
        let tile = art.frame(width: 1024, height: 1024)
            .clipShape(RoundedRectangle(cornerRadius: 1024 * cornerFraction, style: .continuous))
        let r = ImageRenderer(content: tile)
        r.proposedSize = ProposedViewSize(width: 1024, height: 1024)
        r.scale = 0.5
        guard let image = r.cgImage else { print("render failed"); exit(1) }
        try? writePNG(image, to: URL(fileURLWithPath: args[i + 1]))
        print("wrote \(args[i + 1]) (\(image.width) px)")
    }
    exit(0)
}

guard let outDir = args.first(where: { !$0.hasPrefix("--") && !$0.hasSuffix(".png") }) else {
    print("usage: vpn-icon <AppIcon.appiconset directory> [--preview file.png]")
    exit(64)
}
let dir = URL(fileURLWithPath: outDir)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

await MainActor.run {
    let chosen = args.firstIndex(of: "--variant").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "C"
    guard let art = variants.first(where: { $0.id == chosen })?.art, let master = render(art) else { print("render failed"); exit(1) }
    if let i = args.firstIndex(of: "--preview"), i + 1 < args.count { try? writePNG(master, to: URL(fileURLWithPath: args[i + 1])) }

    // macOS icon slots: point size and scale -> pixel size.
    let slots: [(pt: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    var images: [[String: String]] = []
    for s in slots {
        let px = s.pt * s.scale
        let name = "icon_\(s.pt)x\(s.pt)\(s.scale == 2 ? "@2x" : "").png"
        guard let img = px == 1024 ? master : resized(master, to: px) else { continue }
        try? writePNG(img, to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "scale": "\(s.scale)x", "size": "\(s.pt)x\(s.pt)", "filename": name])
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    if let data = try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: dir.appendingPathComponent("Contents.json"))
    }
    print("wrote \(images.count) icons to \(dir.path)")
}
