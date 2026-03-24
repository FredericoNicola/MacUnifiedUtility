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

            // ── Status Card ───────────────────────────────────────────
            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    if let pct = manager.chargePercent {
                        HStack(spacing: 14) {
                            // Circular gauge
                            ZStack {
                                Circle()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 5)
                                Circle()
                                    .trim(from: 0, to: CGFloat(pct) / 100.0)
                                    .stroke(progressColor(percent: pct),
                                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text("\(pct)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(progressColor(percent: pct))
                            }
                            .frame(width: 52, height: 52)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(pct)%")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                HStack(spacing: 6) {
                                    TagBadge(
                                        text: manager.isCharging ? "Charging" : (manager.isPluggedIn ? "Plugged In" : "Discharging"),
                                        color: manager.isCharging ? .green : (manager.isPluggedIn ? .blue : .orange)
                                    )
                                }
                            }

                            Spacer()

                            Button {
                                manager.refresh()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        ProgressView(value: Double(pct), total: 100)
                            .tint(progressColor(percent: pct))
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "battery.slash")
                                .foregroundStyle(.secondary)
                            Text("No battery detected.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // ── Error/Info Messages ───────────────────────────────────
            if let error = manager.lastError {
                ErrorBanner(message: error)
            }
            if let message = manager.lastMessage {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // ── Experimental Charge Limit Card ────────────────────────
            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.system(size: 13))
                        Text("Experimental Feature")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }

                    Text("Charge limiting writes to the SMC and is **not officially supported by Apple**. Use at your own risk. Not all hardware is supported.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Divider()

                    Toggle("Enable charge limit", isOn: $manager.isChargeLimitEnabled)
                        .font(.system(size: 13))

                    if manager.isChargeLimitEnabled {
                        HStack {
                            Text("Limit:")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { Double(manager.chargeLimitPercent) },
                                set: { manager.chargeLimitPercent = Int($0) }
                            ), in: 60...100, step: 5)
                            Text("\(manager.chargeLimitPercent)%")
                                .font(.system(size: 13, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    // ── Privileges section ─────────────────────────────
                    if !PrivilegedHelperManager.shared.hasRootAccess {
                        Divider()
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.blue.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.blue)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Admin Privileges Required")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Charge limiting requires elevated privileges to write to the SMC.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                PrivilegedHelperManager.shared.installHelper()
                            } label: {
                                Label("Install Privileged Helper", systemImage: "shield.lefthalf.filled")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }

    // MARK: - Helpers

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
