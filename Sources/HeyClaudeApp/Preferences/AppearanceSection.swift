import SwiftUI
import HeyClaudeKit

/// Appearance tab: the mascot picker — the gallery of every catalog mascot, the
/// curated color palette, and the idle-motion toggle. Selection reads straight from
/// `controller.settings` and routes taps to the controller setters, which persist
/// and update the live notch island.
struct AppearanceSection: View {
    let controller: AppController

    /// The 8 curated body colors (design doc · "Color palette").
    private let palette: [(name: String, hex: String)] = [
        ("Clay", "#D87757"), ("Amber", "#E0A35E"), ("Sage", "#86A886"),
        ("Sky", "#79A6C4"), ("Lavender", "#9E8CC9"), ("Rose", "#C98AA6"),
        ("Slate", "#8E97A3"), ("Bone", "#EDEAE3"),
    ]

    private var selectedID: String { controller.settings.mascotID }
    private var selectedHex: String { controller.settings.mascotColorHex }
    private var bodyColor: Color { Color(hex: selectedHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.sectionGap) {
            VStack(spacing: 0) {
                SettingsHeader("Mascot", "The character that lives in your notch.")
                gallery.padding(.top, 14)
            }
            VStack(spacing: 0) {
                SettingsHeader("Color")
                swatchRow.padding(.top, 14)
            }
            VStack(spacing: 0) {
                SettingsHeader("Motion")
                SettingsRow("Playful animations",
                            "Subtle idle motion so the mascot feels alive in the notch. Off automatically when macOS Reduce Motion is on.",
                            showsDivider: false) {
                    DashboardToggle(isOn: Binding(
                        get: { controller.settings.mascotIdleAnimations },
                        set: { controller.setMascotIdleAnimations($0) }))
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One tappable square per catalog mascot; the live selection wears a ring.
    /// Left-aligned (no hero preview — the live notch island IS the preview).
    private var gallery: some View {
        let columns = [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: 12, alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(MascotCatalog.all) { m in mascotCell(m) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mascotCell(_ m: Mascot) -> some View {
        let selected = m.id == selectedID
        return Button { controller.setMascot(id: m.id) } label: {
            MascotView(mascot: m, bodyColor: bodyColor)
                .padding(9)
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? PreferencesTheme.ink.opacity(0.10) : .clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? PreferencesTheme.ink : PreferencesTheme.hairStrong,
                                lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        // Unselected cells get the hover lift + fill; the selected cell keeps its ring.
        .dashboardHover(cornerRadius: 12, enabled: !selected)
        .help(m.displayName)
        .accessibilityLabel(m.displayName)
    }

    /// The 8 curated swatches in one row.
    private var swatchRow: some View {
        HStack(spacing: PreferencesTheme.listSpacing) {
            ForEach(palette, id: \.hex) { swatch in
                SwatchButton(
                    swatch: swatch,
                    selected: swatch.hex.caseInsensitiveCompare(selectedHex) == .orderedSame,
                    action: { controller.setMascotColor(hex: swatch.hex) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One color swatch. Unlike rows/cells (which lift + take an ink fill on hover), a
/// swatch is already filled with a vivid color — an ink overlay would be
/// invisible — so it uses a subtle `scale(1.08)` instead (mockup `.sw:hover`).
private struct SwatchButton: View {
    let swatch: (name: String, hex: String)
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: swatch.hex))
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? PreferencesTheme.ink : .white.opacity(0.12),
                                lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: PreferencesTheme.hoverDuration),
                   value: hovering)
        .onHover { hovering = $0 }
        .help(swatch.name)
        .accessibilityLabel(swatch.name)
    }
}
