import GridFixCore
import SwiftUI

/// Position: Glance, Lensatic, or Dial, from the saved face.
/// Settings is a sheet from the gear — not a fifth tab.
struct PositionView: View {
    var onOrientation: () -> Void = {}
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showSettings = false
    @State private var qrRequest: PositionQRRequest?

    private var compact: Bool { verticalSizeClass == .compact }
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
                heading: location.usableHeading,
                isCurrentPosition: true
            )
        }
        if let o = settings.declinationOverride {
            return DeclinationReading(degreesEast: o, source: .override, modelExpired: false)
        }
        return DeclinationReading(degreesEast: nil, source: .none, modelExpired: false)
    }

    /// CI has no magnetometer. `-startHeading 47` paints a real reading
    /// so Lensatic and Dial are instruments, not an empty dash.
    private var injectedHeading: Double? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-startHeading"),
              args.index(after: idx) < args.endIndex,
              let v = Double(args[args.index(after: idx)]),
              v >= 0, v < 360 else { return nil }
        return v
        #else
        return nil
        #endif
    }

    private var movementHeading: MovementHeading? {
        if let injected = injectedHeading { return .init(degreesTrue: injected,source: .compass) }
        let h = location.usableHeading
        let compass = FieldMath.heading(
            trueHeading: settings.declinationOverride == nil && (h?.trueHeading ?? -1) >= 0 ? h?.trueHeading : nil,
            magneticHeading: h?.magneticHeading, north: .trueNorth,
            declinationEast: reading.degreesEast, convergence: nil)
        return MovementHeading.position(face: settings.face,compassTrue: compass,fix: location.fix)
    }
    private var headingDegrees: Double? {
        if let injected = injectedHeading { return injected }
        guard let heading = movementHeading, settings.northRef != .grid || location.fix != nil else { return nil }
        return FieldMath.toNorthRef(angleTrue: heading.degreesTrue,north: settings.northRef,
                                   declinationEast: reading.degreesEast,
                                   convergence: location.fix.map { UTM.gridConvergence(lat: $0.lat,lon: $0.lon) } ?? 0)
    }
    private var headingLabel: String {
        if movementHeading?.source == .course { return location.quality?.stale == true ? "LAST CRS" : "COURSE" }
        return "HEADING"
    }
    private var headingLine: String {
        let letter = settings.northRef.letter
        let label = movementHeading?.source == .course ? "CRS" : "HDG"
        guard let h = headingDegrees else { return "\(label) — \(letter)" }
        return "\(label) \(Format.angle(degrees: h, unit: settings.angleUnit)) \(letter)"
    }

    var body: some View {
        ZStack {
            FieldScreenBackground()
            VStack(alignment: .leading, spacing: 16) {
                header
                if location.reducedAccuracy {
                    reducedAccuracyNotice
                    Spacer(minLength: 0)
                } else {
                    if compact {
                        HStack(alignment: .top,spacing: 24) {
                            if settings.face == .glance {
                                ScrollView { grid.frame(maxWidth: .infinity,alignment: .leading) }.frame(maxWidth: .infinity)
                            } else { instrument.frame(maxWidth: .infinity) }
                            ScrollView {
                                VStack(alignment: .leading,spacing: 12) { precisionPicker; footer }
                            }.frame(maxWidth: .infinity)
                        }
                    } else {
                        switch settings.face {
                        case .glance: glance
                        case .lensatic, .dial: instrument
                        }
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
        .sheet(item: $qrRequest) { PositionQRView(request: $0, night: settings.nightMode) }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(location)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Position").font(.system(compact ? .title2 : .largeTitle, design: .rounded, weight: .bold))
            Spacer()
            if let quality = location.quality {
                Text(location.reducedAccuracy ? "PRECISE OFF" : quality.word)
                    .font(Blackout.label(11))
                    .tracking(1.4)
                    .foregroundStyle(quality.bars >= 4 ? palette.good : quality.bars >= 2 ? palette.accent : palette.warn)
                    .accessibilityIdentifier("position-fix-quality")
            } else {
                Text("ACQUIRING")
                    .font(Blackout.label(11))
                    .tracking(1.4)
                    .foregroundStyle(palette.inkDim)
            }
            Button {
                if let fix = location.usableFix {
                    qrRequest = PositionQRRequest(title: "My position", lat: fix.lat, lon: fix.lon,
                        label: "Position " + String(Format.dtg(Date()).prefix(7)), digits: settings.mgrsDigits)
                }
            } label: {
                Image(systemName: "qrcode").frame(width: 44, height: 44)
            }.buttonStyle(.plain).disabled(location.usableFix == nil)
                .accessibilityLabel("Share position as QR code").accessibilityIdentifier("position-share-qr")
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
            .contextMenu { Button("Orientation",action: onOrientation).accessibilityIdentifier("position-orientation-shortcut") }
            .accessibilityHint("Touch and hold for orientation controls")
        }
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: 22) {
            grid
            precisionPicker
            // Keep the whole grid together while making every readout reachable
            // above the larger opaque night tab bar and at larger text sizes.
            ScrollView { footer.frame(maxWidth: .infinity,alignment: .leading) }
                .accessibilityIdentifier("position-details")
        }
    }

    @ViewBuilder
    private var grid: some View {
        if let p = parts {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.gzd + " " + p.square)
                    .font(Blackout.numerals(compact ? 22 : 30, weight: .semibold))
                    .foregroundStyle(palette.inkDim)
                Text(p.easting)
                    .font(Blackout.numerals(compact ? 48 : 62, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text(p.northing)
                    .font(Blackout.numerals(compact ? 48 : 62, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text(Phonetic.mgrs(p.full))
                    .font(Blackout.label(12, weight: .medium))
                    .foregroundStyle(palette.inkDim)
                    .padding(.top, 8)
                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("position-phonetic")
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        } else {
            Text("— — — — —")
                .font(Blackout.numerals(compact ? 48 : 62, weight: .bold))
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
        Picker("\(settings.gridName) precision", selection: Binding(get: { settings.mgrsDigits }, set: { settings.setMgrsDigits($0) })) {
            ForEach([4, 6, 8, 10], id: \.self) { digits in
                Text("\(digits) digits").tag(digits)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("\(settings.gridName) precision")
    }

    private var instrument: some View {
        CompassInstrument(
            style: settings.face == .lensatic ? .lensatic : .dial,
            heading: headingDegrees,
            northLetter: settings.northRef.letter,
            palette: palette,
            gzdSquare: parts.map { $0.gzd + " " + $0.square } ?? "—",
            easting: parts?.easting ?? "—",
            northing: parts?.northing ?? "—",
            statusLine: statusLine
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusLine: String {
        guard let f = location.fix, let quality = location.quality else { return "ACQUIRING" }
        let acc = Format.accuracy(meters: f.accuracyMeters, unit: settings.units)
        return quality.stale ? "STALE \(quality.ageText) · \(acc)" : "\(quality.word) \(acc)"
    }

    @ViewBuilder
    private var footer: some View {
        if let f = location.fix {
            VStack(alignment: .leading, spacing: 6) {
                if let quality = location.quality {
                    HStack(spacing: 8) {
                        HStack(alignment: .bottom,spacing: 2) {
                            ForEach(0..<5) { index in
                                Rectangle().fill(index < quality.bars ? (quality.bars >= 4 ? palette.good : quality.bars >= 2 ? palette.accent : palette.warn) : palette.inkDim.opacity(0.25))
                                    .frame(width: 3,height: CGFloat(4+index*2))
                            }
                        }.accessibilityElement(children: .ignore)
                            .accessibilityLabel("Accuracy quality: \(quality.word), \(quality.bars) of 5")
                        Text(quality.stale ? "Last fix \(quality.ageText) ago · wait for a fresh fix" : "Fix age \(quality.ageText)")
                            .font(Blackout.label(12)).foregroundStyle(quality.stale ? palette.warn : palette.inkDim)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("position-fix-age")
                    }
                }
                row(headingLabel, headingLine).accessibilityElement(children: .combine).accessibilityIdentifier("position-heading-readout")
                row("DECL", reading.display + " · " + reading.source.rawValue,
                    tint: reading.degreesEast == nil ? palette.warn : palette.ink)
                row("ACCURACY", Format.accuracy(meters: f.accuracyMeters, unit: settings.units))
                row(location.quality?.stale == true ? "LAST SPEED" : "SPEED",
                    f.speedMetersPerSecond.flatMap { $0.isFinite && $0 >= 0 ? Format.speed(metersPerSecond: $0,unit: settings.units) : nil } ?? "—")
                    .accessibilityElement(children: .combine).accessibilityIdentifier("position-speed-readout")
                if let quality = location.quality, settings.mgrsDigits > quality.trustDigits {
                    row("TRUST", quality.stale ? "\(quality.trustDigits)-digit · stale position" : "\(quality.trustDigits)-digit at this accuracy", tint: palette.warn)
                }
                if let alt = f.altitudeMeters {
                    row("ALTITUDE", Format.altitude(meters: alt, unit: settings.units))
                }
                row("UTM", Format.utm(UTM.coordinate(lat: f.lat, lon: f.lon)))
                row("LAT/LON", Format.latLon(lat: f.lat, lon: f.lon, format: settings.latLonFormat))
                row("DTG", Format.dtg(f.timestamp))
            }
        } else {
            row(headingLabel, headingLine).accessibilityElement(children: .combine).accessibilityIdentifier("position-heading-readout")
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
