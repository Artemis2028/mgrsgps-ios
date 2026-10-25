import GridFixCore
import SwiftUI

struct FieldFixRequest: Identifiable {
    let id = UUID()
    let mode: FieldFix.Mode
    let centre: GeoPoint
    let position: GeoPoint?
}

struct FieldFixPanel: View {
    let request: FieldFixRequest
    let onShow: (GeoPoint) -> Void
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var waypoints: WaypointStore
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var second = ""
    @State private var azimuth1 = ""
    @State private var azimuth2 = ""
    @State private var name = ""
    @State private var error: String?
    @State private var points: [KnownPoint] = []
    @State private var openedAt = Date()
    @FocusState private var focused: Int?
    private struct KnownPoint: Identifiable { let id: String; let name: String; let point: GeoPoint }
    private struct Resolution { var solution: FieldFix.Solution?; var error: String?; var expired = false }
    private var title: String { request.mode == .resection ? "Resection" : "Intersection" }
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    private var secondaryInk: Color { settings.nightMode ? palette.ink : palette.inkDim }
    private var rowBackground: Color { settings.nightMode ? .black : Color(uiColor: .secondarySystemGroupedBackground) }
    private var angleLabel: String { settings.angleUnit == .mils ? "mils" : "degrees" }
    private var resolution: Resolution {
        guard let a = points.first(where: { $0.id == first }),let b = points.first(where: { $0.id == second }) else { return Resolution() }
        var expired = false
        do {
            let service = DeclinationService(overrideDegrees: settings.declinationOverride)
            let solution = try FieldFix.solve(mode: request.mode,point1: a.point,point2: b.point,azimuth1: azimuth1,azimuth2: azimuth2,
                                              angleUnit: settings.angleUnit,northReference: settings.northRef.rawValue) { point in
                let reading = service.declination(lat: point.lat,lon: point.lon,date: openedAt,isCurrentPosition: false)
                expired = expired || reading.modelExpired
                return reading.degreesEast
            }
            return .init(solution: solution,expired: expired)
        } catch {
            return .init(error: azimuth1.isEmpty && azimuth2.isEmpty ? nil : error.localizedDescription)
        }
    }
    var body: some View {
        let result = resolution
        NavigationStack {
            Form {
                Section {
                    Text(request.mode == .resection ? "Sight an azimuth to each of two known points. The back-azimuths locate you." : "Enter the azimuth to the target from each of two observation points.")
                    Text("\(angleLabel.capitalized) · \(settings.northRef.title) north (\(settings.northRef.letter))").font(.subheadline)
                    Text("Point coordinates are captured when this tool opens. The phone's current heading is not used for remote points.").font(.footnote).foregroundStyle(secondaryInk)
                }.listRowBackground(rowBackground)
                Section(request.mode == .resection ? "Known point 1" : "Observer 1") {
                    pointPicker(selection: $first,index: 1)
                    LabeledContent("Azimuth (\(angleLabel) \(settings.northRef.letter))") {
                        TextField("0",text: $azimuth1).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                            .focused($focused,equals: 1).accessibilityIdentifier("field-fix-azimuth-1")
                    }
                }.listRowBackground(rowBackground)
                Section(request.mode == .resection ? "Known point 2" : "Observer 2") {
                    pointPicker(selection: $second,index: 2)
                    LabeledContent("Azimuth (\(angleLabel) \(settings.northRef.letter))") {
                        TextField("0",text: $azimuth2).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                            .focused($focused,equals: 2).accessibilityIdentifier("field-fix-azimuth-2")
                    }
                }.listRowBackground(rowBackground)
                Section("Calculated fix") {
                    if let fix = result.solution {
                        Text(fix.grid ?? "Outside \(settings.gridName) coverage").font(.system(.headline,design: .monospaced)).accessibilityIdentifier("field-fix-grid")
                        Text("Ranges: \(Format.distance(meters: fix.range1,unit: settings.units)) / \(Format.distance(meters: fix.range2,unit: settings.units))")
                            .font(.system(.subheadline,design: .monospaced)).accessibilityIdentifier("field-fix-ranges")
                        Text(String(format: "Angle of cut: %.0f°",fix.cutAngle)).accessibilityIdentifier("field-fix-cut")
                        if fix.poorCut { Text("Poor angle of cut - choose points that cross closer to 90°.").foregroundStyle(palette.warn).accessibilityIdentifier("field-fix-poor-cut") }
                        if result.expired { Text("The magnetic model is past its validity period; bearings use an extrapolation.").foregroundStyle(palette.warn) }
                        if settings.northRef == .magnetic,let override = settings.declinationOverride { Text(String(format: "Manual declination: %.1f° %@",abs(override),override >= 0 ? "E" : "W")).font(.footnote) }
                        Text("Eight-digit grid; a compass fix does not imply GPS accuracy. Verify the geometry before using it.").font(.footnote).foregroundStyle(secondaryInk)
                    } else {
                        Text(result.error ?? "Choose two different known points and enter both azimuths. Rays must cross ahead of both points within 100 km.")
                            .foregroundStyle(result.error == nil ? secondaryInk : palette.warn).accessibilityIdentifier("field-fix-message")
                    }
                }.listRowBackground(rowBackground)
                Section {
                    TextField("Waypoint name",text: $name).focused($focused,equals: 3).accessibilityIdentifier("field-fix-name")
                    Button("Show on map") { if let fix = result.solution { onShow(fix.point); dismiss() } }
                        .disabled(result.solution == nil).accessibilityIdentifier("field-fix-show")
                    Button("Save waypoint") { if let fix = result.solution { save(fix) } }
                        .disabled(result.solution == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("field-fix-save")
                    if let error { Text(error).foregroundStyle(palette.warn) }
                }.listRowBackground(rowBackground)
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }.foregroundStyle(palette.ink)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline).autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil }.accessibilityIdentifier("field-fix-keyboard-done") }
            }
            .onAppear { prepare() }
        }.tint(palette.accent).fieldSheetAppearance()
    }
    private func pointPicker(selection: Binding<String>,index: Int) -> some View {
        FieldPointPicker(selection: selection,choices: points.map { .init(id: $0.id,name: $0.name,coordinate: $0.point) },
                         title: "Choose point",identifier: "field-fix-point-\(index)",choicePrefix: "field-fix-choice-\(index)-",
                         onOpen: { focused = nil })
    }
    private func prepare() {
        guard points.isEmpty else { return }
        var choices: [KnownPoint] = []
        if request.mode == .intersection,let position = request.position { choices.append(.init(id: "position",name: "My position",point: position)) }
        choices.append(.init(id: "centre",name: "Crosshair",point: request.centre))
        choices += waypoints.waypoints.map { KnownPoint(id: "wp:"+$0.id,name: $0.name,point: .init(lat: $0.lat,lon: $0.lon)) }
        points = choices; first = choices[0].id; second = choices.count > 1 ? choices[1].id : choices[0].id
        openedAt = Date(); name = (request.mode == .resection ? "RESECTION " : "TGT ")+Format.dtg(openedAt).prefix(7)
    }
    private func save(_ fix: FieldFix.Solution) {
        let waypoint = Waypoint(name: name.trimmingCharacters(in: .whitespacesAndNewlines),lat: fix.point.lat,lon: fix.point.lon,symbol: "target",affiliation: request.mode == .resection ? "none" : "hostile")
        do { _ = try waypoints.restore(waypoints: [waypoint],folders: []); dismiss() }
        catch { self.error = "Could not save waypoint: "+error.localizedDescription }
    }
}
