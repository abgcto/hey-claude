import SwiftUI
import HeyClaudeKit

/// The mascot-customization settings surface: a large live preview of the
/// selected mascot + color, a gallery of every catalog mascot, and the curated
/// color palette. Selection is read straight from `controller.settings` (the
/// `@Observable` controller invalidates `body` when a setter replaces the
/// `Settings` struct), so the UI always mirrors the live notch island — no local
/// `@State` mirror that could desync. Taps route to the controller setters,
/// which persist and update the island.
struct PreferencesView: View {
    let controller: AppController

    // Hover tracking (mirrors the mockup's lift/scale hover affordances).
    @State private var hoveredMascot: String?
    @State private var hoveredSwatch: String?

    // Pure-black, monochrome palette — mirrors OnboardingView (kept local; these
    // are `private` there, and a small duplication beats a shared refactor while
    // sibling files carry uncommitted work).
    private let ink = Color(red: 0.953, green: 0.949, blue: 0.937)      // #f3f2ef
    private let inkSoft = Color(red: 0.612, green: 0.596, blue: 0.561)
    private let inkFaint = Color(red: 0.48, green: 0.47, blue: 0.445)
    private let hairStrong = Color(red: 0.216, green: 0.216, blue: 0.239)

    /// The 8 curated body colors (design doc · "Color palette").
    private let palette: [(name: String, hex: String)] = [
        ("Clay", "#D87757"), ("Amber", "#E0A35E"), ("Sage", "#86A886"),
        ("Sky", "#79A6C4"), ("Lavender", "#9E8CC9"), ("Rose", "#C98AA6"),
        ("Slate", "#8E97A3"), ("Bone", "#EDEAE3"),
    ]

    /// General Sans with system fallback (the OTF weights ship as separate
    /// families, so pick by family name rather than `.weight()`).
    private func gs(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let family: String
        switch weight {
        case .semibold, .bold: family = "General Sans Semibold"
        case .medium:          family = "General Sans Medium"
        default:               family = "General Sans"
        }
        return .custom(family, size: size)
    }

    // Live selection, read from the controller every `body` pass.
    private var selectedID: String { controller.settings.mascotID }
    private var selectedHex: String { controller.settings.mascotColorHex }
    private var selectedMascot: Mascot { MascotCatalog.byID(selectedID) }
    private var bodyColor: Color { Color(hex: selectedHex) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                gallery
                    .padding(.top, 26)
                colorPalette
                    .padding(.top, 28)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 520, height: 430)
        .foregroundStyle(ink)
    }

    // MARK: - Sections

    private var eyebrow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("YOUR MASCOT").font(gs(10, .medium)).tracking(2).foregroundStyle(inkFaint)
            Text("Pick who lives in your notch").font(gs(20, .medium)).tracking(-0.3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One tappable square per catalog mascot; the live selection wears a ring.
    /// Compact fixed-size squares (mockup-style) that pack and wrap, centered.
    private var gallery: some View {
        let columns = Array(repeating: GridItem(.fixed(64), spacing: 12, alignment: .leading), count: 5)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(MascotCatalog.all) { m in
                mascotCell(m)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mascotCell(_ m: Mascot) -> some View {
        let selected = m.id == selectedID
        let hovered = hoveredMascot == m.id
        return Button { controller.setMascot(id: m.id) } label: {
            MascotView(mascot: m, bodyColor: bodyColor)
                .padding(9)
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? ink.opacity(0.08) : (hovered ? ink.opacity(0.04) : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? ink : (hovered ? ink.opacity(0.45) : hairStrong),
                                lineWidth: selected ? 2 : 1)
                )
                .offset(y: hovered ? -2 : 0)   // lift on hover (mockup parity)
        }
        .buttonStyle(.plain)
        .onHover { inside in hoveredMascot = inside ? m.id : (hoveredMascot == m.id ? nil : hoveredMascot) }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(m.displayName)
        .accessibilityLabel(m.displayName)
    }

    /// The 8 curated swatches; the live selection wears a ring. Centered to share
    /// the same axis as the (centered) eyebrow, preview, and mascot grid.
    private var colorPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COLOR").font(gs(10, .medium)).tracking(1.6).foregroundStyle(inkFaint)
            HStack(spacing: 12) {
                ForEach(palette, id: \.hex) { swatch in
                    swatchButton(swatch)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swatchButton(_ swatch: (name: String, hex: String)) -> some View {
        // Case-insensitive compare so a lowercased persisted value still rings.
        let selected = swatch.hex.caseInsensitiveCompare(selectedHex) == .orderedSame
        let hovered = hoveredSwatch == swatch.hex
        return Button { controller.setMascotColor(hex: swatch.hex) } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: swatch.hex))
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? ink : .white.opacity(0.12),
                                lineWidth: selected ? 2.5 : 1)
                )
                .scaleEffect(hovered ? 1.08 : 1)   // grow on hover (mockup parity)
        }
        .buttonStyle(.plain)
        .onHover { inside in hoveredSwatch = inside ? swatch.hex : (hoveredSwatch == swatch.hex ? nil : hoveredSwatch) }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(swatch.name)
        .accessibilityLabel(swatch.name)
    }
}
