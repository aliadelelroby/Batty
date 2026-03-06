import SwiftUI

struct DetailsTab: View {
    @EnvironmentObject var monitor: BatteryMonitor
    let scrollToTopTrigger: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 1) {
                    Color.clear.frame(height: 0).id("top")
                    healthHeader
                        .padding(.bottom, 12)

                    Group {
                        row("Temperature",  monitor.temperatureString)
                        row("Voltage",      monitor.voltageString)
                        row("Current",      monitor.amperageString)
                        row("Battery power", monitor.wattageString)
                        row("System load",  String(format: "%.1fW", monitor.systemLoad))
                        row("Capacity",     "\(monitor.currentRawCapacity) / \(monitor.currentMaxCapacity) mAh")
                        row("Design cap.",  "\(monitor.designCapacity) mAh")
                        row("Cycles",       "\(monitor.cycleCount)", hint: cycleHint)
                        row(monitor.isCharging ? "Time to full" : "Time remaining", timeStr)
                        if !monitor.adapterName.isEmpty {
                            row("Adapter", monitor.adapterName)
                        }
                        if !monitor.manufacturer.isEmpty {
                            row("Made by", monitor.manufacturer)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            .onChange(of: scrollToTopTrigger) { _ in
                DispatchQueue.main.async {
                    withAnimation(.none) {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Health Header
    private var healthHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(String(format: "%.0f", monitor.health))
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text("%")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.3))
                .offset(y: -4)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Battery Health")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.35))
                Text(monitor.healthStatus.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: geo.size.width * CGFloat(monitor.health / 100.0), height: 3)
                        .animation(.easeInOut(duration: 0.8), value: monitor.health)
                }
            }
            .frame(height: 3)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Row
    @ViewBuilder
    private func row(_ label: String, _ value: String, hint: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.4))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                if let hint = hint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private var timeStr: String {
        let mins = monitor.isCharging ? monitor.computedMinutesToFull : monitor.computedMinutesToEmpty
        guard mins > 0 else { return "—" }
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var cycleHint: String? {
        if monitor.cycleCount > 1000 { return "Replace recommended" }
        if monitor.cycleCount > 800  { return "Monitor" }
        return nil
    }
}
