import AppKit
import SwiftUI

/// Owns the menu-bar status item and the launch-time discoverability
/// orchestration. Attached via `@NSApplicationDelegateAdaptor` in
/// `QuotaMonitorApp`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = AppEnvironment.shared
        let loc = LocalizationStore.shared
        let settings = SettingsStore.shared

        let controller = StatusItemController(
            env: env, localization: loc, settings: settings)
        controller.onScreenChange = { [weak self] in
            self?.enforceClipFallback()
        }
        self.statusItemController = controller

        // Launch fan-out previously carried by the MenuBarExtra `.task`.
        env.refreshAll(throttle: false, trigger: "launch")
        env.refreshDashboard()
        env.refreshMenuBar(trigger: "launch")
        env.startBackgroundPolling()

        // Onboarding window on launch (previously MenuBarLabelView.task).
        if loc.needsOnboarding || settings.needsProviderOnboarding {
            WindowRouter.shared.request("onboarding")
            // A brand-new user is mid-wizard; defer the discoverability
            // check until they finish (see notification observer below).
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onboardingCompleted),
                name: .quotaMonitorOnboardingCompleted,
                object: nil)
        } else {
            scheduleDiscoverabilityCheck()
        }
    }

    @objc private func onboardingCompleted() {
        NotificationCenter.default.removeObserver(
            self, name: .quotaMonitorOnboardingCompleted, object: nil)
        scheduleDiscoverabilityCheck()
    }

    /// Give the status item a beat to lay out before we read its frame.
    private func scheduleDiscoverabilityCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.runDiscoverabilityCheck()
        }
    }

    /// One-time first-run presentation + per-launch clip fallback.
    private func runDiscoverabilityCheck() {
        guard let controller = statusItemController else { return }
        let visibility = controller.currentVisibility()

        // Per-launch: clipped → permanent Dock icon + mark unreachable so
        // closing the last window can't drop the only visible entry.
        applyUnreachableState(clipped: visibility == .clipped)

        // One-time presentation.
        let action = MenuBarPresentation.decide(
            visibility: visibility,
            hasShownFirstRun: SettingsStore.shared.hasShownFirstRunPresentation)
        switch action {
        case .showPopover:
            controller.showPopover()
        case .openFallbackWindow:
            AppEnvironment.shared.activateForWindow()
            WindowRouter.shared.request("dashboard")
            AppEnvironment.shared.refreshDashboard()
        case .none:
            break
        }
        if action != .none {
            SettingsStore.shared.hasShownFirstRunPresentation = true
        }
    }

    /// Per-launch / on-screen-change enforcement of the Dock fallback,
    /// without the one-time presentation.
    private func enforceClipFallback() {
        guard let controller = statusItemController else { return }
        applyUnreachableState(clipped: controller.currentVisibility() == .clipped)
    }

    private func applyUnreachableState(clipped: Bool) {
        let env = AppEnvironment.shared
        env.menuBarUnreachable = clipped
        if clipped {
            NSApp.setActivationPolicy(.regular)
        }
        // When reachable we leave the activation policy to the existing
        // Dock-icon-for-windows logic; we never force `.accessory` here
        // (a window may legitimately be holding `.regular`).
    }
}
