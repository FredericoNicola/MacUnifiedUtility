import SwiftUI

/// SwiftUI view for the Battery module.
///
/// Displays current battery status and an experimental 80% charge-limit toggle.
struct BatteryView: View {

    @EnvironmentObject private var manager: BatteryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Header ────────────────────────────────────────────────
            SectionHeader(icon: "battery.75", title: "Battery")

            // ── Status ────────────────────────────────────────────────
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if let pct = manager.chargePercent {
                        HStack {
                            batteryIcon(percent: pct)
                                .font(.largeTitle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(pct)%")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                Text(manager.isCharging ? "Charging" : (manager.isPluggedIn ? "Plugged In (Full)" : "Discharging"))
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                            Spacer()
                            Button("Refresh") { manager.refresh() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }

                        ProgressView(value: Double(pct), total: 100)
                            .tint(progressColor(percent: pct))
                    } else {
                        Label("No battery detected.", systemImage: "battery.slash")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(6)
            }

            // ── Error/Info Messages ───────────────────────────────────
            if let error = manager.lastError {
                ErrorBanner(message: error)
            }
            if let message = manager.lastMessage {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // ── Experimental Charge Limit ─────────────────────────────
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Experimental Feature")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    Text("Charge limiting writes to the SMC and is **not officially supported by Apple**. Use at your own risk. Not all hardware is supported.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Toggle("Enable charge limit", isOn: $manager.isChargeLimitEnabled)
                        .font(.subheadline)

                    if manager.isChargeLimitEnabled {
                        HStack {
                            Text("Limit:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Slider(value: Binding(
                                get: { Double(manager.chargeLimitPercent) },
                                set: { manager.chargeLimitPercent = Int($0) }
                            ), in: 60...100, step: 5)
                            Text("\(manager.chargeLimitPercent)%")
                                .font(.subheadline)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .padding(6)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }

    // MARK: - Helpers

    private func batteryIcon(percent: Int) -> Text {
        let name: String
        switch percent {
        case 90...100: name = "battery.100"
        case 65..<90:  name = "battery.75"
        case 40..<65:  name = "battery.50"
        case 15..<40:  name = "battery.25"
        default:       name = "battery.0"
        }
        return Text(Image(systemName: name))
    }

    private func progressColor(percent: Int) -> Color {
        switch percent {
        case 21...100: return .green
        case 11...20:  return .orange
        default:       return .red
        }
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
