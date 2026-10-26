import GridFixCore
import SwiftUI

struct NavigationControlsView: View {
    @EnvironmentObject private var navigation: NavigationSession
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var boundaries: BoundaryMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lanes: NavigationLaneStore
    @EnvironmentObject private var field: FieldDataStore
    @State private var showingSettings = false
    @State private var clearing = false
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            if let lane = navigation.lane ?? NavLanes.forTarget(lanes.lanes,target: store.waypoints.first { $0.id == store.selectedId }) {
                VStack(alignment: .leading,spacing: 6) {
                    Text("NAV LANE · "+(lane.name.isEmpty ? "Navigation lane" : lane.name)).font(.headline)
                    Text(NavLanes.limitsSummary(lane,graphics: field.document.graphics)).font(.caption)
                    if let problem = navigation.laneProblem { Text(problem).font(.caption).foregroundStyle(palette.warn) }
                    if !lane.visible { Text("Hidden on map · still guides").font(.caption) }
                }.accessibilityIdentifier("navigation-lane-status")
            }
            if let p = navigation.progress {
                Text(p.name).font(.headline)
                Text(p.complete ? "Route complete" : "Point \(p.index+1) of \(p.points.count) · \(p.paused ? "paused" : "following")")
                    .accessibilityIdentifier("route-follow-progress")
                if !p.complete {
                    HStack {
                        if navigation.running { Button("Pause route") { navigation.pause() }.accessibilityIdentifier("pause-route") }
                        else { Button("Resume route") { navigation.resume() }.accessibilityIdentifier("resume-route") }
                        Button("Previous point") { navigation.movePoint(-1) }.disabled(p.index == 0 || navigation.saving)
                        Button("Next point") { navigation.movePoint(1) }.accessibilityIdentifier("next-route-point").disabled(navigation.saving)
                    }.buttonStyle(.bordered).font(.caption)
                    Text("Advances when your GPS accuracy circle fits inside 25 m. The haptic arrival cue uses a separate 50 m ring.")
                        .font(.caption).foregroundStyle(palette.inkDim)
                }
            }
            Toggle("Haptic guide",isOn: Binding(get: { navigation.running && navigation.haptics },set: { navigation.setHaptics($0) }))
                .disabled(navigation.saving || navigation.preparing || (store.selectedId == nil && !navigation.running) || (navigation.progress != nil && !navigation.running && navigation.progress?.complete != true))
                .accessibilityIdentifier("haptic-guide-toggle")
            if navigation.saving { ProgressView("Saving navigation…").accessibilityIdentifier("navigation-saving") }
            Text(navigation.preparing ? "Starting navigation…" : navigation.status).accessibilityIdentifier("navigation-guide-status")
            if let d = navigation.decision, let error = d.deviation, d.cue != .unavailable, navigation.haptics {
                VStack(alignment: .leading,spacing: 6) {
                    Text("Haptic guide · phone top").font(.caption)
                    Text(error == 0 ? "On bearing" : "\(error > 0 ? "Right" : "Left") \(Int(abs(error)))°")
                        .font(.system(.headline,design: .monospaced))
                }.foregroundStyle(palette.accent).accessibilityIdentifier("relative-heading-guide")
            }
            if navigation.preparing { Button("Cancel start") { navigation.pause() } }
            Button("Guide settings") { showingSettings = true }.accessibilityIdentifier("guide-settings")
            if !navigation.feedbackStatus.isEmpty { Text(navigation.feedbackStatus).font(.caption).foregroundStyle(palette.inkDim) }
            Text(navigation.lane != nil && navigation.laneProblem == nil ? "Lane: silent until confirmed between the limits, then an optional entry tick. Optional reminder: long-short-long. Past left: two taps to turn right. Past right: one long pulse to turn left. Past backstop: three long pulses to turn back. Cues can be switched off in Guide settings. Position lost: three short taps once, then each minute if enabled. Phone heading is not needed in lane mode." : "Phone top edge points ahead. Two taps: right. Long pulse: left. Three taps: unavailable. Two long pulses: arrival. Short tick: back on course or configured heartbeat. Silence does not confirm a bearing.")
                .font(.caption).foregroundStyle(palette.inkDim)
            Text("Steering patterns require the app open. Background route following and lane crossings use GPS and iOS notifications as permitted; continuous locked-screen steering buzzes are not promised.")
                .font(.caption).foregroundStyle(palette.inkDim)
            if boundaries.running {
                Text("Boundary monitoring is separate and remains crossing-only. If you enable this navigation guide, its route and steering alerts can sound inside the boundary.")
                    .font(.caption).foregroundStyle(palette.accent)
            }
            if let error = navigation.error { Text(error).font(.footnote).foregroundStyle(palette.warn).accessibilityIdentifier("navigation-error") }
            if !navigation.running && !navigation.preparing {
                Button("Clear saved navigation session") { clearing = true }.font(.caption)
            }
        }.padding(16).fieldContentSurface(night: settings.nightMode)
        .sheet(isPresented: $showingSettings) { GuideSettingsView() }
        .confirmationDialog("Clear navigation progress? Saved routes and waypoints are kept.",isPresented: $clearing) {
            Button("Clear session",role: .destructive) { navigation.clearSavedSession() }
        }
    }
}

