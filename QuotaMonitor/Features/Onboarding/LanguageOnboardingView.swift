import SwiftUI

/// First-launch language picker. Shown as a modal sheet over whatever
/// view first appears (today: the menu bar popover; if the user opens
/// the dashboard window first, that one).
///
/// **Why a sheet, not a full-screen dialog.** The menu bar popover is
/// only 360pt wide and `.sheet` works inside it. A full window would
/// fight `MenuBarExtra(.window)`'s auto-dismiss-on-outside-click.
///
/// **Hard requirement: cannot be dismissed without picking.** No close
/// button, no escape, the only way out is one of the two language
/// buttons. We intentionally pin `isPresented = needsOnboarding` and
/// don't expose a setter for the user to close it some other way.
///
/// **Self-readability.** Both buttons display their label in the
/// language they would activate, so a user who can't read the current
/// UI language can still find their language. The headline is rendered
/// in BOTH languages for the same reason — there's no "before-onboarding
/// neutral language" so we just show both.
struct LanguageOnboardingView: View {
    @Environment(LocalizationStore.self) private var loc

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                Text("Welcome to Quota Monitor")
                    .font(.title3.weight(.semibold))
                Text("欢迎使用 Quota Monitor")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pick your language. You can change it later in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("请选择语言，稍后可在设置中更改。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                Button {
                    loc.set(.english)
                } label: {
                    Label("Continue in English", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Button {
                    loc.set(.simplifiedChinese)
                } label: {
                    Label("使用简体中文继续", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 8)
        }
        .padding(20)
        .frame(width: 320)
    }
}
