import SwiftUI

/// "Blackout" — the same design language the Android app ships.
///
/// Pure black, not a dark grey: an OLED panel leaves black pixels off, which
/// is both battery and light discipline. One amber accent, one lume green for
/// good status, and a red-on-black night mode that preserves dark adaptation.
enum Blackout {
    static let background = Color.black
    static let ink = Color(red: 0.961, green: 0.961, blue: 0.941)      // #F5F5F0 bone
    static let inkDim = Color(red: 0.55, green: 0.55, blue: 0.53)
    static let accent = Color(red: 1.0, green: 0.698, blue: 0.0)       // #FFB300 amber
    static let good = Color(red: 0.749, green: 1.0, blue: 0.478)       // #BFFF7A lume
    static let warn = Color(red: 1.0, green: 0.42, blue: 0.21)
    static let night = Color(red: 0.85, green: 0.11, blue: 0.09)
    static let hairline = Color(white: 0.16)

    /// Every number on every screen is monospaced. A grid whose digits shift
    /// width as they change is a grid you misread at a glance.
    static func numerals(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// A section label: small, wide-tracked, amber. Matches the Android headers.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Blackout.label(11))
            .tracking(1.6)
            .foregroundStyle(Blackout.accent)
    }
}
