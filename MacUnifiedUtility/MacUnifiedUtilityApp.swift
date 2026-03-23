import SwiftUI

/// App entry point – lives in the menu bar using `MenuBarExtra`.
/// Each module is accessible from the popover menu.
@main
struct MacUnifiedUtilityApp: App {

    // MARK: - State

    @StateObject private var displayManager  = DisplayManager()
    @StateObject private var scrollManager   = ScrollManager()
    @StateObject private var thermalMonitor  = ThermalMonitor()
    @StateObject private var batteryManager  = BatteryManager()

    // MARK: - Scene

    var body: some Scene {
        // ── Menu Bar Popover ──────────────────────────────────────────
        MenuBarExtra("MacUnifiedUtility", systemImage: "gearshape") {
            AppMenuView()
                .environmentObject(displayManager)
                .environmentObject(scrollManager)
                .environmentObject(thermalMonitor)
                .environmentObject(batteryManager)
        }
        .menuBarExtraStyle(.window)

        // ── Settings Window ───────────────────────────────────────────
        Settings {
            SettingsView()
                .environmentObject(displayManager)
                .environmentObject(scrollManager)
                .environmentObject(thermalMonitor)
                .environmentObject(batteryManager)
        }
    }
}

// MARK: - App Menu View

/// Root view displayed inside the MenuBarExtra popover.
struct AppMenuView: View {

    @EnvironmentObject private var displayManager: DisplayManager
    @EnvironmentObject private var scrollManager:  ScrollManager
    @EnvironmentObject private var thermalMonitor: ThermalMonitor
    @EnvironmentObject private var batteryManager: BatteryManager

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .foregroundColor(.accentColor)
                Text("MacUnifiedUtility")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // ── Quick Status ──────────────────────────────────────────
            VStack(spacing: 4) {
                StatusRow(icon: "display", label: "Display",
                          value: "\(displayManager.displays.count) screen(s) connected")
                StatusRow(icon: "arrow.up.and.down",
                          label: "Scroll Reversal",
                          value: scrollManager.isReversalActive ? "Active" : "Inactive")
                StatusRow(icon: "thermometer",
                          label: "CPU Temp",
                          value: thermalMonitor.cpuTemperatureSummary)
                StatusRow(icon: "battery.75",
                          label: "Battery",
                          value: batteryManager.statusSummary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // ── Navigation Buttons ────────────────────────────────────
            VStack(spacing: 2) {
                SettingsLink(label: {
                    Label("Open Settings…", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, alignment: .leading)
                })
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 4)

                Divider()

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 300)
    }
}

// MARK: - Settings View

/// Tabbed settings window that hosts each module's settings view.
struct SettingsView: View {
    var body: some View {
        TabView {
            DisplayView()
                .tabItem { Label("Display", systemImage: "display") }

            ScrollSettingsView()
                .tabItem { Label("Scrolling", systemImage: "arrow.up.and.down") }

            ThermalMonitorView()
                .tabItem { Label("Thermal", systemImage: "thermometer") }

            BatteryView()
                .tabItem { Label("Battery", systemImage: "battery.75") }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Shared Helper Views

/// A single row in the quick-status section of the popover.
struct StatusRow: View {
    let icon:  String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)
            Text(label)
                .foregroundColor(.secondary)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
        }
    }
}
