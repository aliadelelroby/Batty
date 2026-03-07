import SwiftUI
import ServiceManagement

struct SettingsTab: View {
    @EnvironmentObject var monitor: BatteryMonitor
    @ObservedObject private var limitManager = ChargeLimitManager.shared
    @ObservedObject private var power = PowerManager.shared
    let scrollToTopTrigger: Bool
    @State private var customLimit: Double = 80
    @State private var lastHapticLimit: Int = -1

    // Menu bar display prefs
    @AppStorage("menuBarShowIcon")         private var showIcon: Bool = true
    @AppStorage("menuBarShowPercentage")   private var showPercentage: Bool = true
    @AppStorage("menuBarBoltWhenCharging") private var boltWhenCharging: Bool = true
    @AppStorage("menuBarShowTime")         private var showTime: Bool = false

    // Launch at login
    @State private var launchAtLogin: Bool = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                    Color.clear.frame(height: 0).id("top")
                    modeToggle
                    limitSection
                    setupStatusRow
                    divider
                    dischargeSection
                    divider
                    powerSection
                    divider
                    menuBarSection
                    divider
                    bottomRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
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
        .onAppear {
            customLimit = Double(monitor.chargeLimit)
            lastHapticLimit = monitor.chargeLimit
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            power.refresh()
        }
    }

    // MARK: - Setup Status Row
    @ViewBuilder
    private var setupStatusRow: some View {
        if limitManager.isSettingUp {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Setting up — enter admin password if prompted…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.4))
                Spacer()
            }
            .padding(.horizontal, 4)
        } else if !limitManager.isSetupComplete {
            HStack(spacing: 8) {
                Image(systemName: "lock.open")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.4))
                Text("Tap Apply — one-time admin password required")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.35))
                Spacer()
            }
            .padding(.horizontal, 4)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.3))
                Text("Hardware limit active — no further prompts needed")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.3))
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Discharge Section
    private var dischargeSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Discharge")
                .padding(.bottom, 10)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.isDischarging
                         ? "Discharging to \(monitor.chargeLimit)%…"
                         : "Discharge to \(monitor.chargeLimit)%")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .animation(.easeInOut(duration: 0.2), value: monitor.isDischarging)
                    Text(monitor.isDischarging
                         ? "Draining while plugged in — stops at the charge limit"
                         : "Drain battery while plugged in down to the charge limit")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.3))
                        .animation(.easeInOut(duration: 0.2), value: monitor.isDischarging)
                }

                Spacer()

                if monitor.isDischarging {
                    Button {
                        NSHapticFeedbackManager.defaultPerformer
                            .perform(.levelChange, performanceTime: .default)
                        monitor.stopDischarge()
                    } label: {
                        Text("Stop")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    let canDischarge = monitor.isConnected && monitor.isLimitEnabled
                        && monitor.percentage > monitor.chargeLimit
                    Button {
                        NSHapticFeedbackManager.defaultPerformer
                            .perform(.levelChange, performanceTime: .default)
                        monitor.startDischargeToTarget(monitor.chargeLimit)
                    } label: {
                        Text("Discharge")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(canDischarge ? 0.08 : 0.03))
                            .foregroundStyle(Color.primary.opacity(canDischarge ? 0.6 : 0.2))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDischarge)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Power Section
    private var powerSection: some View {
        VStack(spacing: 14) {
            // Profile indicator (read-only, follows power source)
            HStack(spacing: 6) {
                Image(systemName: monitor.isConnected ? "bolt.fill" : "battery.75")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.5))
                Text(monitor.isConnected ? "Plugged in" : "Battery")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.5))
                Spacer()
                Text("Settings for current source")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Performance mode
            VStack(spacing: 0) {
                sectionHeader("Performance")
                    .padding(.bottom, 10)

                VStack(spacing: 2) {
                    powerToggleRow(
                        icon: "tortoise",
                        title: "Low Power Mode",
                        subtitle: "Reduces CPU speed, display brightness, background activity",
                        isOn: Binding(
                            get: { monitor.isConnected ? power.lowPowerModeAC : power.lowPowerModeBattery },
                            set: { val in
                                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                power.setLowPowerMode(val, source: monitor.isConnected ? .ac : .battery)
                            }
                        )
                    )

                    if !monitor.isConnected {
                        HStack(spacing: 10) {
                            Image(systemName: "hare")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.18))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("High Power Mode")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.primary.opacity(0.22))
                                Text("AC only")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.primary.opacity(0.18))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    } else {
                        powerToggleRow(
                            icon: "hare",
                            title: "High Power Mode",
                            subtitle: "Sustained peak performance; fans louder, battery drains faster",
                            isOn: Binding(
                                get: { power.highPowerModeAC },
                                set: { val in
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                    power.setHighPowerMode(val)
                                }
                            )
                        )
                    }
                }
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Background & sleep
            VStack(spacing: 0) {
                sectionHeader("Sleep")
                    .padding(.bottom, 10)

                VStack(spacing: 2) {
                    powerToggleRow(
                        icon: "moon.zzz",
                        title: "Power Nap",
                        subtitle: "Fetch mail, contacts, iCloud updates while asleep",
                        isOn: Binding(
                            get: { monitor.isConnected ? power.powerNapAC : power.powerNapBattery },
                            set: { val in
                                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                power.setPowerNap(val, source: monitor.isConnected ? .ac : .battery)
                            }
                        )
                    )
                }
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 10)

                VStack(spacing: 10) {
                    sleepSlider(
                        label: "Display sleep",
                        icon: "display",
                        value: Binding(
                            get: { Double(monitor.isConnected ? power.displaySleepAC : power.displaySleepBattery) },
                            set: { val in power.setDisplaySleep(Self.sleepStep(Int(val)), source: monitor.isConnected ? .ac : .battery) }
                        )
                    )
                    .padding(14)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    sleepSlider(
                        label: "System sleep",
                        icon: "zzz",
                        value: Binding(
                            get: { Double(monitor.isConnected ? power.systemSleepAC : power.systemSleepBattery) },
                            set: { val in power.setSystemSleep(Self.sleepStep(Int(val)), source: monitor.isConnected ? .ac : .battery) }
                        )
                    )
                    .padding(14)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func powerToggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(limitManager.isSetupComplete ? 0.4 : 0.2))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(limitManager.isSetupComplete ? 0.75 : 0.3))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(limitManager.isSetupComplete ? 0.3 : 0.18))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(!limitManager.isSetupComplete)
                .opacity(limitManager.isSetupComplete ? 1 : 0.35)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 0.5)
                .padding(.leading, 42)
        }
    }

    private func sleepSlider(label: String, icon: String, value: Binding<Double>) -> some View {
        VStack(spacing: 10) {
            // Header row: icon + label on left, big value on right
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.35))
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.5))
                Spacer()
                Text(Self.sleepLabel(Int(value.wrappedValue)))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: Int(value.wrappedValue))
            }

            // Slider
            Slider(value: value, in: 0...120)
                .tint(Color.primary.opacity(0.6))
                .disabled(!limitManager.isSetupComplete)
                .opacity(limitManager.isSetupComplete ? 1 : 0.35)

            // Quick-select chips
            HStack(spacing: 6) {
                ForEach([0, 2, 5, 10, 30], id: \.self) { mins in
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            value.wrappedValue = Double(mins)
                        }
                    } label: {
                        let selected = Int(value.wrappedValue) == mins
                        Text(mins == 0 ? "Never" : "\(mins)m")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(selected ? 0.1 : 0.04))
                            .foregroundStyle(Color.primary.opacity(selected ? 0.8 : 0.35))
                            .clipShape(Capsule())
                            .scaleEffect(selected ? 1.04 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: selected)
                    }
                    .buttonStyle(.plain)
                    .disabled(!limitManager.isSetupComplete)
                    .opacity(limitManager.isSetupComplete ? 1 : 0.35)
                }
            }
        }
    }

    private static func sleepStep(_ raw: Int) -> Int {
        let steps = [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
        return steps.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? raw
    }

    private static func sleepLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "Never" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60; let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    // MARK: - Divider
    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.5)
    }

    // MARK: - Mode Toggle
    private var modeToggle: some View {
        HStack(spacing: 10) {
            ForEach(ChargeMode.allCases, id: \.self) { mode in
                Button {
                    NSHapticFeedbackManager.defaultPerformer
                        .perform(.alignment, performanceTime: .default)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        monitor.setMode(mode)
                        customLimit = Double(mode.limitPercentage)
                    }
                } label: {
                    let selected = monitor.currentMode == mode
                    VStack(spacing: 7) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 20, weight: selected ? .semibold : .regular))
                        Text(mode.displayName)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        Text("\(mode.limitPercentage)%")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(selected ? 0.45 : 0.2))
                    }
                    .foregroundStyle(Color.primary.opacity(selected ? 0.85 : 0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.primary.opacity(selected ? 0.07 : 0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(selected ? 0.15 : 0), lineWidth: 1)
                    )
                    .scaleEffect(selected ? 1.0 : 0.97)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Limit Section
    private var limitSection: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(customLimit))")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: customLimit)
                Text("%")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .offset(y: -2)
                Spacer()
                Button {
                    NSHapticFeedbackManager.defaultPerformer
                        .perform(.levelChange, performanceTime: .default)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        monitor.setCustomLimit(Int(customLimit))
                        monitor.applyChargeLimit()
                    }
                } label: {
                    HStack(spacing: 5) {
                        if monitor.isLimitEnabled {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(monitor.isLimitEnabled ? "Applied" : "Apply")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(monitor.isLimitEnabled ? 0.06 : 0.85))
                    .foregroundStyle(monitor.isLimitEnabled
                        ? Color.primary.opacity(0.4)
                        : Color(NSColor.windowBackgroundColor))
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.2), value: monitor.isLimitEnabled)
                }
                .buttonStyle(.plain)
            }

            Slider(value: $customLimit, in: 20...100, step: 5)
                .tint(Color.primary.opacity(0.6))
                .onChange(of: customLimit) { newVal in
                    let intVal = Int(newVal)
                    if intVal != lastHapticLimit {
                        lastHapticLimit = intVal
                        NSHapticFeedbackManager.defaultPerformer
                            .perform(.generic, performanceTime: .default)
                    }
                    if monitor.isLimitEnabled && intVal != monitor.chargeLimit {
                        monitor.removeChargeLimit()
                    }
                }

            HStack(spacing: 6) {
                ForEach([60, 70, 80, 90, 100], id: \.self) { p in
                    Button {
                        NSHapticFeedbackManager.defaultPerformer
                            .perform(.generic, performanceTime: .default)
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            customLimit = Double(p)
                        }
                    } label: {
                        Text("\(p)")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(Int(customLimit) == p ? 0.1 : 0.04))
                            .foregroundStyle(Color.primary.opacity(Int(customLimit) == p ? 0.8 : 0.35))
                            .clipShape(Capsule())
                            .scaleEffect(Int(customLimit) == p ? 1.04 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: Int(customLimit) == p)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Menu Bar Section
    private var menuBarSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Menu Bar")
                .padding(.bottom, 10)

            VStack(spacing: 2) {
                prefRow(
                    icon: "battery.100",
                    label: "Show battery icon",
                    binding: $showIcon
                )
                prefRow(
                    icon: "percent",
                    label: "Show percentage",
                    binding: $showPercentage
                )
                prefRow(
                    icon: "bolt.fill",
                    label: "Bolt icon when charging",
                    binding: $boltWhenCharging
                )
                prefRow(
                    icon: "clock",
                    label: "Show time to full / remaining",
                    binding: $showTime
                )

                prefRow(
                    icon: "arrow.up.right.square",
                    label: "Launch at login",
                    binding: Binding(
                        get: { launchAtLogin },
                        set: { val in
                            NSHapticFeedbackManager.defaultPerformer
                                .perform(.generic, performanceTime: .default)
                            do {
                                if val {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                                launchAtLogin = (SMAppService.mainApp.status == .enabled)
                            } catch {
                                launchAtLogin = (SMAppService.mainApp.status == .enabled)
                            }
                        }
                    )
                )

                // Open Control Center settings
                Button {
                    NSHapticFeedbackManager.defaultPerformer
                        .perform(.generic, performanceTime: .default)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.35))
                            .frame(width: 20)
                        Text("System Control Center settings")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.5))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.2))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Pref Toggle Row
    private func prefRow(icon: String, label: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.35))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.7))
            Spacer()
            Toggle("", isOn: Binding(
                get: { binding.wrappedValue },
                set: { val in
                    NSHapticFeedbackManager.defaultPerformer
                        .perform(.generic, performanceTime: .default)
                    binding.wrappedValue = val
                    // Post notification so AppDelegate refreshes icon immediately
                    NotificationCenter.default.post(name: .menuBarPrefsChanged, object: nil)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 0.5)
                .padding(.leading, 42)
        }
    }

    // MARK: - Section Header
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.3))
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
    }

    // MARK: - Bottom Row
    private var bottomRow: some View {
        HStack {
            Text("Batty v1.0")
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.2))
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }
}

extension Notification.Name {
    static let menuBarPrefsChanged = Notification.Name("menuBarPrefsChanged")
}
