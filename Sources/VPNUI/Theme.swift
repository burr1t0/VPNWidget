import SwiftUI
import WidgetKit
import VPNCore

/// Same palette as NetWatch, so both widgets read as one family.
public enum Theme {
    public static let bgTop = Color(red: 0.07, green: 0.10, blue: 0.18)
    public static let bgBottom = Color(red: 0.03, green: 0.05, blue: 0.10)
    public static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static let text = Color.white.opacity(0.94)
    public static let muted = Color.white.opacity(0.55)
    public static let faint = Color.white.opacity(0.10)

    public static let ok = Color(red: 0.30, green: 0.86, blue: 0.56)
    public static let warn = Color(red: 1.0, green: 0.76, blue: 0.28)
    public static let bad = Color(red: 1.0, green: 0.38, blue: 0.38)
    public static let unknown = Color.white.opacity(0.35)
    public static let accent = Color(red: 0.42, green: 0.72, blue: 1.0)
}

public extension Verdict {
    /// In monochrome widget modes hue is lost but opacity survives, so severity is also encoded as brightness.
    func tint(fullColor: Bool) -> Color {
        switch self {
        case .ok: return fullColor ? Theme.ok : Color.white.opacity(0.4)
        case .off, .unknown: return fullColor ? Theme.unknown : Color.white.opacity(0.35)
        case .noTraffic, .serverDown: return fullColor ? Theme.warn : Color.white.opacity(0.75)
        case .leak, .exitChanged: return fullColor ? Theme.bad : Color.white
        }
    }

    /// A shape per state, so the status reads without color too.
    var symbol: String {
        switch self {
        case .ok: return "checkmark.shield.fill"
        case .off: return "shield.slash.fill"
        case .unknown: return "questionmark.circle.fill"
        case .noTraffic, .serverDown: return "exclamationmark.triangle.fill"
        case .leak: return "xmark.octagon.fill"
        case .exitChanged: return "arrow.triangle.swap"
        }
    }
}

private struct StaticNowKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

public extension EnvironmentValues {
    /// Set outside the widget (README animations) so that elapsed times are computed from a fixed moment instead of the
    /// live clock: the same input then always draws the same picture.
    var staticNow: Date? {
        get { self[StaticNowKey.self] }
        set { self[StaticNowKey.self] = newValue }
    }
}

private struct ForceMonochromeKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Lets previews imitate the monochrome widget styles, which cannot be set through `widgetRenderingMode`.
    var forceMonochrome: Bool {
        get { self[ForceMonochromeKey.self] }
        set { self[ForceMonochromeKey.self] = newValue }
    }
}

struct RenderStyle: DynamicProperty {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.forceMonochrome) private var mono

    var full: Bool { mode == .fullColor && !mono }
}

public enum WidgetSizes {
    public static let medium = CGSize(width: 364, height: 170)
    public static let large = CGSize(width: 364, height: 382)
}

/// Stand-in for the widget container when a view is shown outside WidgetKit (PNG previews).
public struct WidgetFrame<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}
