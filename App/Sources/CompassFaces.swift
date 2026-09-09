import SwiftUI

/// Full-bleed Position instruments. The dial is the screen, not a doodle
/// above the Glance block.
struct CompassInstrument: View {
    enum Style { case lensatic, dial }

    let style: Style
    let heading: Double?
    let northLetter: String
    let palette: FieldPalette
    let gzdSquare: String
    let easting: String
    let northing: String
    let statusLine: String

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height * 0.92)
            ZStack {
                if style == .lensatic {
                    Circle()
                        .fill(palette.night
                              ? Color(red: 0.14, green: 0.03, blue: 0.02)
                              : Color(red: 0.28, green: 0.32, blue: 0.18))
                        .frame(width: side, height: side)
                }
                dialCard(side: side)
                    .frame(width: side * 0.86, height: side * 0.86)
                indexMark
                    .frame(width: side, height: side)
                glassReadout
                    .frame(width: side * 0.46)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var glassReadout: some View {
        VStack(spacing: 2) {
            Text(headingText)
                .font(Blackout.numerals(style == .lensatic ? 28 : 34, weight: .bold))
                .foregroundStyle(palette.accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(northLetter)
                .font(Blackout.label(11))
                .tracking(1.4)
                .foregroundStyle(palette.inkDim)
            Text(gzdSquare)
                .font(Blackout.numerals(13, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(palette.inkDim)
                .padding(.top, 8)
            Text(easting)
                .font(Blackout.numerals(22, weight: .bold))
                .foregroundStyle(palette.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(northing)
                .font(Blackout.numerals(22, weight: .bold))
                .foregroundStyle(palette.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(statusLine)
                .font(Blackout.label(10))
                .tracking(1.0)
                .foregroundStyle(palette.good)
                .padding(.top, 6)
                .lineLimit(1)
        }
        .allowsHitTesting(false)
    }

    private var headingText: String {
        guard let h = heading else { return "— — —" }
        return String(format: "%03.0f°", h)
    }

    private var indexMark: some View {
        VStack {
            Triangle()
                .fill(palette.accent)
                .frame(width: 16, height: 12)
                .padding(.top, 6)
            Spacer()
        }
    }

    private func dialCard(side: CGFloat) -> some View {
        let rotation = heading.map { -Angle.degrees($0) } ?? .zero
        return ZStack {
            Circle()
                .fill(Color.black)
            Circle()
                .stroke(palette.night ? palette.accent.opacity(0.55) : Color(white: 0.35), lineWidth: 2)
            tickRing
            cardinals
        }
        .rotationEffect(rotation)
    }

    private var tickRing: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            for d in 0..<360 {
                let major = d % 30 == 0
                let mid = d % 10 == 0
                guard major || mid else { continue }
                let inner = r - (major ? 16 : 8)
                var line = Path()
                line.move(to: polar(c, r - 2, Double(d)))
                line.addLine(to: polar(c, inner, Double(d)))
                context.stroke(line, with: .color(major ? palette.ink : palette.inkDim),
                               style: StrokeStyle(lineWidth: major ? 2 : 1, lineCap: .butt))
            }
        }
    }

    private var cardinals: some View {
        ZStack {
            label("N", 0, palette.lume)
            label("E", 90, palette.ink)
            label("S", 180, palette.ink)
            label("W", 270, palette.ink)
        }
    }

    private func label(_ text: String, _ bearing: Double, _ color: Color) -> some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = min(geo.size.width, geo.size.height) / 2 - 28
            Text(text)
                .font(Blackout.numerals(18, weight: .bold))
                .foregroundStyle(color)
                .position(polar(c, r, bearing))
                .rotationEffect(.degrees(heading ?? 0))
        }
    }

    private func polar(_ c: CGPoint, _ radius: CGFloat, _ bearingDeg: Double) -> CGPoint {
        let a = (bearingDeg - 90) * .pi / 180
        return CGPoint(x: c.x + radius * CGFloat(cos(a)), y: c.y + radius * CGFloat(sin(a)))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
