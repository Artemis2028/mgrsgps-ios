import SwiftUI

/// Custom blackout bottom nav — replaces system `TabView` chrome so the bar
/// matches Android GridFix: pure black, amber selected, dim unselected, labels
/// under icons. Always visible (including on Map), like Android portrait.
///
/// RootView hosts this via `safeAreaInset(edge: .bottom)`, which keeps the
/// control row above the home indicator. The black background still paints
/// into the unsafe area with `ignoresSafeArea(edges: .bottom)`.
struct FieldTabBar: View {
    @Binding var selection: Int
    @EnvironmentObject private var settings: AppSettings

    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }

    private struct Item: Identifiable {
        let id: Int
        let title: String
        let systemImage: String
    }

    private let items: [Item] = [
        Item(id: 0, title: "Position", systemImage: "location.north.line"),
        Item(id: 1, title: "Navigate", systemImage: "safari"),
        Item(id: 2, title: "Map", systemImage: "map"),
        Item(id: 3, title: "Waypoints", systemImage: "flag"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(items) { item in
                    tabButton(item)
                }
            }
            // ~52pt control row — clear of the home indicator because
            // safeAreaInset already reserves that space under this view.
            .frame(minHeight: 52)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(palette.background.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private func tabButton(_ item: Item) -> some View {
        let selected = selection == item.id
        Button {
            selection = item.id
        } label: {
            VStack(spacing: 5) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 20, weight: selected ? .semibold : .regular))
                Text(item.title)
                    .font(Blackout.label(10, weight: selected ? .semibold : .medium))
                // Small amber underline for selected — not iOS translucent chrome.
                Capsule()
                    .fill(selected ? palette.accent : Color.clear)
                    .frame(width: 18, height: 2)
                    .padding(.top, 1)
            }
            .foregroundStyle(selected ? palette.accent : palette.inkDim)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
