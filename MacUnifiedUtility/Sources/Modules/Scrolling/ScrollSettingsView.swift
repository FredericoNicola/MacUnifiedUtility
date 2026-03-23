import SwiftUI

/// SwiftUI settings view for the Scrolling module.
///
/// Lets the user enable or disable global scroll reversal independently for
/// mouse and trackpad.
struct ScrollSettingsView: View {

    @EnvironmentObject private var manager: ScrollManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Header ────────────────────────────────────────────────
            SectionHeader(icon: "arrow.up.and.down", title: "Scroll Reversal")

            // ── Error Banner ──────────────────────────────────────────
            if let error = manager.lastError {
                ErrorBanner(message: error)
            }

            // ── Status & Master Toggle ────────────────────────────────
            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        StatusDot(
                            isActive: manager.isReversalActive,
                            activeColor: .green
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scroll Reversal")
                                .font(.system(size: 13, weight: .semibold))
                            Text(manager.isReversalActive
                                 ? "Active – intercepting scroll events"
                                 : "Inactive")
                                .font(.system(size: 11))
                                .foregroundStyle(manager.isReversalActive ? .green : .secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { manager.isReversalActive },
                            set: { _ in manager.toggle() }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }

                    Divider()

                    Text("Apply reversal to:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Toggle("🖱 Mouse (scroll wheel)", isOn: $manager.reverseMouse)
                        .font(.system(size: 13))
                        .padding(.leading, 8)

                    Toggle("⌨️ Trackpad (gestures)", isOn: $manager.reverseTrackpad)
                        .font(.system(size: 13))
                        .padding(.leading, 8)
                }
            }

            // ── Permission Note ───────────────────────────────────────
            CardView {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.orange.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "lock.shield")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Permission Required")
                            .font(.system(size: 13, weight: .semibold))
                        Text("CGEvent taps require Accessibility access. If scroll reversal fails to activate, open System Settings → Privacy & Security → Accessibility and enable MacUnifiedUtility.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Open Accessibility Settings…") {
                            PermissionsHelper.openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }
}

// MARK: - Preview

#if DEBUG
struct ScrollSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollSettingsView()
            .environmentObject(ScrollManager())
    }
}
#endif
