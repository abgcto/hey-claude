import CoreGraphics

/// Single source of truth for the island's horizontal footprint, shared by the
/// SwiftUI `IslandView` (which renders it) and `NotchIslandPanel` (which derives
/// the interactive hit-region from it). Keeping these here stops the two layers
/// from drifting apart — the hit-target must match the pixels exactly.
enum IslandGeometry {
    /// One notch-row side zone (mascot left of the camera, content right).
    static let sideArea: CGFloat = 26
    /// `NotchShape`'s flare inset — the band is widened by this on each outer side.
    static let bodyInset: CGFloat = 6

    /// Total band width = two side zones + the camera gap + the two flares.
    static func islandWidth(notchWidth: CGFloat) -> CGFloat {
        2 * sideArea + notchWidth + 2 * bodyInset
    }
}
