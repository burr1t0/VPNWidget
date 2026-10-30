import SwiftUI

// Candidate icon artwork on a 1024 x 1024 canvas. The system rounds the corners, so the art fills the square.

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

/// A. A lit archway: the entrance of a tunnel with the light coming from inside.
struct ArchIcon: View {
    private func arch(_ w: CGFloat, _ h: CGFloat) -> some Shape {
        UnevenRoundedRectangle(topLeadingRadius: w / 2, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: w / 2, style: .continuous)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [rgb(0.03, 0.14, 0.18), rgb(0.01, 0.04, 0.07)], startPoint: .top, endPoint: .bottom)
            // Depth: the same arch again and again, each smaller and brighter.
            ForEach(0..<4, id: \.self) { i in
                let k = CGFloat(i)
                arch(460 - k * 92, 560 - k * 110)
                    .stroke(LinearGradient(colors: [rgb(0.35, 1.0, 0.85), rgb(0.2, 0.7, 1.0)], startPoint: .top, endPoint: .bottom).opacity(0.35 + 0.2 * Double(i)),
                            lineWidth: 34 - k * 6)
                    .frame(width: 460 - k * 92, height: 560 - k * 110)
                    .offset(y: 105 + k * 55)
            }
            arch(190, 250)
                .fill(RadialGradient(colors: [.white, rgb(0.55, 1.0, 0.9), rgb(0.1, 0.6, 0.8).opacity(0)], center: .bottom, startRadius: 0, endRadius: 190))
                .frame(width: 190, height: 250)
                .offset(y: 270)
                .blur(radius: 6)
            // A pool of light on the floor.
            Ellipse().fill(rgb(0.4, 1.0, 0.85).opacity(0.35)).frame(width: 520, height: 90).offset(y: 390).blur(radius: 28)
        }
        .scaleEffect(1.22)
        .offset(y: -34)
    }
}

/// B. A route: from a small hollow point to a glowing one far away.
struct RouteIcon: View {
    private var curve: Path {
        var p = Path()
        p.move(to: CGPoint(x: 250, y: 730))
        p.addQuadCurve(to: CGPoint(x: 780, y: 300), control: CGPoint(x: 300, y: 270))
        return p
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [rgb(0.10, 0.10, 0.13), rgb(0.03, 0.03, 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            curve.stroke(style: StrokeStyle(lineWidth: 80, lineCap: .round)).foregroundStyle(rgb(1.0, 0.45, 0.32).opacity(0.10)).blur(radius: 24)
            curve.trim(from: 0, to: 1)
                .stroke(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.85)], startPoint: .bottomLeading, endPoint: .topTrailing),
                        style: StrokeStyle(lineWidth: 26, lineCap: .round, dash: [2, 46]))
            // Destination: a warm, glowing node with ripples.
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(rgb(1.0, 0.5, 0.35).opacity(0.5 - 0.15 * Double(i)), lineWidth: 8)
                    .frame(width: 190 + CGFloat(i) * 90, height: 190 + CGFloat(i) * 90)
                    .position(x: 780, y: 300)
            }
            Circle().fill(LinearGradient(colors: [rgb(1.0, 0.72, 0.45), rgb(1.0, 0.36, 0.30)], startPoint: .top, endPoint: .bottom))
                .frame(width: 170, height: 170).position(x: 770, y: 300)
                .shadow(color: rgb(1.0, 0.45, 0.32).opacity(0.9), radius: 40)
            // Origin: a small hollow point.
            Circle().stroke(Color.white, lineWidth: 18).frame(width: 110, height: 110).position(x: 250, y: 740)
        }
    }
}

