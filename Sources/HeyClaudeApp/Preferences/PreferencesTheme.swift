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
    /// Faint row divider — the hairline drawn under each `SettingsRow` (mockup's
    /// `rgba(243,242,239,.09)`). Lighter than `hairStrong` (control borders) so the
    /// in-group dividers read as a quiet rhythm, not boxes.
    static let hairline = ink.opacity(0.09)
    /// The single accent — coral, used only to flag an un-granted permission
    /// (matches the notch's attention coral). Everything else stays monochrome.
    static let coral = Color(red: 1.0, green: 0.541, blue: 0.420)   // #ff8a6b

    /// Vertical spacing tokens. `list` = gap within a multi-row control (the target
    /// list, the swatch row); `section` = gap between header-led groups, so each
    /// titled block reads as its own region — the mockup's 38px inter-group margin.
    static let listSpacing: CGFloat = 8
    static let sectionGap: CGFloat = 38

    /// The Settings window's fixed content size — the single source of truth shared
    /// by PreferencesView, PreferencesWindowController, and the retrain window's
    /// fallback, so the "retrain matches Settings" contract can't silently drift.
    static let windowSize = CGSize(width: 820, height: 580)

    /// Type roles (pair with the colour rule):
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

/// A redesigned section header: a 16pt title with an optional one-line gray
/// subtitle beneath — the primary grouping device, bigger and sentence-case with
/// clear air below.
struct SettingsHeader: View {
    let title: String
    let subtitle: String?
    init(_ title: String, _ subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(PreferencesTheme.gs(16, .semibold)).tracking(-0.25)
                .foregroundStyle(PreferencesTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(PreferencesTheme.gs(12))
                    .foregroundStyle(PreferencesTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 6)   // air under the header before the first row (mockup)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One settings line in the redesigned layout: title (+ optional wrapping
/// description) on the left, a trailing control on the right, and a hairline
/// divider beneath. Pass `showsDivider: false` on a group's final row so the
/// rhythm stops at the group edge (mockup's `.row:last-child` rule).
struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    let showsDivider: Bool
    /// When true the description is forced to a single line with middle truncation
    /// (used for the working-folder path); otherwise it wraps to fit.
    let truncatesDescription: Bool
    @ViewBuilder var control: () -> Control
    init(_ title: String, _ description: String? = nil,
         showsDivider: Bool = true, truncatesDescription: Bool = false,
         @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.description = description
        self.showsDivider = showsDivider
        self.truncatesDescription = truncatesDescription
        self.control = control
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    // 14pt/regular title over a 12pt/regular gray description. The
                    // title stays lighter than the 16pt Semibold group header so the
                    // header clearly leads; ink vs gray color separates title from
                    // description.
                    Text(title)
                        .font(PreferencesTheme.gs(14)).tracking(-0.1)
                        .foregroundStyle(PreferencesTheme.ink)
                    if let description {
                        if truncatesDescription {
                            Text(description)
                                .font(PreferencesTheme.gs(12))
                                .foregroundStyle(PreferencesTheme.inkSoft)
                                .lineLimit(1).truncationMode(.middle)
                        } else {
                            Text(description)
                                .font(PreferencesTheme.gs(12))
                                .foregroundStyle(PreferencesTheme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 16)
                // Keep the control at its intrinsic width so a long description can
                // never squeeze it (which made badges/buttons wrap to two lines).
                control()
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 17)   // mockup `.row` padding
            if showsDivider {
                Rectangle().fill(PreferencesTheme.hairline).frame(height: 1)
            }
        }
    }
}

/// A header-led group: a `SettingsHeader` over its rows in a tight VStack — the
/// standard section block used by every tab, replacing the repeated
/// `VStack(spacing: 0) { SettingsHeader(…); rows }`.
struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content
    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }
    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title, subtitle)
            content()
        }
    }
}

/// A permission status pill: `ink` "GRANTED" when allowed, `coral` "NEEDS ACCESS"
/// when not — the only place the dashboard spends its accent color.
struct PermissionBadge: View {
    let granted: Bool
    var body: some View {
        Text(granted ? "Granted" : "Needs access")
            .font(PreferencesTheme.gs(11, .semibold)).tracking(0.6)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(.black)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(granted ? PreferencesTheme.ink : PreferencesTheme.coral))
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
    let lift: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { hovering && enabled }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(active ? PreferencesTheme.hoverFill : .clear))
            .offset(y: (lift && active) ? PreferencesTheme.hoverLift : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: PreferencesTheme.hoverDuration),
                       value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Adds the dashboard's hover affordance (slip-up lift + ink fill) to a control.
    /// Place it so the fill sits *under* any selected-state background/stroke.
    /// Pass `enabled: false` for an already-selected control so hover doesn't stack
    /// a third tint on top of the selected fill. Pass `lift: false` for a flat hover
    /// (fill only, no slip-up) — used by the nav rail, where lifting a full-width
    /// list item reads as wobble rather than the card "pop" the grid cells want.
    func dashboardHover(cornerRadius: CGFloat, enabled: Bool = true, lift: Bool = true) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, enabled: enabled, lift: lift))
    }
}

/// The dashboard's monochrome switch — replaces the stock macOS `Toggle`, whose
/// system-blue track ignores `.tint` and clashes with this black+ink pane. Off:
/// a dim `hairStrong` track with a light knob; on: an `ink` track with a black
/// knob. Compact (34×20) to sit with the 13pt type rather than tower over it.
struct DashboardToggle: View {
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? PreferencesTheme.ink : PreferencesTheme.hairStrong)
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(isOn ? .black : PreferencesTheme.ink)
                    .frame(width: 14, height: 14)
                    .padding(3)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isOn)
        // Switch semantics for VoiceOver (the visual label is a sibling `Text`,
        // merged in by the call site's `.accessibilityElement(children: .combine)`).
        // `.isToggle` makes VO read the on/off value + announce it as a switch.
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The ink-filled pill button used across the dashboard (mirrors onboarding's
/// `actionButton`): black label on `ink`, hugs its text. On hover it slips up
/// `hoverLift` (like the other dashboard controls) and brightens slightly toward
/// white — a fill tint would be invisible on the already-filled `ink` pill, so the
/// brightness lift is its equivalent of the row/cell fill.
struct DashboardButton: View {
    /// `primary` = the ink-filled pill (a section's main action). `secondary` =
    /// a bordered, transparent button (incidental actions like Choose / Re-train /
    /// Open Settings) — quieter, so one ink pill per pane stays the clear lead.
    enum Style { case primary, secondary }

    let title: String
    let style: Style
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ title: String, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PreferencesTheme.gs(12, .medium))
                .lineLimit(1)
                .foregroundStyle(style == .primary ? .black : PreferencesTheme.ink)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(background)
        }
        .buttonStyle(.plain)
        .offset(y: hovering ? PreferencesTheme.hoverLift : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: PreferencesTheme.hoverDuration),
                   value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: 9)
                .fill(PreferencesTheme.ink)
                .brightness(hovering ? 0.06 : 0)
        case .secondary:
            RoundedRectangle(cornerRadius: 9)
                .fill(hovering ? PreferencesTheme.hoverFill : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(PreferencesTheme.hairStrong, lineWidth: 1))
        }
    }
}
