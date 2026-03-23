import SwiftUI

/// SwiftUI settings view for the Scrolling module.
///
/// Lets the user enable or disable global scroll reversal independently for
/// mouse and trackpad.
struct ScrollSettingsView: View {

    @EnvironmentObject private var manager: ScrollManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── Header ────────────────────────────────────────────────
            SectionHeader(icon: "arrow.up.and.down", title: "Scroll Reversal")

            // ── Error Banner ──────────────────────────────────────────
            if let error = manager.lastError {
                ErrorBanner(message: error)
            }

            // ── Status & Master Toggle ────────────────────────────────
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scroll Reversal")
                                .font(.headline)
                            Text(manager.isReversalActive ? "Active – intercepting scroll events" : "Inactive")
                                .font(.subheadline)
                                .foregroundColor(manager.isReversalActive ? .green : .secondary)
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

                    // ── Per-Device Toggles ────────────────────────────
                    Text("Apply reversal to:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Toggle("🖱 Mouse (scroll wheel)", isOn: $manager.reverseMouse)
                        .padding(.leading, 8)

                    Toggle("⌨️ Trackpad (gestures)", isOn: $manager.reverseTrackpad)
                        .padding(.leading, 8)
                }
                .padding(6)
            }

            // ── Permission Note ───────────────────────────────────────
            GroupBox {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Permission Required")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("CGEvent taps require Accessibility access. If scroll reversal fails to activate, open System Settings → Privacy & Security → Accessibility and enable MacUnifiedUtility.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Open Accessibility Settings…") {
                            PermissionsHelper.openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .padding(6)
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
