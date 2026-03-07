import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject var monitor: BatteryMonitor
    @State private var chargingPulse: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            heroSection
            Spacer()
            statsRow
                .padding(.horizontal, 20)
            limitStrip
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)
        }
        .onAppear { startPulseIfNeeded() }
        .onChange(of: monitor.isCharging) { _ in startPulseIfNeeded() }
        .onChange(of: monitor.isDischarging) { _ in startPulseIfNeeded() }
    }

    private func startPulseIfNeeded() {
        if monitor.isCharging {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                chargingPulse = true
            }
        } else {
            withAnimation(.default) { chargingPulse = false }
        }
    }

    // MARK: - Hero
    private var heroSection: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                // Percentage number
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("\(monitor.percentage)")
                        .font(.system(size: 72, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: monitor.percentage)
                        // Subtle pulse opacity when charging
                        .opacity(monitor.isCharging ? (chargingPulse ? 1.0 : 0.75) : 1.0)
                    Text("%")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }

                // Status line — charging icon inline
                HStack(spacing: 5) {
                    if monitor.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(chargingPulse ? 0.6 : 0.25))
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: chargingPulse)
                    } else if monitor.isConnected {
                        Image(systemName: "powerplug")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.3))
                    }
                    Text(statusText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .contentTransition(.interpolate)
                        .animation(.easeInOut(duration: 0.3), value: statusText)
                }
            }

            // Progress bar
            progressBar
                .padding(.horizontal, 40)
        }
    }

    private var statusText: String {
        if monitor.isCharging {
            let t = monitor.timeRemainingString
            return t.replacingOccurrences(of: " to full", with: "")
        }
        if monitor.isConnected {
            // Only say "Not charging" when the limit is engaged and holding the cap
            if monitor.isLimitEnabled && monitor.percentage >= monitor.chargeLimit {
                return "Not charging · limit reached"
            }
            return "Plugged in"
        }
        return monitor.timeRemainingString
            .replacingOccurrences(of: " remaining", with: "")
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 3)

                // Limit ghost
                if monitor.isLimitEnabled {
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: geo.size.width * CGFloat(monitor.chargeLimit) / 100, height: 3)
                }

                // Fill — slightly brighter when charging
                Capsule()
                    .fill(Color.primary.opacity(fillOpacity))
                    .frame(width: geo.size.width * CGFloat(monitor.percentage) / 100, height: 3)
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: monitor.percentage)
            }
        }
        .frame(height: 3)
    }

    private var fillOpacity: Double {
        if monitor.isCharging    { return chargingPulse ? 0.65 : 0.45 }
        if monitor.percentage <= 10 { return 0.85 }
        if monitor.percentage <= 20 { return 0.65 }
        return 0.5
    }

    // MARK: - Stats Row
    private var statsRow: some View {
        HStack(spacing: 0) {
            StatCell(value: monitor.temperatureString, label: "Temp")
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 22)
            StatCell(value: monitor.healthString, label: "Health")
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 22)
            StatCell(value: "\(monitor.cycleCount)", label: "Cycles")
        }
        .padding(.vertical, 13)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Limit Strip
    private var limitStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: monitor.isDischarging ? "arrow.down.circle" : (monitor.isLimitEnabled ? "lock.fill" : "lock.open"))
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(monitor.isLimitEnabled ? 0.5 : 0.2))
                .animation(.easeInOut(duration: 0.2), value: monitor.isLimitEnabled)
                .animation(.easeInOut(duration: 0.2), value: monitor.isDischarging)

            Text(limitStripLabel)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.primary.opacity(monitor.isLimitEnabled ? 0.55 : 0.25))
                .contentTransition(.interpolate)
                .animation(.easeInOut(duration: 0.2), value: limitStripLabel)

            Spacer()

            Toggle("", isOn: Binding(
                get: { monitor.isLimitEnabled },
                set: { on in
                    let impact = NSHapticFeedbackManager.defaultPerformer
                    impact.perform(.generic, performanceTime: .default)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        on ? monitor.applyChargeLimit() : monitor.removeChargeLimit()
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .tint(Color.primary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var limitStripLabel: String {
        if monitor.isDischarging { return "Discharging to \(monitor.chargeLimit)%\u{2026}" }
        if monitor.isLimitEnabled { return "Limit \(monitor.chargeLimit)%" }
        return "No limit"
    }
}

// MARK: - Stat Cell
struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }
}

