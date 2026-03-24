import SwiftUI

/// Rich SwiftUI view for the Battery module.
///
/// Shows a detailed power-state snapshot including level, time remaining, cycle count,
/// health, temperature, capacity, voltage, amperage, and SMC charging control.
struct BatteryView: View {

    @EnvironmentObject private var manager: BatteryManager

    var body: some View {
        if !manager.isOnLaptop {
            EmptyStateView(
                title: "No Battery",
                systemImage: "desktopcomputer",
                description: "This Mac has no internal battery."
            )
            .padding()
            .frame(minWidth: 420, minHeight: 320)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Header ─────────────────────────────────────────
                    SectionHeader(icon: "battery.100percent", title: "Battery")

                    // ── Main Info Card ─────────────────────────────────
                    if let state = manager.powerState {
                        mainInfoCard(state: state)
                        detailsCard(state: state)
                    } else {
                        CardView {
                            HStack(spacing: 8) {
                                Image(systemName: "battery.slash")
                                    .foregroundStyle(.secondary)
                                Text("Reading battery data…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // ── Charging Control ───────────────────────────────
                    if manager.chargingControlAvailable {
                        chargingControlCard
                    } else {
                        ErrorBanner(
                            message: "SMC charging control is not available. This feature requires the app to run without system restrictions — charging modes cannot be changed in the current configuration."
                        )
                    }

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .frame(minWidth: 420, minHeight: 380)
        }
    }

    // MARK: - Main Info Card

    @ViewBuilder
    private func mainInfoCard(state: PowerState) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    // Level percentage
                    Text("\(state.batteryLevel)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(levelColor(state: state))

                    VStack(alignment: .leading, spacing: 4) {
                        // Time description
                        Text(state.timeDescription)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)

                        // Power source badge
                        TagBadge(
                            text: state.powerSource,
                            color: state.chargerConnected ? .blue : .orange
                        )
                    }

                    Spacer()

                    // Charging indicator
                    if state.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                    }
                }

                // Color-coded fill bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(levelColor(state: state))
                            .frame(width: geo.size.width * CGFloat(state.batteryLevel) / 100.0, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: state.batteryLevel)
                    }
                }
                .frame(height: 8)

                // Optimized Battery Charging badge
                if state.optimizedBatteryChargingEngaged {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("Optimized Battery Charging engaged")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Details Card

    @ViewBuilder
    private func detailsCard(state: PowerState) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Divider()

                detailRow(label: "Cycle Count",
                          value: "\(state.cycleCount)")

                detailRow(label: "Battery Health",
                          value: state.batteryHealth.map { "\($0)%" } ?? "Unknown")

                temperatureRow(state: state)

                if let design = state.designCapacity,
                   let max    = state.maxCapacity,
                   let current = state.currentCapacity {
                    detailRow(label: "Capacity (Design / Max / Now)",
                              value: "\(design) / \(max) / \(current) mAh")
                }

                if let voltage = state.voltage {
                    detailRow(label: "Voltage",
                              value: String(format: "%.3f V", voltage / 1000.0))
                }

                if let amperage = state.amperage {
                    detailRow(label: "Amperage",
                              value: String(format: "%.0f mA", amperage))
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func temperatureRow(state: PowerState) -> some View {
        HStack {
            Text("Temperature")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                if state.batteryTemperature >= 40 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                Text(formatTemperature(state.batteryTemperature))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(state.batteryTemperature >= 40 ? .orange : .primary)
            }
        }
    }

    // MARK: - Charging Control Card

    private var chargingControlCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Charging Control")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Divider()

                Picker("Mode", selection: Binding(
                    get: { manager.chargingMode },
                    set: { manager.setChargingMode($0) }
                )) {
                    ForEach(ChargingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(manager.chargingMode.modeDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func levelColor(state: PowerState) -> Color {
        if state.isCharging   { return .blue }
        if state.batteryLevel <= 20 { return .red }
        if state.batteryLevel <= 40 { return .orange }
        return .green
    }

    private func formatTemperature(_ celsius: Double) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }
}

// MARK: - Preview

#if DEBUG
struct BatteryView_Previews: PreviewProvider {
    static var previews: some View {
        BatteryView()
            .environmentObject(BatteryManager())
    }
}
#endif