struct GuideSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    private var rowBackground: Color { settings.nightMode ? .black : Color(white: 0.12) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Haptic navigation · Android 1.1.0") {
                    Picker("Drift allowance",selection: $settings.guideAllowance) {
                        ForEach(Array(Set([5,10,15,20,30,settings.guideAllowance])).sorted(),id: \.self) { Text("±\($0)°").tag($0) }
                    }
                    Picker("Buzz after off course for",selection: $settings.guideHoldOffSec) {
                        ForEach(Array(Set([0,3,5,10,settings.guideHoldOffSec])).sorted(),id: \.self) { Text($0 == 0 ? "At once" : "\($0) s").tag($0) }
                    }
                    Picker("While on course",selection: $settings.guideHeartbeatSec) {
                        ForEach(Array(Set([0,30,60,settings.guideHeartbeatSec])).sorted(),id: \.self) { Text($0 == 0 ? "Silent" : "Pulse every \($0) s").tag($0) }
                    }
                    Picker("Steer by",selection: $settings.guideMode) { Text("Hold azimuth").tag(0); Text("Home on point").tag(1) }
                    if settings.guideMode == 0 {
                        Picker("Leg drift corridor",selection: $settings.guideCorridorM) {
                            ForEach(Array(Set([0,50,100,200,settings.guideCorridorM])).sorted(),id: \.self) { Text($0 == 0 ? "Off" : "±\($0) m").tag($0) }
                        }
                        Text("Hold the leg azimuth from the start position. Within 100 m of the target, home on the point. A drift corridor steers you back to this straight leg; it does not change drawn boundary alerts.").font(.footnote)
                    }
                }.listRowBackground(rowBackground)
                Section("Navigation lanes") {
                    Picker("Early warning",selection: $settings.laneWarningM) {
                        ForEach(Array(Set([0,25,50,settings.laneWarningM])).sorted(),id: \.self) { Text($0 == 0 ? "Off" : "\($0) m inside").tag($0) }
                    }
                    Toggle("Side-limit cues",isOn:$settings.laneSideCues).accessibilityIdentifier("lane-side-cues")
                    Toggle("Backstop cue",isOn:$settings.laneBackstopCue).accessibilityIdentifier("lane-backstop-cue")
                    Toggle("In-the-lane tick",isOn:$settings.laneInsideTick).accessibilityIdentifier("lane-inside-tick")
                    FieldChoicePicker(
                        selection: Binding(get: { String(settings.laneReminderMin) },set: { if let minutes = Int($0) { settings.laneReminderMin = minutes } }),
                        title: "Not in lane reminder",
                        choices: Array(Set([0,2,5,10,settings.laneReminderMin])).sorted().map {
                            .init(id: String($0),title: $0 == 0 ? "Off" : "Every \($0) min",accessibilityIdentifier: "lane-reminder-\($0)")
                        },identifier: "lane-reminder"
                    )
                    Toggle("Position lost alert",isOn:$settings.laneGpsAlert).accessibilityIdentifier("lane-gps-alert")
                    Text("Starts silent until two distinct fixes confirm you are between the limits; behind the start does not count. The reminder is long-short-long. Position lost alerts sound once, then at most each minute. These switches do not change route checkpoint or arrival cues.").font(.footnote)
                    Text("One turn-away cue per approach. Crossing cues repeat while outside. Lane guidance replaces azimuth steering only when the selected checkpoint or route has a usable assigned lane.").font(.footnote)
                }.listRowBackground(rowBackground)
                Section { Text("These settings apply to navigation guidance only. Quiet-inside boundary monitoring has no heading tolerance, approach warning, heartbeat or steering cues.").font(.footnote) }.listRowBackground(rowBackground)
            }
                .scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .foregroundStyle(palette.ink)
                .navigationTitle("Guide settings").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Guide settings").font(.headline).foregroundStyle(palette.ink) }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }.tint(palette.accent).environment(\.fieldNight,settings.nightMode).fieldSheetAppearance()
    }
}