/// C. An arrow flying through a ring: passing through the barrier.
struct ThroughRingIcon: View {
    private var arrow: Path {
        var p = Path()
        p.move(to: CGPoint(x: 800, y: 200))
        p.addLine(to: CGPoint(x: 560, y: 760))
        p.addLine(to: CGPoint(x: 508, y: 560))
        p.addLine(to: CGPoint(x: 300, y: 500))
        p.closeSubpath()
        return p
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [rgb(0.15, 0.11, 0.35), rgb(0.04, 0.03, 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            let ring = Ellipse().rotation(.degrees(-25))
            // Back half of the ring, behind the arrow.
            ring.trim(from: 0.0, to: 0.5)
                .stroke(rgb(0.50, 0.40, 1.0).opacity(0.6), style: StrokeStyle(lineWidth: 64, lineCap: .round))
                .frame(width: 600, height: 760).offset(x: -20, y: 20)
            arrow
                .fill(LinearGradient(colors: [rgb(1.0, 0.86, 0.45), rgb(1.0, 0.55, 0.30)], startPoint: .topTrailing, endPoint: .bottomLeading))
                .shadow(color: rgb(1.0, 0.6, 0.3).opacity(0.8), radius: 36)
            // Front half, in front of it.
            ring.trim(from: 0.5, to: 1.0)
                .stroke(LinearGradient(colors: [rgb(0.45, 0.45, 1.0), rgb(0.75, 0.45, 1.0)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 64, lineCap: .round))
                .frame(width: 600, height: 760).offset(x: -20, y: 20)
        }
    }
}

/// D. A loop with no start and no end.
struct LoopIcon: View {
    private var lemniscate: Path {
        var p = Path()
        let a: CGFloat = 330
        for i in 0...240 {
            let t = Double(i) / 240 * 2 * .pi
            let d = 1 + sin(t) * sin(t)
            let pt = CGPoint(x: 512 + a * CGFloat(cos(t) / d), y: 512 + a * CGFloat(sin(t) * cos(t) / d) * 1.5)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [rgb(0.17, 0.05, 0.22), rgb(0.04, 0.02, 0.09)], startPoint: .top, endPoint: .bottom)
            ZStack {
                lemniscate.stroke(style: StrokeStyle(lineWidth: 150, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(rgb(0.7, 0.3, 1.0).opacity(0.28)).blur(radius: 40)
                lemniscate.stroke(AngularGradient(colors: [rgb(0.25, 0.95, 0.9), rgb(0.45, 0.55, 1.0), rgb(0.95, 0.4, 0.85), rgb(0.25, 0.95, 0.9)], center: .center),
                                  style: StrokeStyle(lineWidth: 110, lineCap: .round, lineJoin: .round))
                lemniscate.stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            }
            .rotationEffect(.degrees(-28))
        }
    }
}

/// E. Two beams of light meeting at one point.
struct BeamsIcon: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [rgb(0.04, 0.07, 0.14), rgb(0.01, 0.02, 0.05)], startPoint: .top, endPoint: .bottom)
            v(spread: 250, top: 190, bottom: 760, width: 84)
            Circle().fill(.white).frame(width: 118, height: 118).offset(y: 248)
                .shadow(color: rgb(0.4, 1.0, 0.9), radius: 44).shadow(color: rgb(0.4, 1.0, 0.9), radius: 18)
        }
    }

    private func v(spread: CGFloat, top: CGFloat, bottom: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 512 - spread, y: top)); p.addLine(to: CGPoint(x: 512, y: bottom))
            }.stroke(LinearGradient(colors: [rgb(0.2, 0.9, 1.0), rgb(0.5, 1.0, 0.85)], startPoint: .top, endPoint: .bottom),
                     style: StrokeStyle(lineWidth: width, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 512 + spread, y: top)); p.addLine(to: CGPoint(x: 512, y: bottom))
            }.stroke(LinearGradient(colors: [rgb(0.62, 0.42, 1.0), rgb(0.35, 0.85, 1.0)], startPoint: .top, endPoint: .bottom),
                     style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        .shadow(color: rgb(0.3, 0.8, 1.0).opacity(0.5), radius: 26)
    }
}

/// F. A glass orb with a tunnel inside it.
struct OrbIcon: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [rgb(0.96, 0.95, 0.99), rgb(0.80, 0.82, 0.93)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color.black.opacity(0.18)).frame(width: 640, height: 640).offset(y: 40).blur(radius: 40)
            Circle().fill(RadialGradient(colors: [rgb(0.45, 0.85, 1.0), rgb(0.30, 0.30, 0.95), rgb(0.12, 0.08, 0.50)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 20, endRadius: 400))
                .frame(width: 640, height: 640)
            // The tunnel: rings pulling towards a bright point.
            ForEach(0..<4, id: \.self) { i in
                Circle().stroke(Color.white.opacity(0.10 + 0.10 * Double(i)), lineWidth: 12)
                    .frame(width: 440 - CGFloat(i) * 105, height: 440 - CGFloat(i) * 105)
                    .offset(x: CGFloat(i) * 14, y: CGFloat(i) * 10)
            }
            Circle().fill(.white).frame(width: 64, height: 64).offset(x: 62, y: 44).shadow(color: .white, radius: 28)
            // Glass highlight.
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 400, height: 190).offset(x: -40, y: -200)
        }
    }
}

struct Variant: Identifiable {
    let id: String
    let name: String
    let art: AnyView
}

let variants: [Variant] = [
    Variant(id: "A", name: "Арка", art: AnyView(ArchIcon())),
    Variant(id: "B", name: "Маршрут", art: AnyView(RouteIcon())),
    Variant(id: "C", name: "Сквозь кольцо", art: AnyView(ThroughRingIcon())),
    Variant(id: "D", name: "Петля", art: AnyView(LoopIcon())),
    Variant(id: "E", name: "Лучи", art: AnyView(BeamsIcon())),
    Variant(id: "F", name: "Шар", art: AnyView(OrbIcon())),
]
