import Foundation
import Testing
@testable import QuotaMonitor

@Suite("Claude credentials settings copy", .serialized)
struct SettingsClaudeCredentialsCopyTests {
    @Test("Claude credential source labels explain the practical effect")
    func credentialSourceLabelsExplainPracticalEffect() {
        LocalizationTestSupport.withLanguage(.english) {
            #expect(L10n.keychainPolicyFallback.localizedCaseInsensitiveContains("recommended"))
            #expect(L10n.keychainPolicyFallback.localizedCaseInsensitiveContains("keychain"))
            #expect(L10n.keychainPolicyNever.localizedCaseInsensitiveContains("file only"))
            #expect(L10n.keychainPolicyNever.localizedCaseInsensitiveContains("no keychain"))
        }

        LocalizationTestSupport.withLanguage(.simplifiedChinese) {
            #expect(L10n.keychainPolicyFallback.contains("推荐"))
            #expect(L10n.keychainPolicyFallback.contains("钥匙串"))
            #expect(L10n.keychainPolicyNever.contains("仅文件"))
            #expect(L10n.keychainPolicyNever.contains("不读取钥匙串"))
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
}
