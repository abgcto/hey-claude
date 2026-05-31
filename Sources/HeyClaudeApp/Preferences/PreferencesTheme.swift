import SwiftUI

/// Shared design tokens for the Settings dashboard — the same pure-black + ink
/// palette and General Sans typography the onboarding flow uses, in one place so
/// the section views (Voice / Launch / Appearance / General) stay consistent and
/// small. Mirrors the constants previously inlined in `OnboardingView` /
/// `PreferencesView`.
enum PreferencesTheme {
    static let ink = Color(red: 0.953, green: 0.949, blue: 0.937)       // #f3f2ef
    static let inkSoft = Color(red: 0.612, green: 0.596, blue: 0.561)
    static let inkFaint = Color(red: 0.48, green: 0.47, blue: 0.445)    // 4.8:1 on black
    static let hairStrong = Color(red: 0.216, green: 0.216, blue: 0.239)

    /// Consistent vertical spacing, used by every section so the rhythm matches
    /// across tabs. `group` = between labelled groups; `row` = label → its content
    /// and between stacked elements in a group; `list` = within a multi-row control.
    static let groupSpacing: CGFloat = 28
    static let rowSpacing: CGFloat = 12
    static let listSpacing: CGFloat = 8

    /// Strict type scale — three roles, one purpose each, so panes don't sprout
    /// ad-hoc sizes. Pair with the colour rule below.
    ///   • label   → `SectionLabel` (tracked caps, `inkFaint`)
    ///   • body    → primary text: list items, names, the toggle/button label (`ink`)
    ///   • caption → secondary text: explanatory lines, slider bounds (`inkSoft`)
    static var body: Font { gs(13) }
    static var bodyMedium: Font { gs(13, .medium) }
    static var caption: Font { gs(12) }

    /// General Sans with system fallback (the OTF weights ship as separate
    /// families, so pick by family name rather than `.weight()`).
    static func gs(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let family: String
        switch weight {
        case .semibold, .bold: family = "General Sans Semibold"
        case .medium:          family = "General Sans Medium"
        default:               family = "General Sans"
        }
        return .custom(family, size: size)
    }
}

/// An all-caps tracked section eyebrow (e.g. "WAKE SENSITIVITY").
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(PreferencesTheme.gs(10, .medium))
            .tracking(1.6)
            .foregroundStyle(PreferencesTheme.inkFaint)
    }
}

/// A labelled settings group — an eyebrow label over its content, with one
/// consistent internal gap (`rowSpacing`). Sections stack these `groupSpacing`
/// apart, so every tab shares the same vertical rhythm.
struct SettingsGroup<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.rowSpacing) {
            SectionLabel(label)
            content()
        }
    }
}

extension PreferencesTheme {
    /// Hover tint for list/nav surfaces. The mockup's 3% (`rgba(243,242,239,.03)`)
    /// sat on a near-black *panel*; on this dashboard's true-black canvas 3% is
    /// invisible, so it's lifted to 6% — clearly visible while still below the 10%
    /// selected fill, preserving the hover < selected hierarchy.
    static let hoverFill = ink.opacity(0.06)
    /// Shared hover transition: a gentle 0.15s ease, matching the mockups' `.15s`.
    static let hoverDuration: Double = 0.15
    /// Hover lift, matching the mockup card's `transform: translateY(-2px)` — the
    /// control "slips up" on hover rather than only tinting.
    static let hoverLift: CGFloat = -2
}

/// The dashboard's hover affordance for rows, rail tabs and cells: the control
/// slips up `hoverLift` points and takes a faint `hoverFill` tint — mirroring the
/// mockup's `.card:hover { transform: translateY(-2px) }` plus row fill. The lift
/// uses `.offset` (a render transform, not a layout change) so neighbors in a grid
/// or stack never reflow. Honors Reduce Motion by dropping the animation (the end
/// state still applies, just without the fade/slide). The host supplies its own
/// `cornerRadius` so the highlight matches the control's shape.
private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let enabled: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { hovering && enabled }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(active ? PreferencesTheme.hoverFill : .clear))
            .offset(y: active ? PreferencesTheme.hoverLift : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: PreferencesTheme.hoverDuration),
                       value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Adds the dashboard's hover affordance (slip-up lift + ink fill) to a control.
    /// Place it so the fill sits *under* any selected-state background/stroke.
    /// Pass `enabled: false` for an already-selected control so hover doesn't stack
    /// a third tint on top of the selected fill.
    func dashboardHover(cornerRadius: CGFloat, enabled: Bool = true) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, enabled: enabled))
    }
}

/// The ink-filled pill button used across the dashboard (mirrors onboarding's
/// `actionButton`): black label on `ink`, hugs its text. On hover it slips up
/// `hoverLift` (like the other dashboard controls) and brightens slightly toward
/// white — a fill tint would be invisible on the already-filled `ink` pill, so the
/// brightness lift is its equivalent of the row/cell fill.
struct DashboardButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PreferencesTheme.gs(13, .medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(PreferencesTheme.ink)
                        .brightness(hovering ? 0.06 : 0))
        }
        .buttonStyle(.plain)
        .offset(y: hovering ? PreferencesTheme.hoverLift : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: PreferencesTheme.hoverDuration),
                   value: hovering)
        .onHover { hovering = $0 }
    }
}
