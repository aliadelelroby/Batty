import Foundation
import IOKit.ps
import IOKit

// MARK: - Mode
enum ChargeMode: String, Codable, CaseIterable {
    case desk = "desk"
    case go = "go"

    var displayName: String {
        switch self {
        case .desk: return "Desk"
        case .go: return "On the Go"
        }
    }

    var icon: String {
        switch self {
        case .desk: return "desktopcomputer"
        case .go: return "figure.walk"
        }
    }

    var limitPercentage: Int {
        switch self {
        case .desk: return 80
        case .go: return 100
        }
    }

    var description: String {
        switch self {
        case .desk: return "Limits charge to 80% for long-term battery health when staying at your desk."
        case .go: return "Full charge for maximum battery life when you're away from power."
        }
    }
}

// MARK: - Battery Health Status
enum BatteryHealthStatus: String {
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case unknown = "Unknown"

}

// MARK: - BatteryMonitor
@MainActor
class BatteryMonitor: ObservableObject {
    @Published var percentage: Int = 0
    @Published var isCharging: Bool = false
    @Published var isConnected: Bool = false
    @Published var timeToEmpty: Int = 0       // minutes
    @Published var timeToFull: Int = 0        // minutes
    @Published var health: Double = 100.0     // percentage
    @Published var healthStatus: BatteryHealthStatus = .unknown
    @Published var cycleCount: Int = 0
    @Published var temperature: Double = 0.0  // Celsius
    @Published var voltage: Double = 0.0      // Volts
    @Published var amperage: Double = 0.0     // Amps (current draw, negative = discharging)
    @Published var wattage: Double = 0.0         // Watts (battery net charge/discharge)
    @Published var designCapacity: Int = 0         // mAh
    @Published var currentMaxCapacity: Int = 0     // mAh
    @Published var currentRawCapacity: Int = 0     // mAh (actual current charge level)
    @Published var manufacturer: String = ""
    // Adapter
    @Published var adapterWatts: Int = 0           // Rated adapter wattage from IOKit AdapterDetails
    @Published var adapterName: String = ""        // Adapter name from IOKit AdapterDetails
    // Telemetry (mW, direct from PMU)
    @Published var batteryNetPower: Double = 0.0   // mW going into (positive) or out of (negative) battery
    @Published var systemLoad: Double = 0.0        // mW total system consumption
    @Published var adapterPowerIn: Double = 0.0    // mW coming from wall
    // Gauge-computed times (most accurate — coulomb counter in battery chip)
    @Published var avgTimeToFull: Int = 0          // minutes (from gauge, valid when charging)
    @Published var avgTimeToEmpty: Int = 0         // minutes (from gauge, valid when discharging)
    @Published var chargeLimit: Int = 80      // max charge cap (%)
    @Published var minCharge: Int = 75         // re-enable charging below this (%)
    @Published var currentMode: ChargeMode = .desk
    @Published var isLimitEnabled: Bool = false
    @Published var chargeLimitStatus: String = "Not set"
    @Published var isSetupComplete: Bool = false
    // Discharge
    @Published var isDischarging: Bool = false

    init() {
        loadSettings()
        refresh()
        // Start event-driven enforcement after first read
        if isLimitEnabled {
            ChargeLimitManager.shared.startEnforcement(maxCharge: chargeLimit)
        }
    }

    func refresh() {
        // Read IOPowerSources synchronously (fast, main-thread safe)
        readIOPowerSources()
        // Read heavy IOKit battery details off the main thread
        Task.detached(priority: .utility) {
            let details = BatteryDetails.read()
            await MainActor.run { [weak self] in
                self?.applyDetails(details)
            }
        }
        // Cache setup state without hitting the filesystem each time
        isSetupComplete = ChargeLimitManager.shared.isSetupComplete
        // Mirror discharge state — ChargeLimitManager may have stopped it (unplug/wake/target reached)
        let managerDischarging = ChargeLimitManager.shared.isDischarging
        if isDischarging && !managerDischarging {
            isDischarging = false
            chargeLimitStatus = isLimitEnabled ? "Limit active at \(chargeLimit)%" : "No limit"
            saveSettings()
        } else {
            isDischarging = managerDischarging
        }
        // NOTE: enforcement is fully event-driven via ChargeLimitManager's
        // notify_register_dispatch loop — do NOT call enforceLimit() here.
    }

    // MARK: - IOPowerSources (basic info)
    private func readIOPowerSources() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                percentage = info[kIOPSCurrentCapacityKey] as? Int ?? percentage
                isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
                isConnected = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

