import SwiftUI

/// Issued-compass and clean-card instruments for the Position screen.
///
/// Not a pixel clone of the Android Compose faces: the same reading — a dial,
/// a grid on the glass, heading, accuracy — drawn so night mode is red ink.
struct CompassInstrument: View {
    enum Style {
        case lensatic
        case dial
    }

    let style: Style
    /// Degrees in the selected north reference, or nil when the compass has
    /// not reported. A nil heading must not paint as 000.
    let heading: Double?
    let northLetter: String
    let palette: FieldPalette
    let gzdSquare: String
    let easting: String
    let northing: String
    let statusLine: String
    let headingLine: String

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    Canvas { context, size in
                        draw(context: &context, size: size)
                    }
                    .opacity(heading == nil ? 0.42 : 1)
                    centerReadout
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(headingLine)
                .font(Blackout.numerals(13))
                .foregroundStyle(heading == nil ? palette.inkDim : palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var centerReadout: some View {
        VStack(spacing: 0) {
            Text(gzdSquare)
                .font(Blackout.numerals(style == .lensatic ? 12 : 14, weight: .medium))
                .tracking(2)
                .foregroundStyle(palette.inkDim)
            Text(easting)
                .font(Blackout.numerals(style == .lensatic ? 28 : 34, weight: .bold))
                .foregroundStyle(palette.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(northing)
                .font(Blackout.numerals(style == .lensatic ? 28 : 34, weight: .bold))
                .foregroundStyle(palette.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(statusLine)
                .font(Blackout.label(10))
                .tracking(1.1)
                .foregroundStyle(palette.inkDim)
                .padding(.top, 4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 36)
        .allowsHitTesting(false)
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = min(size.width, size.height) / 2
        switch style {
        case .lensatic:
            drawLensatic(context: &context, c: c, r: r)
        case .dial:
            drawDial(context: &context, c: c, r: r)
        }
    }

    private func drawLensatic(context: inout GraphicsContext, c: CGPoint, r: CGFloat) {
        let night = palette.night
        let caseColor = night ? Color(red: 0.16, green: 0.04, blue: 0.02) : Color(red: 0.29, green: 0.33, blue: 0.20)
        let bezel = night ? Color(red: 0.05, green: 0.01, blue: 0.01) : Color(red: 0.11, green: 0.11, blue: 0.11)
        let tick = night ? Color(red: 0.43, green: 0.09, blue: 0.06) : Color(red: 0.56, green: 0.58, blue: 0.54)
        let face = Color.black
        let mils = night ? Color(red: 0.48, green: 0.10, blue: 0.07) : Color(red: 0.85, green: 0.83, blue: 0.78)
        let deg = night ? Color(red: 0.56, green: 0.11, blue: 0.08) : Color(red: 0.91, green: 0.27, blue: 0.18)
        let s = r / 180

        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(caseColor))
        context.fill(Path(ellipseIn: CGRect(x: c.x - (r - 8 * s), y: c.y - (r - 8 * s), width: (r - 8 * s) * 2, height: (r - 8 * s) * 2)), with: .color(bezel))

        for i in 0..<120 {
            let long = i % 10 == 0
            strokeTick(context: &context, c: c, bearing: Double(i) * 3, from: r - 22 * s, to: r - 11 * s,
                       color: tick, width: (long ? 1.4 : 0.8) * s)
        }

        let big = r - 26 * s
        context.fill(Path(ellipseIn: CGRect(x: c.x - big, y: c.y - big, width: big * 2, height: big * 2)), with: .color(face))
        context.stroke(Path(ellipseIn: CGRect(x: c.x - big, y: c.y - big, width: big * 2, height: big * 2)),
                       with: .color(palette.hairline), lineWidth: s)

        // Card rotates so the heading sits under the fixed index. No heading:
        // leave the card north-up and dimmed — do not pretend the index reads 000.
        var card = context
        if let h = heading {
            card.translateBy(x: c.x, y: c.y)
            card.rotate(by: .degrees(-h))
            card.translateBy(x: -c.x, y: -c.y)
        }

        for k in 0..<320 {
            let milsVal = k * 20
            let long = milsVal % 100 == 0
            let bearing = Double(milsVal) * 360.0 / 6400.0
            strokeTick(context: &card, c: c, bearing: bearing, from: big - (long ? 9 : 5) * s, to: big - s,
                       color: mils, width: (long ? 1.1 : 0.6) * s)
        }
        for d in stride(from: 0, to: 360, by: 5) {
            let long = d % 10 == 0
            strokeTick(context: &card, c: c, bearing: Double(d), from: big - 23 * s, to: big - (long ? 30 : 27) * s,
                       color: deg, width: (long ? 1 : 0.7) * s)
        }

        // Luminous north arrow on the card.
        var arrow = Path()
        arrow.move(to: CGPoint(x: c.x, y: c.y - (big - 32 * s)))
        arrow.addLine(to: CGPoint(x: c.x - 7.5 * s, y: c.y - (big - 54 * s)))
        arrow.addLine(to: CGPoint(x: c.x + 7.5 * s, y: c.y - (big - 54 * s)))
        arrow.closeSubpath()
        card.fill(arrow, with: .color(palette.lume))
        let stem = CGRect(x: c.x - 2.5 * s, y: c.y - (big - 54 * s), width: 5 * s, height: 20 * s)
        card.fill(Path(stem), with: .color(palette.lume))

        drawRadialLabel(context: &card, c: c, text: "E", bearing: 90, radius: big - 52 * s, size: 15 * s, color: palette.lume)
        drawRadialLabel(context: &card, c: c, text: "S", bearing: 180, radius: big - 52 * s, size: 15 * s, color: palette.ink)
        drawRadialLabel(context: &card, c: c, text: "W", bearing: 270, radius: big - 52 * s, size: 15 * s, color: palette.lume)
        for d in stride(from: 20, to: 360, by: 20) {
            drawRadialLabel(context: &card, c: c, text: "\(d)", bearing: Double(d), radius: big - 40 * s,
                            size: 9 * s, color: deg)
        }

        // Fixed index on the crystal — the sighting wire.
        var index = Path()
        index.move(to: CGPoint(x: c.x, y: c.y - r + 9 * s))
        index.addLine(to: CGPoint(x: c.x, y: c.y - r + 58 * s))
        context.stroke(index, with: .color(palette.ink), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
    }

    private func drawDial(context: inout GraphicsContext, c: CGPoint, r: CGFloat) {
        let s = r / 165
        let ring = palette.night ? palette.hairline : Color(red: 0.23, green: 0.23, blue: 0.20)
        var bezel = Path(ellipseIn: CGRect(x: c.x - (r - 2 * s), y: c.y - (r - 2 * s), width: (r - 2 * s) * 2, height: (r - 2 * s) * 2))
        context.stroke(bezel, with: .color(ring), lineWidth: 1.5 * s)

        // Card stays north-up. The mark rides the ring at the heading.
        for d in stride(from: 0, to: 360, by: 10) {
            let big = d % 30 == 0
            strokeTick(context: &context, c: c, bearing: Double(d),
                       from: r - (big ? 16 : 9) * s, to: r - 3 * s,
                       color: big ? palette.ink : palette.inkDim, width: (big ? 2 : 1) * s)
        }
        drawUprightLabel(context: &context, c: c, text: "N", bearing: 0, radius: r - 36 * s, size: 16 * s, color: palette.lume)
        drawUprightLabel(context: &context, c: c, text: "E", bearing: 90, radius: r - 36 * s, size: 16 * s, color: palette.ink)
        drawUprightLabel(context: &context, c: c, text: "S", bearing: 180, radius: r - 36 * s, size: 16 * s, color: palette.ink)
        drawUprightLabel(context: &context, c: c, text: "W", bearing: 270, radius: r - 36 * s, size: 16 * s, color: palette.ink)

        if let h = heading {
            let pos = polar(c, r - 22 * s, h)
            var mark = context
            mark.translateBy(x: pos.x, y: pos.y)
            mark.rotate(by: .degrees(h))
            var tri = Path()
            tri.move(to: CGPoint(x: 0, y: -9 * s))
            tri.addLine(to: CGPoint(x: 6 * s, y: 3 * s))
            tri.addLine(to: CGPoint(x: -6 * s, y: 3 * s))
            tri.closeSubpath()
            mark.fill(tri, with: .color(palette.lume))
        }

        _ = northLetter
    }

    private func strokeTick(context: inout GraphicsContext, c: CGPoint, bearing: Double,
                             from: CGFloat, to: CGFloat, color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: polar(c, from, bearing))
        path.addLine(to: polar(c, to, bearing))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
    }

    private func drawRadialLabel(context: inout GraphicsContext, c: CGPoint, text: String,
                                 bearing: Double, radius: CGFloat, size: CGFloat, color: Color) {
        let pos = polar(c, radius, bearing)
        var local = context
        local.translateBy(x: pos.x, y: pos.y)
        local.rotate(by: .degrees(bearing))
        local.draw(Text(text).font(.system(size: max(8, size), weight: .semibold, design: .default)).foregroundColor(color),
                    at: .zero, anchor: .center)
    }

    private func drawUprightLabel(context: inout GraphicsContext, c: CGPoint, text: String,
                                  bearing: Double, radius: CGFloat, size: CGFloat, color: Color) {
        let pos = polar(c, radius, bearing)
        context.draw(Text(text).font(.system(size: max(8, size), weight: .semibold)).foregroundColor(color),
                      at: pos, anchor: .center)
    }

    /// Bearing 0 is north, clockwise. Screen y grows downward.
    private func polar(_ c: CGPoint, _ radius: CGFloat, _ bearingDeg: Double) -> CGPoint {
        let a = (bearingDeg - 90) * .pi / 180
        return CGPoint(x: c.x + radius * CGFloat(cos(a)), y: c.y + radius * CGFloat(sin(a)))
    }
}
