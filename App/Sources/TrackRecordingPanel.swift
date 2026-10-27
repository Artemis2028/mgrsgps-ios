import GridFixCore
import SwiftUI

struct RecordingButton: View {
    var mapControl = false
    @EnvironmentObject private var recorder: TrackRecorder
    @State private var showingPanel = false
    var body: some View {
        Button {
            if recorder.canStart { recorder.start() }
            else { showingPanel = true }
        } label: {
            Image(systemName: recorder.canStop ? "stop.circle.fill" : "record.circle")
                .font(.system(size:22))
                .frame(width: 44, height: 40)
        }
        .fieldGlassButton(mapControl: mapControl)
        .accessibilityLabel(recorder.canStart ? "Record track" : "Recording controls")
        .accessibilityIdentifier("record-track")
        .sheet(isPresented: $showingPanel) { TrackRecordingPanel() }
    }
}

/// Visible on every tab, including while waiting for fixes or finalizing a log.
struct RecordingBanner: View {
    @EnvironmentObject private var recorder: TrackRecorder
    @EnvironmentObject private var settings: AppSettings
    var onOpen: () -> Void
    private var visible: Bool { recorder.phase != .idle || recorder.failure != nil || recorder.hasRecoveryNotice }
    var body: some View {
        if visible {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: recorder.canStop ? "record.circle.fill" : "exclamationmark.circle").font(.system(size:22))
                    Text(title).font(.caption.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size:18))
                }
                .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(FieldPalette(night: settings.nightMode).accent)
            .background(Color.black, ignoresSafeAreaEdges: [])
            .accessibilityLabel(title)
            .accessibilityIdentifier("recording-banner")
        }
    }
    private var title: String {
        if recorder.phase == .recording, let active = recorder.active {
            return "Recording · \(active.pointCount) points · \(Format.distance(meters: active.distanceM, unit: settings.units))"
        }
        switch recorder.phase {
        case .recording: return "Recording · waiting for GPS"
        case .preparing: return "Starting recording…"
        case .requestingPermission: return "Recording needs location permission"
        case .saving: return "Saving recorded track…"
        case .recovering: return "Checking saved recording…"
        case .recoveryRequired: return "Recording stopped · saved log needs attention"
        case .idle: return recorder.hasRecoveryNotice ? "Recovered interrupted recording · view details" : "Track recording · permission or storage issue"
        }
    }
}

struct TrackRecordingPanel: View {
    @EnvironmentObject private var recorder: TrackRecorder
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmingDiscard = false
    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }
    private var rowBackground: Color { settings.nightMode ? .black : Color(white: 0.12) }
    private var secondaryInk: Color { settings.nightMode ? palette.ink : palette.inkDim }
    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    if let active = recorder.active {
                        Text(active.name).font(.headline)
                        Text("\(active.pointCount) saved points").monospacedDigit().accessibilityIdentifier("recording-point-count")
                        Text(Format.distance(meters: active.distanceM, unit: settings.units)).monospacedDigit()
                    }
                    if let message = recorder.message { Text(message).font(.subheadline) }
                    if recorder.canStop {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let stale = recorder.lastGPSAt.map({ context.date.timeIntervalSince($0) > 15 }) ?? true
                            Text(stale ? "Waiting for an accurate GPS fix. Saved points are kept." : "GPS active")
                                .font(.caption).foregroundStyle(stale ? palette.warn : palette.good)
                        }
                    }
                    if let failure = recorder.failure { Text(failure).foregroundStyle(palette.warn).accessibilityIdentifier("recording-failure") }
                    if recorder.canStart {
                        Button("Start recording") { recorder.start() }.foregroundStyle(palette.accent).accessibilityIdentifier("start-recording")
                    }
                    if recorder.needsSettings {
                        Button("Open location settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.foregroundStyle(palette.accent)
                    }
                }.listRowBackground(rowBackground)
                if recorder.canStop {
                    Section("Finish track") {
                        TextField("Track name (optional)", text: $name, prompt: Text("Track name (optional)").foregroundColor(secondaryInk)).accessibilityIdentifier("recording-name")
                            .onChange(of: name) { name = String($0.prefix(30)) }
                        Button("Save track") { recorder.stop(name: name) }.foregroundStyle(palette.accent).accessibilityIdentifier("save-recording")
                        Button("Discard recording", role: .destructive) { confirmingDiscard = true }
                            .foregroundStyle(palette.warn)
                            .accessibilityIdentifier("discard-recording")
                    }.listRowBackground(rowBackground)
                }
                if recorder.phase == .saving || recorder.phase == .recovering || recorder.phase == .preparing {
                    ProgressView(recorder.phase == .saving ? "Saving track…" : "Preparing recording…")
                        .listRowBackground(rowBackground)
                }
                if recorder.phase == .recoveryRequired {
                    Section("Saved log") {
                        Button("Retry saving") { recorder.recover() }.foregroundStyle(palette.accent).accessibilityIdentifier("retry-recording")
                        Button("Discard saved log", role: .destructive) { confirmingDiscard = true }.foregroundStyle(palette.warn)
                    }.listRowBackground(rowBackground)
                }
                Section {
                    Text("Start recording with the app open and Precise Location enabled. You can then lock the screen or use another app. iOS shows its location indicator while background recording is active.")
                    Text("Force-quitting, restarting the phone, or changing location permission can interrupt recording. Reopen the app to recover saved points and start a new track. Recording does not restart automatically.")
                }.font(.footnote).foregroundStyle(secondaryInk).listRowBackground(rowBackground)
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .foregroundStyle(palette.ink)
            .navigationTitle("Track recording").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Track recording").font(.headline).foregroundStyle(palette.ink) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { recorder.acknowledgeNotice(); dismiss() } }
            }
            .alert("Discard this recording and its saved points?", isPresented: $confirmingDiscard) {
                Button("Discard recording", role: .destructive) { recorder.discard() }
                Button("Keep recording", role: .cancel) {}
            }
        }.tint(palette.accent).fieldSheetAppearance()
    }
}
