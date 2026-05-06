import SwiftUI
import AppKit

/// Tiny utility button that puts `payload` on the system pasteboard and
/// flashes a "Copied" confirmation for ~1.5 s. Used in places where
/// in-place text selection is unreliable (e.g. NSPopover-hosted views,
/// long error lists). The payload is captured at construction time so
/// the button works even after the host view re-renders.
///
/// Currently only used by the scan-errors popover, but the type is
/// general — drop it next to any block of text the user would otherwise
/// have to screenshot.
struct CopyButton: View {
    let payload: String
    /// `nil` defaults to `L10n.copy` lazily so the button label tracks
    /// the current language. Static-property default parameters must be
    /// compile-time constants and `L10n.copy` is a runtime read.
    var label: String? = nil
    @State private var didCopy = false

    var body: some View {
        Button {
            // NSPasteboard.declareTypes + setString is the
            // straight-line way; on macOS 14+ we could use
            // `Pasteboard.general.string = ...` from SwiftUI but
            // AppKit gives us identical behavior with no version
            // gating.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(payload, forType: .string)
            didCopy = true
            // Reset after the toast window so the next click is
            // visually distinct. 1.5s matches Finder / Xcode "Copied"
            // flashes — long enough to register, short enough to avoid
            // looking stuck.
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                await MainActor.run { didCopy = false }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                Text(didCopy ? L10n.copied : (label ?? L10n.copy))
                    .font(.caption2)
            }
            .foregroundStyle(didCopy ? Color.green : Color.accentColor)
        }
        .buttonStyle(.plain)
        .help(L10n.copyTooltip(lines: payload.split(separator: "\n").count))
    }
}