                if let tte = info[kIOPSTimeToEmptyKey] as? Int, tte > 0 {
                    timeToEmpty = tte
                }
                if let ttf = info[kIOPSTimeToFullChargeKey] as? Int, ttf > 0 {
                    timeToFull = ttf
                }
                break
            }
        }
    }

    // MARK: - IOKit registry (detailed battery info — runs off main thread)
    private func applyDetails(_ d: BatteryDetails) {
        if d.cycleCount        > 0 { cycleCount        = d.cycleCount }
        if d.designCapacity    > 0 { designCapacity    = d.designCapacity }
        if d.currentMaxCapacity > 0 { currentMaxCapacity = d.currentMaxCapacity }
        if d.currentRawCapacity > 0 { currentRawCapacity = d.currentRawCapacity }
        temperature     = d.temperature
        voltage         = d.voltage
        amperage        = d.amperage
        wattage         = abs(d.voltage * d.amperage)
        if d.avgTimeToFull  > 0 { avgTimeToFull  = d.avgTimeToFull  }
        if d.avgTimeToEmpty > 0 { avgTimeToEmpty = d.avgTimeToEmpty }
        batteryNetPower = d.batteryNetPower
        systemLoad      = d.systemLoad
        adapterPowerIn  = d.adapterPowerIn
        adapterWatts    = d.adapterWatts
        adapterName     = d.adapterName
        if !d.manufacturer.isEmpty { manufacturer = d.manufacturer }
        if d.healthPercent > 0 {
            // Exact value from system_profiler — always matches macOS System Information
            health = Double(d.healthPercent)
        } else if d.designCapacity > 0 && d.currentMaxCapacity > 0 {
            // Fallback: NominalChargeCapacity / DesignCapacity
            health = min(100.0, floor(Double(d.currentMaxCapacity) / Double(d.designCapacity) * 100.0))
        }
        healthStatus = health >= 80 ? .good : health >= 60 ? .fair : .poor
        if d.isChargingKnown { isCharging = d.isCharging }
    }



    // MARK: - Mode & Limit
    func setMode(_ mode: ChargeMode) {
        currentMode = mode
        chargeLimit = mode.limitPercentage
        minCharge   = max(20, chargeLimit - 5)
        saveSettings()
    }

    func setCustomLimit(_ limit: Int) {
        chargeLimit = max(20, min(100, limit))
        minCharge   = max(20, chargeLimit - 5)
        saveSettings()
    }

    /// Enables the charge limit. Opens SMC on first use (no admin prompt needed).
    func applyChargeLimit() {
        Task { @MainActor in
            let ready = await ChargeLimitManager.shared.ensureSetup()
            guard ready else {
                chargeLimitStatus = ChargeLimitManager.shared.setupStatus
                return
            }
            isLimitEnabled = true
            chargeLimitStatus = "Limit active at \(chargeLimit)%"
            isSetupComplete = true
            saveSettings()
            // Immediately enforce, then start event-driven loop
            ChargeLimitManager.shared.enforceLimit(
                chargeLimit,
                currentPct: percentage,
                isCurrentlyCharging: isCharging
            )
            ChargeLimitManager.shared.startEnforcement(maxCharge: chargeLimit)
        }
    }

    func removeChargeLimit() {
        isLimitEnabled = false
        chargeLimitStatus = "No limit"
        saveSettings()
        ChargeLimitManager.shared.stopEnforcement()
        ChargeLimitManager.shared.enableCharging()
    }

    // MARK: - Discharge
    func startDischargeToTarget(_ target: Int) {
        // target is always chargeLimit — ignore param, use chargeLimit directly
        let target = chargeLimit
        guard percentage > target else { return }  // already at or below limit
        Task { @MainActor in
            let ready = await ChargeLimitManager.shared.ensureSetup()
            guard ready else { return }
            ChargeLimitManager.shared.startDischarge(to: target)
            isDischarging = true
            chargeLimitStatus = "Discharging to \(target)%"
            saveSettings()
        }
    }

    func stopDischarge() {
        ChargeLimitManager.shared.stopDischarge()
        isDischarging = false
        chargeLimitStatus = isLimitEnabled ? "Limit active at \(chargeLimit)%" : "No limit"
        saveSettings()
    }

    // MARK: - Persistence
    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let modeRaw = defaults.string(forKey: "chargeMode"),
           let mode = ChargeMode(rawValue: modeRaw) {
            currentMode = mode
        }
        chargeLimit = defaults.integer(forKey: "chargeLimit")
        if chargeLimit == 0 { chargeLimit = 80 }
        minCharge = defaults.integer(forKey: "minCharge")
        if minCharge == 0 { minCharge = max(20, chargeLimit - 5) }
        isLimitEnabled = defaults.bool(forKey: "isLimitEnabled")
        chargeLimitStatus = isLimitEnabled ? "Limit active at \(chargeLimit)%" : "No limit"
        isSetupComplete = ChargeLimitManager.shared.isSetupComplete
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(currentMode.rawValue, forKey: "chargeMode")
        defaults.set(chargeLimit, forKey: "chargeLimit")
        defaults.set(minCharge, forKey: "minCharge")
        defaults.set(isLimitEnabled, forKey: "isLimitEnabled")
    }

    // MARK: - Helpers
    // MARK: - Time Remaining (accurate)
    // Primary source: battery chip's own coulomb counter (AvgTimeToFull / AvgTimeToEmpty)
    // These are the same values macOS itself uses — the gauge chip tracks actual charge flow.
    // Fallback: our own calculation from current mAh delta ÷ live amperage.

    /// Minutes to full charge (only meaningful when charging).
    /// Respects the active charge limit — if limit is set to 80%, calculates
    /// time to reach 80% of currentMaxCapacity, not 100%.
    var computedMinutesToFull: Int {
        guard isCharging, amperage > 0.1, currentMaxCapacity > 0, currentRawCapacity > 0 else { return 0 }

        // Target mAh: charge limit % of the real max capacity
        let targetPct = isLimitEnabled ? chargeLimit : 100
        let targetMah = Int(Double(currentMaxCapacity) * Double(targetPct) / 100.0)

        // Already at or past the target
        if currentRawCapacity >= targetMah { return 0 }

        let remainingMah = Double(targetMah - currentRawCapacity)

        // Use live amperage for most accurate calculation (mA → A conversion)
        let chargingAmps = amperage  // already in Amps from IOKit read
        if chargingAmps > 0.1 {
            return Int((remainingMah / (chargingAmps * 1000.0)) * 60.0)
        }

        // Fallback: use gauge value only when no limit is set (gauge always targets 100%)
        if !isLimitEnabled, avgTimeToFull > 0 { return avgTimeToFull }
        return 0
    }

    /// Minutes of battery remaining (only meaningful when discharging)
    var computedMinutesToEmpty: Int {
        // 1. Prefer gauge value
        if avgTimeToEmpty > 0 { return avgTimeToEmpty }
        // 2. Fallback: currentRaw mAh ÷ discharge current (mA) × 60
        guard !isCharging, amperage < -0.05, currentRawCapacity > 0 else { return 0 }
        return Int((Double(currentRawCapacity) / abs(amperage * 1000.0)) * 60.0)
    }

    /// Returns a short time string for the menu bar, or nil if unavailable/calculating.
    var timeRemainingShort: String? {
        if isCharging {
            let mins = computedMinutesToFull
            guard mins > 0 else { return nil }
            let h = mins / 60, m = mins % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        } else {
            let mins = computedMinutesToEmpty
            guard mins > 0 else { return nil }
            let h = mins / 60, m = mins % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        }
    }

    var timeRemainingString: String {
        if isCharging {
            // At or past limit — not going to charge further
            if isLimitEnabled && percentage >= chargeLimit { return "Limit reached" }
            let mins = computedMinutesToFull
            if mins <= 0 { return "Calculating…" }
            let h = mins / 60, m = mins % 60
            if h > 0 { return "\(h)h \(m)m to full" }
            return "\(m)m to full"
        } else {
            let mins = computedMinutesToEmpty
            if mins <= 0 { return "Calculating…" }
            let h = mins / 60, m = mins % 60
            if h > 0 { return "\(h)h \(m)m remaining" }
            return "\(m)m remaining"
        }
    }

    var temperatureString: String {
        String(format: "%.1f°C", temperature)
    }

    var voltageString: String {
        String(format: "%.2fV", voltage)
    }

    var wattageString: String {
        String(format: "%.1fW", wattage)
    }

    var amperageString: String {
        String(format: "%.2fA", abs(amperage))
    }

    var healthString: String {
        String(format: "%.1f%%", health)
    }
}

