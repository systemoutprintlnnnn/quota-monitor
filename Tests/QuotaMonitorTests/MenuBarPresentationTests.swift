import Foundation
import Testing
@testable import QuotaMonitor

/// The one-time first-run presentation decision. The Dock-icon /
/// `menuBarUnreachable` side effect is NOT encoded here — it follows
/// directly from `visibility == .clipped` and is applied every launch by
/// the caller. This enum only governs the one-time popover/window action.
@Suite("Menu-bar first-run presentation decision")
struct MenuBarPresentationTests {

    @Test
    func visibleAndUnshownShowsPopover() {
        #expect(MenuBarPresentation.decide(
            visibility: .visible, hasShownFirstRun: false) == .showPopover)
    }

    @Test
    func clippedAndUnshownOpensFallbackWindow() {
        #expect(MenuBarPresentation.decide(
            visibility: .clipped, hasShownFirstRun: false) == .openFallbackWindow)
    }

    @Test
    func alreadyShownVisibleIsNone() {
        #expect(MenuBarPresentation.decide(
            visibility: .visible, hasShownFirstRun: true) == .none)
    }

    @Test
    func alreadyShownClippedIsNone() {
        // Already-shown means no *one-time* action; the per-launch Dock
        // fallback (driven by .clipped separately) still runs.
        #expect(MenuBarPresentation.decide(
            visibility: .clipped, hasShownFirstRun: true) == .none)
    }
}
