import GridFixCore
import SwiftUI

struct SunMoonPlanningView: View {
    let request: FieldPlanningRequest
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    init(request: FieldPlanningRequest) { self.request = request; _date = State(initialValue: request.date) }
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    private var secondaryInk: Color { settings.nightMode ? palette.ink : palette.inkDim }
    private var rowBackground: Color { settings.nightMode ? .black : Color(uiColor: .secondarySystemGroupedBackground) }
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = request.timeZone; return value }
    var body: some View {
        let result = Result { try SunMoonPlan(point: request.centre,date: date,timeZone: request.timeZone) }
        NavigationStack {
            Form {
                Section("Map-centre location") {
                    Text(MGRS.parts(lat: request.centre.lat,lon: request.centre.lon,digits: 8)?.full ?? Format.latLon(lat: request.centre.lat,lon: request.centre.lon,format: .decimalDegrees))
                        .font(.system(.subheadline,design: .monospaced))
                    Text("Local times use the device zone: "+request.timeZone.identifier+". Zulu is UTC.").font(.footnote).foregroundStyle(secondaryInk)
                }.listRowBackground(rowBackground)
                Section("Planning date") {
                    DatePicker("Date",selection: $date,displayedComponents: .date).datePickerStyle(.compact).accessibilityIdentifier("planning-date")
                    HStack {
                        Button { step(-1) } label: { Label("Prev",systemImage: "chevron.left") }.accessibilityIdentifier("planning-prev")
                        Spacer()
                        Button("Today") { date = Date() }.accessibilityIdentifier("planning-today")
                        Spacer()
                        Button { step(1) } label: { Label("Next",systemImage: "chevron.right") }.accessibilityIdentifier("planning-next")
                    }.buttonStyle(.borderless)
                }.listRowBackground(rowBackground)
                switch result {
                case .success(let plan):
                    Section {
                        Text(plan.dateLabel).font(.headline).accessibilityIdentifier("planning-day")
                        ForEach(plan.sun) { event in eventRow(event) }
                    } header: { Text("Sun · local / Zulu") }
                    .listRowBackground(rowBackground)
                    Section("Moon · local / Zulu") {
                        Text("\(plan.phase) · \(plan.illumination)% illumination").font(.headline).accessibilityIdentifier("moon-phase")
                        ForEach(plan.moon) { event in eventRow(event) }
                    }.listRowBackground(rowBackground)
                case .failure(let error):
                    Section { Text(error.localizedDescription).foregroundStyle(palette.warn) }.listRowBackground(rowBackground)
                }
                Section {
                    Text("BMNT/EENT are nautical twilight (12° below the horizon); civil dawn/dusk use 6°. ---- means no crossing was calculated for that event.")
                    Text("For the map-centre location captured when opened. Offline approximate sun/moon model; moon times about ±5 minutes. Local clock changes can affect moon-event coverage. Verify critical movement times.")
                }.font(.footnote).foregroundStyle(secondaryInk).listRowBackground(rowBackground)
            }
            .environment(\.calendar,calendar).environment(\.timeZone,request.timeZone)
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }.foregroundStyle(palette.ink)
            .navigationTitle("Sun & moon").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.tint(palette.accent).fieldSheetAppearance()
    }
    private func eventRow(_ event: SunMoonPlan.Event) -> some View {
        LabeledContent(event.name) {
            HStack(spacing: 12) {
                Text(event.local).accessibilityIdentifier("sunmoon-"+event.id+"-local")
                Text(event.zulu).accessibilityIdentifier("sunmoon-"+event.id+"-zulu")
            }.font(.system(.subheadline,design: .monospaced)).lineLimit(1).minimumScaleFactor(0.65)
        }
    }
    private func step(_ delta: Int) { if let next = calendar.date(byAdding: .day,value: delta,to: date) { date = next } }
}

