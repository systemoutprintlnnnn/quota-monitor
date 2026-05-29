import Foundation

/// The one-time, first-run-only presentation action. Pure + `Equatable`
/// so the decision table is unit-tested independently of AppKit.
///
/// The Dock-icon / `menuBarUnreachable` side effect is deliberately NOT
/// represented here: it is a *per-launch* consequence of
/// `visibility == .clipped`, applied by the caller on every launch,
/// whereas this decision is gated by `hasShownFirstRun` and fires once.
enum MenuBarPresentation: Equatable {
    /// Icon is visible and we have not presented before — open the
    /// popover so its anchor arrow points at the icon.
    case showPopover
    /// Icon is clipped and we have not presented before — open the
    /// Dashboard window (the per-launch Dock fallback also engages).
    case openFallbackWindow
    /// Nothing to do this launch (already presented once).
    case none

    static func decide(visibility: StatusItemVisibility,
                       hasShownFirstRun: Bool) -> MenuBarPresentation {
        guard !hasShownFirstRun else { return .none }
        switch visibility {
        case .visible: return .showPopover
        case .clipped: return .openFallbackWindow
        }
    }
}
