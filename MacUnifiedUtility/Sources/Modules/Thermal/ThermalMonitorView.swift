import SwiftUI

/// SwiftUI view for the Thermal / Sensors module.
///
/// Renders live SMC, HID, and IOReport sensor data grouped by hardware section
/// (CPU, GPU, System, Sensors, HID, Unknown). Each section shows sensors of
/// all types: temperature, voltage, current, power, energy, and fan RPM.
struct ThermalMonitorView: View {

    @EnvironmentObject private var monitor: ThermalMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Header ────────────────────────────────────────────────────
            SectionHeader(icon: "thermometer", title: "Temperature & Sensors")

            // ── Unavailable Banner ────────────────────────────────────────
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
                // ── Status Bar ────────────────────────────────────────────
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

                // ── Grouped Sensor List ───────────────────────────────────
                if monitor.sensors.isEmpty {
                    EmptyStateView(
                        title: "No Sensors Detected",
                        systemImage: "thermometer.medium.slash",
                        description: "No SMC sensors responded. This may be normal on Apple Silicon Macs where some keys differ."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(monitor.groupedSensors, id: \.group.rawValue) { section in
                                SensorGroupSection(group: section.group,
                                                   sensors: section.sensors)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 460, minHeight: 340)
    }
}

// MARK: - Group Section

private struct SensorGroupSection: View {
    let group: SensorGroup
    let sensors: [any Sensor_p]

    private var groupIcon: String {
        switch group {
        case .CPU:     return "cpu"
        case .GPU:     return "rectangle.3.group"
        case .system:  return "memorychip"
        case .sensor:  return "sensor"
        case .hid:     return "waveform"
        case .unknown: return "questionmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: groupIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(group.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 5) {
                ForEach(Array(sensors.enumerated()), id: \.offset) { _, sensor in
                    SensorRow(sensor: sensor)
                }
            }
        }
    }
}

// MARK: - Sensor Row (unified for all sensor types)

private struct SensorRow: View {
    let sensor: any Sensor_p

    // MARK: Temperature colour

    private var tempColor: Color {
        guard sensor.type == .temperature else { return .accentColor }
        switch sensor.value {
        case ..<45:  return .green
        case ..<65:  return .yellow
        case ..<80:  return .orange
        default:     return .red
        }
    }

    private var tempLabel: String {
        switch sensor.value {
        case ..<45:  return "Normal"
        case ..<65:  return "Warm"
        case ..<80:  return "Hot"
        default:     return "Critical"
        }
    }

    // MARK: Type icon

    private var typeIcon: String {
        switch sensor.type {
        case .temperature: return "thermometer.medium"
        case .voltage:     return "bolt"
        case .current:     return "arrow.right.circle"
        case .power:       return "flame"
        case .energy:      return "battery.100"
        case .fan:         return "fan"
        }
    }

    var body: some View {
        if let fan = sensor as? Fan {
            FanRow(fan: fan)
        } else {
            genericRow
        }
    }

    @ViewBuilder
    private var genericRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tempColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: typeIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tempColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sensor.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(sensor.key)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if sensor.type == .temperature {
                        TagBadge(text: tempLabel, color: tempColor)
                    }
                    if sensor.isComputed {
                        TagBadge(text: "avg", color: .secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(sensor.formattedValue)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(sensor.type == .temperature ? tempColor : .primary)

                if sensor.type == .temperature {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.06))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(tempColor.opacity(0.6))
                                .frame(width: geo.size.width * min(sensor.value / 110.0, 1.0))
                        }
                    }
                    .frame(width: 60, height: 4)
                }
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

// MARK: - Fan Row

private struct FanRow: View {
    let fan: Fan

    private var speedColor: Color {
        let pct = fan.percentage
        switch pct {
        case ..<40: return .green
        case ..<70: return .yellow
        case ..<90: return .orange
        default:    return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(speedColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "fan")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(speedColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(fan.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(fan.key)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    TagBadge(text: fan.mode == .automatic ? "Auto" : "Forced",
                             color: fan.mode == .automatic ? .blue : .orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(fan.value)) RPM")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(speedColor)
                Text("\(Int(fan.minSpeed))–\(Int(fan.maxSpeed)) RPM")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.06))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(speedColor.opacity(0.6))
                            .frame(width: geo.size.width * Double(fan.percentage) / 100.0)
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
