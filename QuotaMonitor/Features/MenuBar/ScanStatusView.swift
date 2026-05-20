import SwiftUI

// "Last scan" status row + the failing-files popover. Extracted from
// MenuBarContentView for readability.

extension MenuBarContentView {

    @ViewBuilder
    var scanStatus: some View {
        if let progress = env.scanProgress {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.scanIndexingTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(L10n.scanProgressSummary(
                    completed: progress.completedFiles,
                    total: progress.totalFiles))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                ProgressView(value: progress.fraction ?? 0)
                    .progressViewStyle(.linear)
                if let file = progress.currentFile {
                    Text(L10n.scanCurrentFile(file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } else if let report = env.lastScanReport {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.lastScan)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(L10n.scanSummary(scanned: report.scannedFiles,
                                      changed: report.changedFiles,
                                      events: report.importedEvents))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if !report.errors.isEmpty {
                    // Was a static red label — now opens the failing-file
                    // list so the user can investigate. 50/668 errors with
                    // no escape hatch was the worst part of the menu bar.
                    Button {
                        showingErrors = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text(L10n.errorCount(report.errors.count))
                                .font(.caption2)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingErrors,
                             arrowEdge: .leading) {
                        scanErrorsPopover(report.errors)
                    }
                }
            }
        } else {
            Text(L10n.noScanYet)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func scanErrorsPopover(_ errors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.scanErrors).font(.headline)
                Spacer()
                Text(L10n.errorTotal(errors.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                // One-click copy: drag-selection inside an NSPopover is
                // flaky (popover steals focus on click), so we expose
                // an explicit "Copy all" button. Copies the full list,
                // not just the first 100 we render — that's almost
                // always what the user wants when triaging.
                CopyButton(payload: errors.joined(separator: "\n"),
                           label: L10n.copyAll)
            }
            Text(L10n.scanErrorsExplain)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(errors.prefix(100).enumerated()), id: \.offset) { _, err in
                        Text(err)
                            .font(.caption2.monospacedDigit())
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                    if errors.count > 100 {
                        Text(L10n.moreTruncated(errors.count - 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
        }
        .padding(12)
        .frame(width: 420)
    }
}
