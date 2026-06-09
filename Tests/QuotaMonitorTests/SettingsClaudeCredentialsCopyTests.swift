import Foundation
import Testing
@testable import QuotaMonitor

@Suite("Claude credentials settings copy", .serialized)
struct SettingsClaudeCredentialsCopyTests {
    @Test("Claude credential recovery copy explains the automatic mode")
    func credentialRecoveryCopyExplainsAutomaticMode() {
        LocalizationTestSupport.withLanguage(.english) {
            #expect(L10n.claudeCredentialFileOnlyWarning.localizedCaseInsensitiveContains("automatic credential refresh"))
        }

        LocalizationTestSupport.withLanguage(.simplifiedChinese) {
            #expect(L10n.claudeCredentialFileOnlyWarning.contains("自动凭据刷新"))
        }
    }

    @Test("Claude disk cache copy calls out prompt reduction and the tradeoff")
    func diskCacheCopyCallsOutPromptReductionAndTradeoff() {
        LocalizationTestSupport.withLanguage(.english) {
            #expect(L10n.mirrorClaudeCredsLabel.localizedCaseInsensitiveContains("fewer keychain prompts"))
            #expect(L10n.mirrorClaudeCredsHelp.localizedCaseInsensitiveContains("less secure"))
        }

        LocalizationTestSupport.withLanguage(.simplifiedChinese) {
            #expect(L10n.mirrorClaudeCredsLabel.contains("减少钥匙串提示"))
            #expect(L10n.mirrorClaudeCredsHelp.contains("安全性低于钥匙串"))
        }
    }

    @Test("Claude credentials settings hide the source picker outside recovery")
    func credentialsSettingsHideSourcePickerOutsideRecovery() throws {
        let source = try Self.source(named: "QuotaMonitor/Features/Settings/AdvancedSettingsTab.swift")

        #expect(!source.contains("Picker(\"\", selection: $settings.keychainPolicy)"))
        #expect(!source.contains("ForEach(SettingsStore.KeychainPolicy.allCases)"))
        #expect(source.contains("settings.keychainPolicy == .never"))
        #expect(source.contains("L10n.restoreAutomaticClaudeCredentialsMode"))
        #expect(source.contains("settings.keychainPolicy = .fallback"))
    }

    private static func source(named relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