// MARK: - BatteryDetails (plain value type — safe to read on any thread)
struct BatteryDetails {
    var cycleCount: Int = 0
    var designCapacity: Int = 0
    var currentMaxCapacity: Int = 0
    var currentRawCapacity: Int = 0
    var temperature: Double = 0
    var voltage: Double = 0
    var amperage: Double = 0
    var avgTimeToFull: Int = 0
    var avgTimeToEmpty: Int = 0
    var batteryNetPower: Double = 0
    var systemLoad: Double = 0
    var adapterPowerIn: Double = 0
    var adapterWatts: Int = 0
    var adapterName: String = ""
    var manufacturer: String = ""
    var isCharging: Bool = false
    var isChargingKnown: Bool = false
    var healthPercent: Int = 0   // from system_profiler; 0 = unavailable

    /// Read all IOKit battery properties. Safe to call on any thread.
    static func read() -> BatteryDetails {
        var d = BatteryDetails()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return d }
        defer { IOObjectRelease(service) }

        func intProp(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
                .map { $0.takeRetainedValue() as? Int } ?? nil
        }
        func boolProp(_ key: String) -> Bool? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
                .map { $0.takeRetainedValue() as? Bool } ?? nil
        }
        func stringProp(_ key: String) -> String? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
                .map { $0.takeRetainedValue() as? String } ?? nil
        }

        d.cycleCount         = intProp("CycleCount") ?? 0
        d.designCapacity     = intProp("DesignCapacity") ?? 0
        // NominalChargeCapacity is what macOS System Information uses for health.
        d.currentMaxCapacity = intProp("NominalChargeCapacity")
                            ?? intProp("AppleRawMaxCapacity")
                            ?? intProp("MaxCapacity")
                            ?? 0
        d.currentRawCapacity = intProp("AppleRawCurrentCapacity") ?? intProp("CurrentCapacity") ?? 0

        // Read health % directly from system_profiler to exactly match macOS System Information
        d.healthPercent = BatteryDetails.readSystemProfilerHealthPercent()
        d.currentRawCapacity = intProp("AppleRawCurrentCapacity") ?? intProp("CurrentCapacity") ?? 0

        if let temp = intProp("Temperature") { d.temperature = Double(temp) / 100.0 }
        if let v    = intProp("Voltage")     { d.voltage     = Double(v)    / 1000.0 }
        if let a    = intProp("Amperage")    { d.amperage    = Double(a)    / 1000.0 }

        let atf = intProp("AvgTimeToFull")  ?? 0
        let ate = intProp("AvgTimeToEmpty") ?? 0
        d.avgTimeToFull  = (atf > 0 && atf < 65535) ? atf : 0
        d.avgTimeToEmpty = (ate > 0 && ate < 65535) ? ate : 0

        if let telemetry = IORegistryEntryCreateCFProperty(
            service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any] {
            // Determine charging from amperage sign (positive = charging)
            let charging = d.amperage > 0
            if let bp = telemetry["BatteryPower"] as? Int {
                d.batteryNetPower = (charging ? 1.0 : -1.0) * Double(bp) / 1000.0
            }
            if let sl = telemetry["SystemLoad"]    as? Int { d.systemLoad    = Double(sl) / 1000.0 }
            if let pi = telemetry["SystemPowerIn"] as? Int { d.adapterPowerIn = Double(pi) / 1000.0 }
        }

        if let adapter = IORegistryEntryCreateCFProperty(
            service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any] {
            d.adapterWatts = adapter["Watts"] as? Int    ?? 0
            d.adapterName  = adapter["Name"]  as? String ?? ""
        }

        d.manufacturer = stringProp("Manufacturer") ?? ""
        if let charging = boolProp("IsCharging") {
            d.isCharging      = charging
            d.isChargingKnown = true
        }
        return d
    }

    /// Parse the health % that macOS System Information shows.
    /// Runs `system_profiler SPPowerDataType -xml` and extracts
    /// `sppower_battery_health_maximum_capacity` (e.g. "93%" → 93).
    /// Cached for 60 s to avoid re-running system_profiler on every refresh.
    private static var cachedHealthPercent: Int = 0
    private static var healthCacheTime: Date = .distantPast

    static func readSystemProfilerHealthPercent() -> Int {
        let now = Date()
        if cachedHealthPercent > 0 && now.timeIntervalSince(healthCacheTime) < 60 {
            return cachedHealthPercent
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPPowerDataType", "-xml"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch { return cachedHealthPercent }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let xml = String(data: data, encoding: .utf8) else { return cachedHealthPercent }
        // Look for `sppower_battery_health_maximum_capacity` followed by a string like "93%"
        if let keyRange = xml.range(of: "sppower_battery_health_maximum_capacity") {
            let after = xml[keyRange.upperBound...]
            if let strStart = after.range(of: "<string>"),
               let strEnd   = after.range(of: "</string>") {
                let raw = String(after[strStart.upperBound..<strEnd.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "%", with: "")
                if let pct = Int(raw), pct > 0 {
                    cachedHealthPercent = pct
                    healthCacheTime = now
                    return pct
                }
            }
        }
        return cachedHealthPercent
    }
}
