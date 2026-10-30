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

/// Red-on-black when night is on. Day colours stay the blackout set.
struct FieldPalette {
    var night: Bool

    var background: Color { .black }
    var ink: Color { night ? Color(red: 1.0, green: 0.23, blue: 0.19) : Blackout.ink }
    // Secondary labels stay red, with readable contrast on the opaque night surfaces.
    var inkDim: Color { night ? Color(red: 0.90, green: 0.22, blue: 0.18) : Blackout.inkDim }
    var accent: Color { night ? Color(red: 1.0, green: 0.23, blue: 0.19) : Blackout.accent }
    var good: Color { night ? Color(red: 1.0, green: 0.35, blue: 0.24) : Blackout.good }
    var warn: Color { night ? Color(red: 1.0, green: 0.32, blue: 0.20) : Blackout.warn }
    var hairline: Color { night ? Color(red: 0.32, green: 0.08, blue: 0.06) : Blackout.hairline }
    var lume: Color { night ? Color(red: 1.0, green: 0.28, blue: 0.20) : Blackout.good }
}

private struct FieldNightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var fieldNight: Bool {
        get { self[FieldNightKey.self] }
        set { self[FieldNightKey.self] = newValue }
    }
}

/// Glass is reserved for the control layer. Content remains opaque and legible.
struct FieldScreenBackground: View {
    @Environment(\.fieldNight) private var night
    var body: some View {
        LinearGradient(colors: night ? [.black] : [Color(red: 0.12, green: 0.15, blue: 0.19), .black],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

private struct FieldChrome: ViewModifier {
    @Environment(\.fieldNight) private var night
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if night || reduceTransparency {
            content.background(night ? Color.black : Color(red: 0.16, green: 0.18, blue: 0.22), in: shape)
                .overlay(shape.stroke(night ? FieldPalette(night: true).hairline : Color.white.opacity(0.18)))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

private struct OpaqueFieldButtonStyle: ButtonStyle {
    let night: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let palette = FieldPalette(night: night)
        configuration.label
            .foregroundStyle(palette.accent)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 12)
            .background(Color.black, in: Capsule())
            .overlay(Capsule().stroke(palette.hairline, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

private struct ReadableMapGlassStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .foregroundStyle(Blackout.ink)
            .frame(minWidth: 44,minHeight: 44)
            .padding(.horizontal,12)
            // Native glass can brighten independently over pale map tiles.
            // Keep a dark backing beneath the light symbol in either state.
            .background(.black.opacity(0.72),in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
        if #available(iOS 26.0, *) {
            label.glassEffect(.regular.tint(.black.opacity(0.35)).interactive(),in: Capsule())
        } else {
            label.overlay(Capsule().stroke(.white.opacity(0.18)))
        }
    }
}

private struct FieldGlassButton: ViewModifier {
    @Environment(\.fieldNight) private var night
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var mapControl: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if night || reduceTransparency {
            content.buttonStyle(OpaqueFieldButtonStyle(night: night))
        } else if mapControl {
            content.buttonStyle(ReadableMapGlassStyle())
        } else if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func fieldChrome(radius: CGFloat = 20) -> some View { modifier(FieldChrome(radius: radius)) }
    func fieldGlassButton(mapControl: Bool = false) -> some View { modifier(FieldGlassButton(mapControl: mapControl)) }

    func fieldContentSurface(night: Bool) -> some View {
        background(night ? Color.black : Color.white.opacity(0.045),
                   in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(night ? FieldPalette(night: true).hairline : Color.white.opacity(0.09)))
    }
}

/// A section label: small, wide-tracked, amber — red when night mode is on.
struct SectionLabel: View {
    let text: String
    @Environment(\.fieldNight) private var night

    var body: some View {
        Text(text.uppercased())
            .font(Blackout.label(11))
            .tracking(1.6)
            .foregroundStyle(night ? Color(red: 1.0, green: 0.23, blue: 0.19) : Blackout.accent)
    }
}

/// Hairline segmented control used by Settings and the precision picker.
struct BlackoutSegments: View {
    let options: [String]
    let selected: Int
    var palette: FieldPalette
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, title in
                Button {
                    onSelect(index)
                } label: {
                    Text(title)
                        .font(Blackout.numerals(13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(index == selected ? palette.background : palette.ink)
                        .background(index == selected ? palette.accent : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: palette.night ? 0.06 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.hairline))
    }
}

/// Field forms use light ink on dark content surfaces, even when presented
/// from the map's light chrome environment.
extension View {
    func fieldSheetAppearance() -> some View {
        self.environment(\.colorScheme,.dark).preferredColorScheme(.dark)
            .toolbarColorScheme(.dark,for: .navigationBar)
    }
}
