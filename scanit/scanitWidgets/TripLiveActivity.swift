import ActivityKit
import SwiftUI
import WidgetKit

/// The running total while a trip is in progress (BACKLOG LIVE-001): Lock Screen banner and
/// Dynamic Island. Amber and red mean what they mean in the app: near the limit, over it.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripLockScreenView(storeName: context.attributes.storeName, state: context.state)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.storeName ?? "Trip", systemImage: "cart.fill")
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.itemsText)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TripTotalBlock(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(context.state.level.tint)
            } compactTrailing: {
                Text(context.state.total)
                    .monospacedDigit()
                    .foregroundStyle(context.state.level.tint)
            } minimal: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(context.state.level.tint)
            }
            .keylineTint(context.state.level.tint)
        }
    }
}

private struct TripLockScreenView: View {
    let storeName: String?
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(storeName ?? "Trip", systemImage: "cart.fill")
                    .lineLimit(1)
                Spacer()
                Text(state.itemsText)
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            TripTotalBlock(state: state)
        }
        .padding(16)
    }
}

/// Total, limit bar and what is left. Shared by the Lock Screen and the expanded island.
private struct TripTotalBlock: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.total)
                .font(.system(.title, design: .default, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let progress = state.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(state.level.tint)
            }
            if let limitText = state.limitText {
                Text(limitText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(state.level == .over ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension TripActivityAttributes.ContentState {
    var itemsText: String { items == 1 ? "1 item" : "\(items) items" }
}

private extension TripActivityAttributes.Level {
    /// The brand green, then the limit colours.
    var tint: Color {
        switch self {
        case .noLimit, .ok: Color(red: 0x23 / 255, green: 0x84 / 255, blue: 0x3B / 255)
        case .near: .orange
        case .over: .red
        }
    }
}
