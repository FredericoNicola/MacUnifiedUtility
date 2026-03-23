import SwiftUI

/// SwiftUI view for the Thermal module.
///
/// Shows a live-updating list of all detected SMC temperature sensors.
struct ThermalMonitorView: View {

    @EnvironmentObject private var monitor: ThermalMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Header ────────────────────────────────────────────────
            SectionHeader(icon: "thermometer", title: "Temperature Monitor")

            // ── Unavailable Banner ────────────────────────────────────
            if let reason = monitor.unavailableReason {
                ErrorBanner(message: reason)
                Button {
                    monitor.retryConnection()
                } label: {
                    Label("Retry Connection", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                // ── Status Bar ────────────────────────────────────────
                CardView {
                    HStack(spacing: 8) {
                        StatusDot(isActive: monitor.isMonitoring)
                        Text(monitor.isMonitoring
                             ? "Monitoring · refreshes every \(Int(monitor.pollInterval)) s"
                             : "Paused")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(monitor.isMonitoring ? "Pause" : "Resume") {
                            monitor.isMonitoring ? monitor.stopMonitoring() : monitor.startMonitoring()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Stepper("", value: $monitor.pollInterval, in: 1...60, step: 1)
                            .labelsHidden()
                            .frame(width: 36)
                        Text("\(Int(monitor.pollInterval)) s")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }

                // ── Sensor List ───────────────────────────────────────
                let hasReadings = !monitor.readings.isEmpty || !monitor.dynamicReadings.isEmpty
                if hasReadings {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(monitor.readings) { reading in
                                SensorRow(reading: reading)
                            }
                            ForEach(monitor.dynamicReadings) { reading in
                                DynamicSensorRow(reading: reading)
                            }
                        }
                    }
                } else {
                    EmptyStateView(
                        title: "No Sensors Detected",
                        systemImage: "thermometer.medium.slash",
                        description: "No SMC sensors responded. This may be normal on Apple Silicon Macs where some keys differ."
                    )
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }
}

// MARK: - Sensor Row (known keys)

private struct SensorRow: View {
    let reading: TemperatureReading

    private var temperatureColor: Color {
        switch reading.value {
        case ..<45:  return .green
        case ..<65:  return .yellow
        case ..<80:  return .orange
        default:     return .red
        }
    }

    private var temperatureLevel: String {
        switch reading.value {
        case ..<45:  return "Normal"
        case ..<65:  return "Warm"
        case ..<80:  return "Hot"
        default:     return "Critical"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(temperatureColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(temperatureColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(reading.key.displayName)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    Text(reading.key.rawValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    TagBadge(text: temperatureLevel, color: temperatureColor)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(reading.formattedValue)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(temperatureColor)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.06))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(temperatureColor.opacity(0.6))
                            .frame(width: geo.size.width * min(reading.value / 110.0, 1.0))
                    }
                }
                .frame(width: 60, height: 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Dynamic Sensor Row (discovered keys)

private struct DynamicSensorRow: View {
    let reading: DynamicTemperatureReading

    private var temperatureColor: Color {
        switch reading.value {
        case ..<45:  return .green
        case ..<65:  return .yellow
        case ..<80:  return .orange
        default:     return .red
        }
    }

    private var temperatureLevel: String {
        switch reading.value {
        case ..<45:  return "Normal"
        case ..<65:  return "Warm"
        case ..<80:  return "Hot"
        default:     return "Critical"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(temperatureColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(temperatureColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(reading.displayName)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    Text(reading.key)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    TagBadge(text: temperatureLevel, color: temperatureColor)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(reading.formattedValue)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(temperatureColor)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.06))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(temperatureColor.opacity(0.6))
                            .frame(width: geo.size.width * min(reading.value / 110.0, 1.0))
                    }
                }
                .frame(width: 60, height: 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ThermalMonitorView_Previews: PreviewProvider {
    static var previews: some View {
        ThermalMonitorView()
            .environmentObject(ThermalMonitor())
    }
}
#endif
