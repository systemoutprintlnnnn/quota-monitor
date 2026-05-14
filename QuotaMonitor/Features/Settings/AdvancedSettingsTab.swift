import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Power-user / debugging knobs. Anything that 95% of users never need
/// but 5% absolutely require lives here. Sections:
///
///   - Codex CLI: binary path + CODEX_HOME override
///   - Claude Code: home path override + Keychain access policy
///   - Database: location + reveal in Finder
///   - Export: usage_events.csv dump
///
/// **Why a separate tab:** the General tab was getting visually
/// overwhelming with eight controls before this split. Pushing rare
/// knobs here keeps the General tab to four obvious settings without
/// taking any feature away from the people who need them.
struct AdvancedSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var env
    @State private var exportStatus: String?
    @State private var exporting = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section(L10n.sectionCodexCLI) {
                LabeledContent(L10n.binaryPath) {
                    pathField(
                        text: $settings.codexBinaryOverride,
                        prompt: L10n.autoDetectPrompt) { url in
                            url.path
                        }
                }
                LabeledContent("CODEX_HOME") {
                    pathField(
                        text: $settings.codexHomeOverride,
                        prompt: L10n.codexHomePrompt,
                        chooseDirectories: true) { url in
                            url.path
                        }
                }
                Text(L10n.pathOverrideHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Codex rate-limit poll cadence. Lives here (not General)
                // because the value only affects the Codex CLI IPC pull;
                // Claude /usage is a separate timer hard-coded to 2 h.
                // Surfacing it next to the other Codex CLI knobs makes
                // the scope obvious.
                LabeledContent(L10n.interval) {
                    HStack(spacing: 8) {
                        Text(L10n.minutesShort(settings.pollIntervalSeconds / 60))
                            .monospacedDigit()
                            .frame(minWidth: 56, alignment: .trailing)
                        Stepper("",
                                value: $settings.pollIntervalSeconds,
                                in: 60...3600, step: 60)
                            .labelsHidden()
                            .onChange(of: settings.pollIntervalSeconds) { _, _ in
                                env.applySettings()
                            }
                    }
                }
                Text(L10n.codexPollingHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n.sectionClaudeCode) {
                LabeledContent(L10n.claudeHomeLabel) {
                    pathField(
                        text: $settings.claudeHomeOverride,
                        prompt: L10n.claudeHomePrompt,
                        chooseDirectories: true) { url in
                            url.path
                        }
                }
                Text(L10n.claudePathOverrideHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(L10n.keychainPolicyLabel) {
                    Picker("", selection: $settings.keychainPolicy) {
                        ForEach(SettingsStore.KeychainPolicy.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320, alignment: .trailing)
                }
                Text(L10n.claudeOAuthExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(L10n.mirrorClaudeCredsLabel,
                       isOn: $settings.mirrorClaudeKeychainToFile)
                Text(L10n.mirrorClaudeCredsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n.sectionDatabase) {
                LabeledContent(L10n.location) {
                    Text(DatabaseManager.defaultURL().path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button(L10n.revealInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([DatabaseManager.defaultURL()])
                }
            }

            Section(L10n.sectionExport) {
                Button(L10n.exportUsageEventsCsv) {
                    Task { await exportCSV() }
                }
                .disabled(exporting)
                if let exportStatus {
                    Text(exportStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func pathField(
        text: Binding<String>,
        prompt: String,
        chooseDirectories: Bool = false,
        transform: @escaping (URL) -> String
    ) -> some View {
        HStack {
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
            Button(L10n.choose) {
                let panel = NSOpenPanel()
                panel.canChooseFiles = !chooseDirectories
                panel.canChooseDirectories = chooseDirectories
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    text.wrappedValue = transform(url)
                }
            }
            if !text.wrappedValue.isEmpty {
                Button(L10n.clear) { text.wrappedValue = "" }
            }
        }
    }

    private func exportCSV() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "codex-events.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        exporting = true
        defer { exporting = false }
        do {
            let count = try await env.exportUsageEventsCSV(to: url)
            exportStatus = L10n.exportedEventsTo(count, fileName: url.lastPathComponent)
        } catch {
            exportStatus = L10n.exportFailed(String(describing: error))
        }
    }
}
