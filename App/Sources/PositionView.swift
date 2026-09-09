import GridFixCore
import SwiftUI

/// Position: Glance, Lensatic, or Dial, from the saved face.
/// Settings is a sheet from the gear — not a fifth tab.
struct PositionView: View {
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings
    @State private var showSettings = false

    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }

    private var parts: MGRS.Parts? {
        guard let f = location.fix else { return nil }
        return MGRS.parts(lat: f.lat, lon: f.lon, digits: settings.mgrsDigits)
    }

    private var reading: DeclinationReading {
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

    private var headingDegrees: Double? {
        let h = location.heading
        let trueH: Double? = {
            guard let h, h.headingAccuracy >= 0, h.trueHeading >= 0 else { return nil }
            return h.trueHeading
        }()
        let magH: Double? = {
            guard let h, h.headingAccuracy >= 0, h.magneticHeading >= 0 else { return nil }
            return h.magneticHeading
        }()
        let conv: Double? = location.fix.map { UTM.gridConvergence(lat: $0.lat, lon: $0.lon) }
        return FieldMath.heading(
            trueHeading: trueH,
            magneticHeading: magH,
            north: settings.northRef,
            declinationEast: reading.degreesEast,
            convergence: conv
        )
    }

    private var headingLine: String {
        let letter = settings.northRef.letter
        guard let h = headingDegrees else { return "HDG — \(letter)" }
        return "HDG \(Format.angle(degrees: h, unit: settings.angleUnit)) \(letter)"
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                header
                if location.reducedAccuracy {
                    reducedAccuracyNotice
                    Spacer(minLength: 0)
                } else {
                    switch settings.face {
                    case .glance:
                        glance
                    case .lensatic, .dial:
                        instrument
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(palette.ink)
        .environment(\.fieldNight, settings.nightMode)
        .onAppear { location.start() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(location)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            SectionLabel(text: "Position")
            Spacer()
            if let f = location.fix {
                Text(f.gradeWord)
                    .font(Blackout.label(11))
                    .tracking(1.4)
                    .foregroundStyle(f.grade >= 4 ? palette.good : f.grade >= 2 ? palette.accent : palette.warn)
            } else {
                Text("ACQUIRING")
                    .font(Blackout.label(11))
                    .tracking(1.4)
                    .foregroundStyle(palette.inkDim)
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.inkDim)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: 22) {
            grid
            Spacer(minLength: 0)
            precisionPicker
            footer
        }
    }

    @ViewBuilder
    private var grid: some View {
        if let p = parts {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.gzd + " " + p.square)
                    .font(Blackout.numerals(30, weight: .semibold))
                    .foregroundStyle(palette.inkDim)
                Text(p.easting)
                    .font(Blackout.numerals(62, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text(p.northing)
                    .font(Blackout.numerals(62, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text(Phonetic.mgrs(p.full))
                    .font(Blackout.label(12, weight: .medium))
                    .foregroundStyle(palette.inkDim)
                    .padding(.top, 8)
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        } else {
            Text("— — — — —")
                .font(Blackout.numerals(62, weight: .bold))
                .foregroundStyle(palette.inkDim)
        }
    }

    private var reducedAccuracyNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRECISE LOCATION OFF")
                .font(Blackout.label(15))
                .tracking(1.2)
                .foregroundStyle(palette.warn)
            Text("iOS is giving this app a position accurate to kilometres, "
                 + "which is not a grid. Turn on Precise Location for MGRS GPS "
                 + "in Settings before you use anything on this screen.")
                .font(Blackout.label(13, weight: .regular))
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var precisionPicker: some View {
        HStack(spacing: 0) {
            ForEach([4, 6, 8, 10], id: \.self) { d in
                let trusted = location.fix.map { d <= $0.trustedDigits } ?? true
                Button {
                    settings.setMgrsDigits(d)
                } label: {
                    Text("\(d)")
                        .font(Blackout.numerals(15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(
                            settings.mgrsDigits == d ? palette.background
                                : trusted ? palette.ink : palette.inkDim
                        )
                        .background(settings.mgrsDigits == d ? palette.accent : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.hairline))
    }

    private var instrument: some View {
        VStack(spacing: 12) {
            CompassInstrument(
                style: settings.face == .lensatic ? .lensatic : .dial,
                heading: headingDegrees,
                northLetter: settings.northRef.letter,
                palette: palette,
                gzdSquare: parts.map { $0.gzd + " " + $0.square } ?? "—",
                easting: parts?.easting ?? "—",
                northing: parts?.northing ?? "—",
                statusLine: statusLine,
                headingLine: headingLine
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            precisionPicker
            footer
        }
    }

    private var statusLine: String {
        guard let f = location.fix else { return "ACQUIRING" }
        let acc = Format.accuracy(meters: f.accuracyMeters, unit: settings.units)
        return "\(f.gradeWord) \(acc)"
    }

    @ViewBuilder
    private var footer: some View {
        if let f = location.fix {
            VStack(alignment: .leading, spacing: 6) {
                row("HEADING", headingLine)
                row("DECL", reading.display + " · " + reading.source.rawValue,
                    tint: reading.degreesEast == nil ? palette.warn : palette.ink)
                row("ACCURACY", Format.accuracy(meters: f.accuracyMeters, unit: settings.units))
                if settings.mgrsDigits > f.trustedDigits {
                    row("TRUST", "\(f.trustedDigits)-digit at this accuracy", tint: palette.warn)
                }
                if let alt = f.altitudeMeters {
                    row("ALTITUDE", Format.altitude(meters: alt, unit: settings.units))
                }
                row("UTM", Format.utm(UTM.coordinate(lat: f.lat, lon: f.lon)))
                row("LAT/LON", Format.latLon(lat: f.lat, lon: f.lon, format: settings.latLonFormat))
                row("DTG", Format.dtg(f.timestamp))
            }
        } else {
            row("HEADING", headingLine)
            row("DECL", reading.display + " · " + reading.source.rawValue)
        }
    }

    private func row(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Blackout.label(10))
                .tracking(1.2)
                .foregroundStyle(palette.inkDim)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(Blackout.numerals(13))
                .foregroundStyle(tint ?? palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
