import GridFixCore
import SwiftUI

struct PracticeCourseView: View {
    @EnvironmentObject private var course: PracticeSession
    @EnvironmentObject private var waypoints: WaypointStore
    @EnvironmentObject private var field: FieldDataStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var count = 5
    @State private var radius = 1000
    @State private var folder = ""
    @State private var ending: String?
    @State private var showReset = false
    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }
    private var rowBackground: Color { settings.nightMode ? .black : Color(white: 0.12) }
    private var eligible: [String] { waypoints.folders.map(\.name).filter { folder in waypoints.waypoints.filter { $0.folder == folder }.count >= 2 } }
    var body: some View {
        NavigationStack {
            Form {
                if let error = course.error {
                    Section {
                        Text(error).foregroundStyle(palette.warn).accessibilityIdentifier("practice-error")
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-uiTesting"), ProcessInfo.processInfo.arguments.contains("-uiTestPracticeHistoryWriteFailure") {
                            Button("Repair test result storage") {
                                let file = FileManager.default.temporaryDirectory.appendingPathComponent("mgrsgps-ui-tests/field-data-v1.zip")
                                if (try? FileManager.default.contentsOfDirectory(atPath: file.path))?.isEmpty == true { try? FileManager.default.removeItem(at: file) }
                            }.accessibilityIdentifier("practice-repair-result")
                        }
                        #endif
                    }.listRowBackground(rowBackground)
                }
                if course.damaged {
                    Section("Saved course needs attention") {
                        Text("The unreadable session is kept. Resetting preserves a copy and unlocks navigation; waypoints, tracks and results are retained.")
                        Button("Preserve damaged session and reset",role: .destructive) { showReset = true }
                    }.listRowBackground(rowBackground)
                } else if let result = course.summary {
                    Section("Course complete") { resultRows(result) }.listRowBackground(rowBackground)
                    Button("Done") { course.dismissSummary(); dismiss() }.accessibilityIdentifier("practice-summary-done").listRowBackground(rowBackground)
                } else if let active = course.active {
                    progress(active)
                } else {
                    Section("Create course") {
                        Picker("Setup",selection: $mode) { Text("Random points").tag(0); Text("From folder").tag(1) }.pickerStyle(.segmented)
                        if mode == 0 {
                            Picker("Points",selection: $count) { ForEach([3,4,5,6,8],id: \.self) { Text("\($0)").tag($0) } }
                            Picker("Radius",selection: $radius) { Text("500 m").tag(500); Text("1 km").tag(1000); Text("2 km").tag(2000) }
                            Text(location.usableFix == nil ? "Waiting for a recent, precise GPS fix." : "Points are scattered 120 m to the chosen radius around you, at least 120 m apart, and saved in a course folder.")
                        } else {
                            FieldChoicePicker(selection: $folder,title: "Folder",choices: eligible.map { .init(id: $0,title: $0) },identifier: "practice-folder")
                            Text("Checkpoints follow their saved list order, including hidden points. A folder needs at least two points.")
                        }
                        Text("Find checkpoints in order. Your position and its full accuracy circle must fit inside 25 m. Scoring runs with the app open; elapsed time continues while closed.")
                            .font(.footnote)
                        Button("Start course") {
                            if mode == 0 { course.startRandom(count: count,radius: radius,fix: location.usableFix) }
                            else { course.startFolder(folder) }
                        }.disabled(mode == 0 ? location.usableFix == nil : !eligible.contains(folder))
                            .accessibilityIdentifier("practice-start")
                    }.listRowBackground(rowBackground)
                    if !field.document.courseHistory.isEmpty {
                        Section("Practice log") {
                            ForEach(Array(field.document.courseHistory.sorted { $0.started > $1.started }.enumerated()),id: \.offset) { _, result in
                                DisclosureGroup("\(PracticeCourse.time(result.total)) · \(result.points) points · \(result.name)") { resultRows(result) }
                            }
                        }.listRowBackground(rowBackground)
                    }
                }
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }
            .foregroundStyle(palette.ink)
            .navigationTitle("Practice course").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Practice course").font(.headline).foregroundStyle(palette.ink) }
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
            .confirmationDialog("End this course? Saved checkpoints remain; unfinished runs are not added to results.",isPresented: Binding(get: { ending != nil },set: { if !$0 { ending = nil } }),titleVisibility: .visible) {
                Button("End course",role: .destructive) { course.end(expectedRunID: ending); ending = nil }
            }
            .confirmationDialog("Preserve a copy of the unreadable session and reset?",isPresented: $showReset,titleVisibility: .visible) { Button("Reset course session",role: .destructive) { course.resetDamaged() } }
        }.tint(palette.accent).environment(\.fieldNight,settings.nightMode).fieldSheetAppearance()
    }
    @ViewBuilder private func progress(_ active: PracticeCourse) -> some View {
        Section(active.paused ? "Course paused" : "Course · \(active.name)") {
            if let reason = active.pauseReason { Text(reason).foregroundStyle(palette.warn).accessibilityIdentifier("practice-paused") }
            Text(active.done ? (course.finalizing ? "Saving result…" : "Completed · result not saved") : "CP \(active.nextIndex+1) of \(active.waypointIDs.count)")
                .font(.title2.monospacedDigit()).accessibilityIdentifier("practice-progress")
            if let id = active.targetID, let target = waypoints.waypoints.first(where: { $0.id == id }) {
                Text(target.name).font(.headline)
                Text(MGRS.string(lat: target.lat,lon: target.lon,digits: settings.mgrsDigits) ?? "—").font(.system(.body,design: .monospaced))
            }
            TimelineView(.periodic(from: .now,by: 1)) { timeline in
                let end = active.done ? (active.foundAt.last ?? active.startedAt) : Int64(timeline.date.timeIntervalSince1970*1000)
                Text("Elapsed \(PracticeCourse.time(end-active.startedAt))").monospacedDigit()
            }
            ForEach(Array(active.foundAt.enumerated()),id: \.offset) { i,time in
                Text("CP \(i+1) · \(PracticeCourse.time(time-(i == 0 ? active.startedAt : active.foundAt[i-1])))")
            }
            if !active.paused && !active.done { Text("Navigate is locked to this checkpoint and advances automatically. Haptic guidance is optional and separate from scoring.").font(.footnote) }
            Button("Continue") { dismiss() }
            if course.finalizing { ProgressView("Saving course result…").accessibilityIdentifier("practice-saving-result") }
            if active.done { Button("Retry saving result") { course.retryResult() }.disabled(course.finalizing).accessibilityIdentifier("practice-retry-result") }
            Button("End course…",role: .destructive) { ending = active.runID }.disabled(active.done).accessibilityIdentifier("practice-end")
        }.listRowBackground(rowBackground)
    }
    private func resultRows(_ result: Backup.CourseResult) -> some View {
        VStack(alignment: .leading,spacing: 8) {
            Text(PracticeCourse.time(result.total)).font(.largeTitle.monospacedDigit())
            Text("\(result.points) points · \(result.name)")
            ForEach(Array(result.splits.enumerated()),id: \.offset) { i,split in Text("CP \(i+1) · \(PracticeCourse.time(split))") }
        }.accessibilityIdentifier("practice-result")
    }
}
