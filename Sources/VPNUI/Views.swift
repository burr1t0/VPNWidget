import SwiftUI
import VPNCore

/// The widget: status with the power button, four key numbers, and one line at the bottom.
/// It is meant to sit above NetWatch's large widget, which already draws the latency graph and the incident list,
/// so nothing here repeats them.
public struct VPNMediumView: View {
    private let state: VPNState
    private let button: ActionButtonBuilder?

    public init(state: VPNState, button: ActionButtonBuilder? = nil) {
        self.state = state
        self.button = button
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            StatusHeader(s: state, button: button)
            MetricsRow(s: state)
            Rectangle().fill(Theme.faint).frame(height: 1)
            // The account card only means something once a subscription is connected; until then the server line is more useful.
            if let alert = state.alert {
                AlertRow(alert: alert, current: state.external?.country?.uppercased(), button: button)
            } else if state.subscription.fetched != nil {
                SubscriptionRow(s: state, button: button)
            } else if let active = state.activeServer {
                ServerRow(ping: active, active: true)
            }
        }
    }
}
