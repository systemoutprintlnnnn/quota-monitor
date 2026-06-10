import Foundation
import Testing
@testable import QuotaMonitor

@MainActor
@Suite("Menu-bar recovery guide lifecycle actions")
struct MenuBarHelpLifecycleActionsTests {

    @Test
    func disappearingWindowDemotesToAccessory() {
        var didDemote = false
        let actions = MenuBarHelpLifecycleActions(
            demoteToAccessory: { didDemote = true })

        actions.windowDidDisappear()

        #expect(didDemote == true)
    }
}
