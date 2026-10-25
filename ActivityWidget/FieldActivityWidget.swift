import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FieldActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FieldActivityAttributes.self) { context in
            FieldActivityCard(state: context.state,kind: context.attributes.kind,stale: context.isStale)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(context.state.night ? .red : .white)
                .widgetURL(URL(string: "gridfix://" + context.attributes.kind))
        } dynamicIsland: { context in
            let tint: Color = context.state.night ? .red : .orange
            let fresh = !context.isStale && context.state.hasFreshFix()
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.attributes.kind == "recording" ? "record.circle" : "location.north.line").foregroundStyle(tint) }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.attributes.kind == "recording",let start=context.state.startedAt { Text(start,style:.timer).monospacedDigit() }
                }
                DynamicIslandExpandedRegion(.bottom) { FieldActivityCard(state:context.state,kind:context.attributes.kind,stale:context.isStale) }
            } compactLeading: {
                Image(systemName: context.attributes.kind == "recording" ? "record.circle" : "location.north.line").foregroundStyle(tint)
            } compactTrailing: {
                Text(context.attributes.kind == "recording" ? "REC" : fresh ? "NAV" : "GPS?").font(.caption2).foregroundStyle(tint)
            } minimal: {
                Image(systemName: context.attributes.kind == "recording" ? "record.circle" : fresh ? "location.north.line" : "location.slash").foregroundStyle(tint)
            }.widgetURL(URL(string:"gridfix://"+context.attributes.kind)).keylineTint(tint)
        }
    }
}

private struct FieldActivityCard: View {
    let state: FieldActivityState
    let kind: String
    let stale: Bool
    private var fresh: Bool { !stale && state.hasFreshFix() }
    private var ink: Color { state.night ? .red : .white }
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Text(kind == "recording" ? "GRIDFIX · RECORDING" : "GRIDFIX · NAVIGATION").font(.caption2.bold())
                Spacer()
                if kind == "recording",let start=state.startedAt { Text(start,style:.timer).font(.caption.monospacedDigit()) }
            }
            Text(state.title).font(.headline).lineLimit(1)
            Text(kind == "recording" && state.status != "Recording" ? state.status : fresh ? (kind == "recording" ? "Recording · GPS active" : state.status) : "Waiting for fresh GPS")
                .font(.subheadline).lineLimit(2)
            if kind == "recording" || fresh { Text(state.detail).font(.caption.monospacedDigit()).lineLimit(2) }
            if fresh,let grid=state.grid { Text(grid).font(.system(.caption,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.7) }
            if !fresh { Text("Open app for current status").font(.caption2) }
        }.padding(14).foregroundStyle(ink)
    }
}
