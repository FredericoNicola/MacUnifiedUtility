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
                Button("Refresh") { manager.refresh() }
                    .buttonStyle(.bordered)
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
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Display Name
                HStack {
                    Image(systemName: "display")
                        .foregroundColor(.accentColor)
                    Text(display.name)
                        .font(.headline)
                }

                // Current Resolution
                if let current = display.currentMode {
                    HStack {
                        Text("Current:")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Text(current.label)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }

                Divider()

                // Resolution Picker
                HStack {
                    Text("Switch to:")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Picker("", selection: $selectedMode) {
                        Text("Select a mode…")
                            .tag(nil as CGDisplayMode?)       // ← matches the nil initial state
                        ForEach(display.availableModes, id: \.self) { mode in
                            Text(mode.label)
                                .tag(Optional(mode))          // already correct
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
                    .disabled(selectedMode == nil)
                }
            }
            .padding(6)
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
