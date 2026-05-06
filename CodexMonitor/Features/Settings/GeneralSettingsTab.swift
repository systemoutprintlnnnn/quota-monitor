import SwiftUI
import AppKit

/// General preferences. Deliberately kept short — only the three knobs
/// regular users actually touch:
///   1. Language
///   2. Menu bar headline window (7d / 30d)
///   3. Notifications threshold
///
/// Path overrides, keychain policy, database location, CSV export, and
/// the Codex rate-limit poll interval all moved to `AdvancedSettingsTab`
/// so first-time users aren't intimidated.
struct GeneralSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var env
    @Environment(LocalizationStore.self) private var loc

    var body: some View {
        @Bindable var settings = settings
        Form {
            // Top of the General tab — language is the first thing the
            // user is likely to look for after first launch since the
            // onboarding sheet promised "you can change it later in
            // Settings". Keep it before any technical sections.
            Section(L10n.sectionLanguage) {
                LabeledContent(L10n.languagePickerLabel) {
                    Picker("", selection: Binding(
                        get: { loc.currentLanguage },
                        set: { loc.set($0) }
                    )) {
                        ForEach(LocalizationStore.Language.allCases) { lang in
                            Text(lang.nativeName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                Text(L10n.languagePickerHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Menu bar headline window — controls both the menu bar's
            // "API equivalent" $ on each provider block and the Dashboard
            // statline. Keep them in lock-step so the user never sees
            // two different "this is the period we mean" values in one
            // glance.
            Section(L10n.sectionMenuBar) {
                LabeledContent(L10n.menuBarHeadlineWindowLabel) {
                    Picker("", selection: $settings.menuBarHeadlineWindow) {
                        ForEach(HeadlineWindow.allCases) { w in
                            Text(L10n.headlineWindowLabel(w)).tag(w)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                Text(L10n.menuBarHeadlineWindowHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Notifications — single knob "ping me when usage hits X%".
            // Polling interval that drives "when do we re-check usage"
            // lives in Advanced because tuning it well requires knowing
            // which provider it actually applies to (Codex only).
            Section(L10n.sectionNotifications) {
                LabeledContent(L10n.notifyAt) {
                    HStack {
                        Slider(value: $settings.notifyThreshold,
                               in: 50...100, step: 5)
                            .frame(maxWidth: 220)
                        Text("\(Int(settings.notifyThreshold))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
