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
            } else {
                // ── Status Bar ────────────────────────────────────────
                HStack {
                    Circle()
                        .fill(monitor.isMonitoring ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(monitor.isMonitoring ? "Monitoring – refreshes every \(Int(monitor.pollInterval)) s" : "Paused")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(monitor.isMonitoring ? "Pause" : "Resume") {
                        monitor.isMonitoring ? monitor.stopMonitoring() : monitor.startMonitoring()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // ── Poll Interval Stepper ─────────────────────────────
                HStack {
                    Text("Refresh interval:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Stepper("\(Int(monitor.pollInterval)) s",
                            value: $monitor.pollInterval,
                            in: 1...60,
                            step: 1)
                    .labelsHidden()
                    Text("\(Int(monitor.pollInterval)) s")
                        .monospacedDigit()
                }

                Divider()

                // ── Sensor List ───────────────────────────────────────
                if monitor.readings.isEmpty {
                    EmptyStateView(
                        title: "No Sensors Detected",
                        systemImage: "thermometer.slash",
                        description: "No SMC sensors responded. This may be normal on Apple Silicon Macs where some keys differ."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(monitor.readings) { reading in
                                SensorRow(reading: reading)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }
}

// MARK: - Sensor Row

private struct SensorRow: View {
    let reading: TemperatureReading

    private var temperatureColor: Color {
        switch reading.value {
        case ..<50:  return .green
        case ..<75:  return .yellow
        case ..<90:  return .orange
        default:     return .red
        }
    }

    var body: some View {
        HStack {
            Image(systemName: "thermometer")
                .foregroundColor(temperatureColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.key.displayName)
                    .font(.subheadline)
                Text(reading.key.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(reading.formattedValue)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(temperatureColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
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