struct DeclinationPlanningView: View {
    let request: FieldPlanningRequest
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    private var palette: FieldPalette { .init(night: settings.nightMode) }
    private var secondaryInk: Color { settings.nightMode ? palette.ink : palette.inkDim }
    private var rowBackground: Color { settings.nightMode ? .black : Color(uiColor: .secondarySystemGroupedBackground) }
    var body: some View {
        let value = DeclinationDiagramReading.at(request.centre,date: request.date,override: settings.declinationOverride)
        NavigationStack {
            Form {
                Section("Map centre") {
                    Text(MGRS.parts(lat: request.centre.lat,lon: request.centre.lon,digits: 8)?.full ?? Format.latLon(lat: request.centre.lat,lon: request.centre.lon,format: .decimalDegrees))
                        .font(.system(.subheadline,design: .monospaced))
                    DeclinationNorthDiagram(reading: value,ink: palette.ink,accent: palette.accent).frame(height: 175).accessibilityIdentifier("declination-diagram")
                    HStack { Text("★ TN"); Spacer(); Text("- - GN"); Spacer(); Text("↗ MN").foregroundStyle(palette.accent) }.font(.caption)
                    Text("Diagram not to scale - use the printed values.").font(.footnote).foregroundStyle(secondaryInk)
                }.listRowBackground(rowBackground)
                Section("Reference angles") {
                    LabeledContent("Magnetic declination") { Text(DeclinationDiagramReading.eastWest(value.magnetic)).monospacedDigit().accessibilityIdentifier("declination-magnetic") }
                    LabeledContent("Grid convergence") { Text(DeclinationDiagramReading.eastWest(value.convergence)).monospacedDigit().accessibilityIdentifier("declination-convergence") }
                    LabeledContent("G-M angle") { Text(value.gridMagneticAngle.map { String(format: "%.1f°",$0) } ?? "Unavailable").monospacedDigit().accessibilityIdentifier("declination-grid-magnetic") }
                    Text(value.manual ? "Manual declination from Settings" : "World Magnetic Model at map centre")
                        .font(.footnote).foregroundStyle(secondaryInk).accessibilityIdentifier("declination-source")
                    if value.manual { Text("Bundled model comparison: "+DeclinationDiagramReading.eastWest(value.model)).font(.footnote).foregroundStyle(secondaryInk) }
                    if value.modelExpired { Text("The bundled magnetic model is past its validity period; its values are extrapolated.").font(.footnote).foregroundStyle(palette.warn) }
                    if value.magnetic == nil { Text("Magnetic reference unavailable. No magnetic arm or zero declination has been substituted.").foregroundStyle(palette.warn) }
                    if value.convergence == nil { Text("Grid north is unavailable outside 80°S-84°N UTM coverage.").foregroundStyle(palette.warn) }
                }.listRowBackground(rowBackground)
                Section {
                    Text("Computed for the map centre captured when opened, not the phone's compass heading. A map-sheet declination or G-M angle can be pinned in Settings.")
                }.font(.footnote).foregroundStyle(secondaryInk).listRowBackground(rowBackground)
            }
            .scrollContentBackground(.hidden).background { FieldScreenBackground() }.foregroundStyle(palette.ink)
            .navigationTitle("Declination").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.tint(palette.accent).fieldSheetAppearance()
    }
}

private struct DeclinationNorthDiagram: View {
    let reading: DeclinationDiagramReading
    let ink: Color
    let accent: Color
    var body: some View {
        Canvas { context,size in
            let base = CGPoint(x: size.width/2,y: size.height-12),length = size.height-36
            func tip(_ degrees: Double) -> CGPoint {
                let angle = (degrees-90)*Double.pi/180
                return .init(x: base.x+length*cos(angle),y: base.y+length*sin(angle))
            }
            func arm(_ degrees: Double,_ color: Color,dashed: Bool = false) {
                var line = Path(); line.move(to: base); line.addLine(to: tip(degrees))
                context.stroke(line,with: .color(color),style: .init(lineWidth: 2,dash: dashed ? [5,3] : []))
            }
            arm(0,ink)
            context.draw(Text("★").font(.system(size: 15)).foregroundColor(ink),at: tip(0))
            if let grid = reading.convergence { arm(DeclinationDiagramReading.displayAngle(grid),ink,dashed: true) }
            if let magnetic = reading.magnetic {
                let degrees = DeclinationDiagramReading.displayAngle(magnetic),end = tip(degrees)
                arm(degrees,accent)
                let angle = (degrees-90)*Double.pi/180+2.6
                var head = Path(); head.move(to: end); head.addLine(to: .init(x: end.x+12*cos(angle),y: end.y+12*sin(angle)))
                context.stroke(head,with: .color(accent),lineWidth: 2)
            }
            context.stroke(Path(ellipseIn: .init(x: base.x-3,y: base.y-3,width: 6,height: 6)),with: .color(ink),lineWidth: 1.5)
        }.accessibilityElement(children: .ignore).accessibilityLabel("True, grid and magnetic north diagram. Not to scale. See printed reference angles.")
    }
}
