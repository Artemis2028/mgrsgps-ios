import GridFixCore
import SwiftUI

/// Settings sheet opened from the gear on Position. Same blackout language
/// as the rest of the app; night mode recolors this screen too.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var location: LocationService
    @Environment(\.dismiss) private var dismiss

    @State private var manualOn = false
    @State private var asGridMagnetic = true
    @State private var east = true
    @State private var draft = ""

    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Display")
                    faceBlock
                    nightBlock

                    section("Grid & units")
                    digitsBlock
                    latLonBlock
                    unitsBlock
                    angleBlock
                    northBlock
                    declinationBlock
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Blackout.label(15))
                        .foregroundStyle(palette.accent)
                }
            }
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .environment(\.fieldNight, settings.nightMode)
        .preferredColorScheme(.dark)
        .onAppear { loadDraft() }
    }

    private func section(_ title: String) -> some View {
        SectionLabel(text: title)
    }

    private var faceBlock: some View {
        block("Position face") {
            BlackoutSegments(
                options: PositionFace.allCases.map(\.title),
                selected: settings.face.rawValue,
                palette: palette
            ) { index in
                if let face = PositionFace(rawValue: index) { settings.face = face }
            }
            caption(faceCaption)
        }
    }

    private var faceCaption: String {
        switch settings.face {
        case .glance:
            return "Glance: the grid as two big numbers."
        case .lensatic:
            return "Lensatic: issued-compass dial, grid on the glass, heading under the index."
        case .dial:
            return "Dial: a clean compass card with the grid and a heading mark."
        }
    }

    private var nightBlock: some View {
        block("Night mode") {
            Toggle(isOn: $settings.nightMode) {
                Text("Red-on-black, to keep night vision")
                    .font(Blackout.label(14, weight: .regular))
                    .foregroundStyle(palette.ink)
            }
            .tint(palette.accent)
        }
    }

    private var digitsBlock: some View {
        block("MGRS precision") {
            BlackoutSegments(
                options: ["4", "6", "8", "10"],
                selected: [4, 6, 8, 10].firstIndex(of: settings.mgrsDigits) ?? 2,
                palette: palette
            ) { index in
                settings.setMgrsDigits([4, 6, 8, 10][index])
            }
        }
    }

    private var latLonBlock: some View {
        block("Lat / Lon format") {
            BlackoutSegments(
                options: ["DD", "DDM", "DMS"],
                selected: settings.latLonFormat.rawValue,
                palette: palette
            ) { index in
                if let f = LatLonFormat(rawValue: index) { settings.latLonFormat = f }
            }
        }
    }

    private var unitsBlock: some View {
        block("Units") {
            BlackoutSegments(
                options: ["Metric", "Imperial", "Nautical"],
                selected: settings.units.rawValue,
                palette: palette
            ) { index in
                if let u = DistanceUnit(rawValue: index) { settings.units = u }
            }
        }
    }

    private var angleBlock: some View {
        block("Angle") {
            BlackoutSegments(
                options: ["Degrees", "Mils"],
                selected: settings.angleUnit.rawValue,
                palette: palette
            ) { index in
                if let u = AngleUnit(rawValue: index) { settings.angleUnit = u }
            }
        }
    }

    private var northBlock: some View {
        block("North") {
            BlackoutSegments(
                options: NorthReference.allCases.map(\.title),
                selected: settings.northRef.rawValue,
                palette: palette
            ) { index in
                if let n = NorthReference(rawValue: index) { settings.northRef = n }
            }
            caption("Headings and azimuths use this reference. Magnetic needs a declination; a missing one stays a dash, not 0.")
        }
    }

    private var declinationBlock: some View {
        block("Declination") {
            Toggle(isOn: $manualOn) {
                Text("Manual G-M angle")
                    .font(Blackout.label(14, weight: .regular))
                    .foregroundStyle(palette.ink)
            }
            .tint(palette.accent)
            .onChange(of: manualOn) { on in
                if !on { settings.declinationOverride = nil }
                else { applyDraft() }
            }

            if manualOn {
                BlackoutSegments(
                    options: ["G-M angle", "Declination"],
                    selected: asGridMagnetic ? 0 : 1,
                    palette: palette
                ) { index in
                    asGridMagnetic = index == 0
                    applyDraft()
                }
                HStack(spacing: 10) {
                    TextField("0.0", text: $draft)
                        .keyboardType(.decimalPad)
                        .font(Blackout.numerals(18, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color(white: 0.08))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.hairline))
                        .onChange(of: draft) { _ in applyDraft() }
                    BlackoutSegments(
                        options: ["E", "W"],
                        selected: east ? 0 : 1,
                        palette: palette
                    ) { index in
                        east = index == 0
                        applyDraft()
                    }
                    .frame(width: 120)
                }
            }

            caption(declinationCaption)
        }
    }

    private var declinationCaption: String {
        let reading = resolvedReading
        var line = reading.display
        line += " · \(reading.source.rawValue)"
        if reading.modelExpired { line += " · MODEL EXPIRED" }
        if manualOn, settings.declinationOverride == nil, !draft.trimmingCharacters(in: .whitespaces).isEmpty {
            line += asGridMagnetic && location.fix == nil
                ? " · need a fix to apply a G-M angle"
                : " · not a valid angle"
        }
        return line
    }

    private var resolvedReading: DeclinationReading {
        let svc = DeclinationService(overrideDegrees: settings.declinationOverride)
        if let f = location.fix {
            return svc.declination(
                lat: f.lat, lon: f.lon,
                heightMeters: f.altitudeMeters ?? 0,
                heading: location.heading,
                isCurrentPosition: true
            )
        }
        if let o = settings.declinationOverride {
            return DeclinationReading(degreesEast: o, source: .override, modelExpired: false)
        }
        return DeclinationReading(degreesEast: nil, source: .none, modelExpired: false)
    }

    private func loadDraft() {
        if let o = settings.declinationOverride {
            manualOn = true
            asGridMagnetic = false
            east = o >= 0
            draft = String(format: "%.1f", abs(o))
        } else {
            manualOn = false
            draft = ""
        }
    }

    private func applyDraft() {
        guard manualOn else { return }
        let conv: Double? = location.fix.map { UTM.gridConvergence(lat: $0.lat, lon: $0.lon) }
        guard let resolved = ManualDeclination.resolve(
            text: draft,
            east: east,
            mils: settings.angleUnit == .mils,
            asGridMagnetic: asGridMagnetic,
            convergence: conv
        ) else { return }
        settings.declinationOverride = resolved
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Blackout.label(15, weight: .semibold))
                .foregroundStyle(palette.ink)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Blackout.label(12, weight: .regular))
            .foregroundStyle(palette.inkDim)
            .fixedSize(horizontal: false, vertical: true)
    }
}
