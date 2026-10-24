import GridFixCore
import SwiftUI

struct NavigationControlsView: View {
    @EnvironmentObject private var navigation: NavigationSession
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var boundaries: BoundaryMonitor
    @EnvironmentObject private var settings: AppSettings
    @State private var showingSettings = false
    @State private var clearing = false
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            if let p = navigation.progress {
                Text(p.name).font(.headline)
                Text(p.complete ? "Route complete" : "Point \(p.index+1) of \(p.points.count) · \(p.paused ? "paused" : "following")")
                    .accessibilityIdentifier("route-follow-progress")
                if !p.complete {
                    HStack {
                        if navigation.running { Button("Pause route") { navigation.pause() }.accessibilityIdentifier("pause-route") }
                        else { Button("Resume route") { navigation.resume() }.accessibilityIdentifier("resume-route") }
                        Button("Previous point") { navigation.movePoint(-1) }.disabled(p.index == 0)
                        Button("Next point") { navigation.movePoint(1) }.accessibilityIdentifier("next-route-point")
                    }.buttonStyle(.bordered).font(.caption)
                    Text("Advances when your GPS accuracy circle fits inside 25 m. The haptic arrival cue uses a separate 50 m ring.")
                        .font(.caption).foregroundStyle(palette.inkDim)
                }
            }
            Toggle("Haptic guide",isOn: Binding(get: { navigation.running && navigation.haptics },set: { navigation.setHaptics($0) }))
                .disabled(navigation.preparing || (store.selectedId == nil && !navigation.running) || (navigation.progress != nil && !navigation.running && navigation.progress?.complete != true))
                .accessibilityIdentifier("haptic-guide-toggle")
            Text(navigation.preparing ? "Starting navigation…" : navigation.status).accessibilityIdentifier("navigation-guide-status")
            if let d = navigation.decision, let error = d.deviation, d.cue != .unavailable, navigation.haptics {
                HStack(spacing: 16) {
                    Image(systemName: "arrow.up").font(.system(size: 36,weight: .semibold))
                        .rotationEffect(.degrees(error)).frame(width: 70,height: 70)
                    Text(error == 0 ? "On bearing" : "\(error > 0 ? "Right" : "Left") \(Int(abs(error)))°")
                        .font(.system(.headline,design: .monospaced))
                }.foregroundStyle(palette.accent).accessibilityIdentifier("relative-heading-guide")
            }
            if navigation.preparing { Button("Cancel start") { navigation.pause() } }
            Button("Guide settings") { showingSettings = true }.accessibilityIdentifier("guide-settings")
            if !navigation.feedbackStatus.isEmpty { Text(navigation.feedbackStatus).font(.caption).foregroundStyle(palette.inkDim) }
            Text("Phone top edge points ahead. Two taps: right. Long pulse: left. Three taps: unavailable. Two long pulses: arrival. Short tick: back on course or configured heartbeat. Silence does not confirm a bearing.")
                .font(.caption).foregroundStyle(palette.inkDim)
            Text("Steering patterns require the app open. Background route following uses GPS and milestone notifications as iOS permits; it does not promise continuous locked-screen steering buzzes.")
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
                }
                Section { Text("These settings apply to navigation guidance only. Quiet-inside boundary monitoring has no heading tolerance, heartbeat or steering cues.").font(.footnote) }
            }.navigationTitle("Guide settings").navigationBarTitleDisplayMode(.inline)
                .tint(FieldPalette(night: settings.nightMode).accent)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.fieldSheetAppearance()
    }
}
