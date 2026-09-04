import GridFixCore
import SwiftUI

/// The Glance face: the grid, big, and the two things that tell you whether to
/// believe it — how good the fix is, and how many of those digits mean
/// anything. Everything else is one tap away.
struct PositionView: View {
    @EnvironmentObject private var location: LocationService
    @State private var digits = 8

    private var parts: MGRS.Parts? {
        guard let f = location.fix else { return nil }
        return MGRS.parts(lat: f.lat, lon: f.lon, digits: digits)
    }

    var body: some View {
        ZStack {
            Blackout.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                header
                grid
                Spacer(minLength: 0)
                precisionPicker
                footer
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .foregroundStyle(Blackout.ink)
        .onAppear { location.start() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionLabel(text: "Position")
            Spacer()
            if let f = location.fix {
                Text(f.gradeWord)
                    .font(Blackout.label(11))
                    .tracking(1.4)
                    .foregroundStyle(f.grade >= 4 ? Blackout.good : f.grade >= 2 ? Blackout.accent : Blackout.warn)
            } else {
                Text("ACQUIRING")
                    .font(Blackout.label(11))
                    .tracking(1.4)
                    .foregroundStyle(Blackout.inkDim)
            }
        }
    }

    @ViewBuilder
    private var grid: some View {
        if location.reducedAccuracy {
            reducedAccuracyNotice
        } else if let p = parts {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.gzd + " " + p.square)
                    .font(Blackout.numerals(30, weight: .semibold))
                    .foregroundStyle(Blackout.inkDim)
                Text(p.easting)
                    .font(Blackout.numerals(62, weight: .bold))
                    .foregroundStyle(Blackout.ink)
                Text(p.northing)
                    .font(Blackout.numerals(62, weight: .bold))
                    .foregroundStyle(Blackout.ink)
                Text(Phonetic.mgrs(p.full))
                    .font(Blackout.label(12, weight: .medium))
                    .foregroundStyle(Blackout.inkDim)
                    .padding(.top, 8)
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        } else {
            Text("— — — — —")
                .font(Blackout.numerals(62, weight: .bold))
                .foregroundStyle(Blackout.inkDim)
        }
    }

    private var reducedAccuracyNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRECISE LOCATION OFF")
                .font(Blackout.label(15))
                .tracking(1.2)
                .foregroundStyle(Blackout.warn)
            Text("iOS is giving this app a position accurate to kilometres, "
                 + "which is not a grid. Turn on Precise Location for MGRS GPS "
                 + "in Settings before you use anything on this screen.")
                .font(Blackout.label(13, weight: .regular))
                .foregroundStyle(Blackout.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var precisionPicker: some View {
        HStack(spacing: 0) {
            ForEach([4, 6, 8, 10], id: \.self) { d in
                let trusted = location.fix.map { d <= $0.trustedDigits } ?? true
                Button {
                    digits = d
                } label: {
                    Text("\(d)")
                        .font(Blackout.numerals(15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(
                            digits == d ? Blackout.background
                                : trusted ? Blackout.ink : Blackout.inkDim
                        )
                        .background(digits == d ? Blackout.accent : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Blackout.hairline))
    }

    @ViewBuilder
    private var footer: some View {
        if let f = location.fix {
            VStack(alignment: .leading, spacing: 6) {
                row("ACCURACY", Format.accuracy(meters: f.accuracyMeters, unit: .metric))
                if digits > f.trustedDigits {
                    row("TRUST", "\(f.trustedDigits)-digit at this accuracy", tint: Blackout.warn)
                }
                if let alt = f.altitudeMeters {
                    row("ALTITUDE", Format.altitude(meters: alt, unit: .metric))
                }
                row("UTM", Format.utm(UTM.coordinate(lat: f.lat, lon: f.lon)))
                row("LAT/LON", Format.latLon(lat: f.lat, lon: f.lon, format: .degreesMinutes))
                row("DTG", Format.dtg(f.timestamp))
            }
        }
    }

    private func row(_ label: String, _ value: String, tint: Color = Blackout.ink) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Blackout.label(10))
                .tracking(1.2)
                .foregroundStyle(Blackout.inkDim)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(Blackout.numerals(13))
                .foregroundStyle(tint)
            Spacer()
        }
    }
}
