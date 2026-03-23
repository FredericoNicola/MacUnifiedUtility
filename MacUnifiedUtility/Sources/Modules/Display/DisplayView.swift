import SwiftUI
import CoreGraphics

/// SwiftUI view for the Display module.
///
/// Shows every connected display, its current resolution, and a picker to
/// switch to any available mode.
struct DisplayView: View {

    @EnvironmentObject private var manager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Header ────────────────────────────────────────────────
            SectionHeader(icon: "display", title: "Display Resolution")

            // ── Error Banner ──────────────────────────────────────────
            if let error = manager.lastError {
                ErrorBanner(message: error)
            }

            // ── Display List ──────────────────────────────────────────
            if manager.displays.isEmpty {
                EmptyStateView(
                    title: "No Displays Found",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: "Make sure your displays are connected and active."
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(manager.displays) { display in
                            DisplayRow(display: display)
                        }
                    }
                }
            }

            // ── Refresh Button ────────────────────────────────────────
            HStack {
                Spacer()
                Button {
                    manager.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 300)
        .onAppear { manager.refresh() }
    }
}

// MARK: - Display Row

private struct DisplayRow: View {

    @EnvironmentObject private var manager: DisplayManager
    let display: DisplayInfo

    @State private var selectedMode: CGDisplayMode?

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                // Display name + icon
                HStack(spacing: 8) {
                    Image(systemName: "display")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.accentColor)
                    Text(display.name)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if let current = display.currentMode {
                        TagBadge(text: current.label, color: .accentColor)
                    }
                }

                Divider()

                // Resolution picker
                HStack {
                    Text("Switch to:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $selectedMode) {
                        Text("Select a mode…")
                            .tag(nil as CGDisplayMode?)
                        ForEach(display.availableModes, id: \.self) { mode in
                            Text(mode.label)
                                .tag(Optional(mode))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button("Apply") {
                        if let mode = selectedMode {
                            manager.setMode(mode, for: display)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedMode == nil)
                }
            }
        }
        .onAppear {
            selectedMode = display.availableModes.first
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DisplayView_Previews: PreviewProvider {
    static var previews: some View {
        DisplayView()
            .environmentObject(DisplayManager())
    }
}
#endif
