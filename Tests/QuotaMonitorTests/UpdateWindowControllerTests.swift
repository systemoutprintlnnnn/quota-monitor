import AppKit
import Foundation
import Testing
@testable import QuotaMonitor

@MainActor
@Suite("Update window controller lifecycle")
struct UpdateWindowControllerTests {

    @Test
    func windowCloseRunsLifecycleCallback() {
        var didClose = false
        let controller = UpdateWindowController(
            state: UpdateWindowState(),
            onWindowClosed: { didClose = true })

        controller.windowWillClose(
            Notification(name: NSWindow.willCloseNotification))

        #expect(didClose == true)
    }

    @Test
    func previewLauncherParsesLaunchArguments() throws {
        let qaConfig = Data(#"{"isActive":true}"#.utf8).base64EncodedString()
        let config = try #require(UpdateWindowPreviewLauncher.configuration(arguments: [
            "QuotaMonitor",
            "--quotamonitor-qa-config-base64",
            qaConfig,
            "--quotamonitor-preview-update-window-html",
            "/tmp/notes.html",
            "--quotamonitor-preview-update-window-version",
            "0.2.31",
            "--quotamonitor-preview-current-version=0.2.30",
            "--quotamonitor-preview-locale",
            "zh-Hans"
        ]))

        #expect(config.htmlPath == "/tmp/notes.html")
        #expect(config.newVersion == "0.2.31")
        #expect(config.currentVersion == "0.2.30")
        #expect(config.locale == "zh-Hans")
    }

    @Test
    func previewLauncherIgnoresLaunchArgumentsOutsideLocalQA() {
        let config = UpdateWindowPreviewLauncher.configuration(arguments: [
            "QuotaMonitor",
            "--quotamonitor-preview-update-window-html",
            "/tmp/notes.html"
        ])

        #expect(config == nil)
    }
}
