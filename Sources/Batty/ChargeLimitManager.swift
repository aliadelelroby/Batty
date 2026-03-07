import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import notify
import os.log

// MARK: - ChargeLimitManager
//
// Enforces real hardware charge limits and controlled discharge by writing
// Apple SMC keys via the bundled `smc` binary with passwordless sudo.
//
// First-use setup: installs a sudoers.d entry via one admin dialog so that
// subsequent calls run silently. No ongoing prompts.
//
// Charging key:  CHTE  ui32  ON=[0x00000000]  OFF=[0x01000000]  (M-series Macs)
// Adapter key:   CHIE  hex_  ON=[0x00]         OFF=[0x08]       (disable adapter = force discharge)
//
// Behaviour:
//   • Charge limit: disable charging when % >= maxCharge; re-enable at minCharge (hysteresis)
//   • Discharge:    disable adapter entirely so the machine drains on battery while plugged in;
//                   stops when % <= dischargeTarget, then re-enables adapter + charging
//   • Sleep:        restore safe state before sleep, re-apply on wake
//   • Unplug:       stops discharge if active
//   • App exit:     restore safe state so battery charges normally after quit

@MainActor
final class ChargeLimitManager: ObservableObject {

    static let shared = ChargeLimitManager()

    // MARK: - Published state
    @Published var isSetupComplete: Bool = false
    @Published var setupStatus: String = ""
    @Published var isSettingUp: Bool = false

    // Discharge state
    @Published var isDischarging: Bool = false
    @Published var dischargeTarget: Int = 20

    // MARK: - Private state
    private let hysteresis = 5
    // Kept in sync by BatteryMonitor.applyChargeLimit()
    var limitMaxCharge: Int = 80

    // notify tokens
    private var notifyToken: Int32 = NOTIFY_TOKEN_INVALID
    private var powerToken: Int32  = NOTIFY_TOKEN_INVALID

    // IOKit sleep/wake
    private var sleepWakePort: io_connect_t = IO_OBJECT_NULL
    private var sleepNotifyPortRef: IONotificationPortRef? = nil
    private var sleepNotifier: io_object_t = IO_OBJECT_NULL

    private static let kIOMessageCanSystemSleep:     UInt32 = 0xe0000270
    private static let kIOMessageSystemWillSleep:    UInt32 = 0xe0000280
    private static let kIOMessageSystemHasPoweredOn: UInt32 = 0xe0000300

    // Path to bundled smc binary
    private static var smcPath: String {
        // Running from app bundle
        if let res = Bundle.main.resourcePath {
            let p = res + "/smc"
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        // Running from swift build .build/release
        let devPath = Bundle.main.bundlePath + "/../../Resources/smc"
        if FileManager.default.fileExists(atPath: devPath) { return devPath }
        // Fallback: same dir as executable
        let execDir = (Bundle.main.executablePath ?? "").components(separatedBy: "/").dropLast().joined(separator: "/")
        return execDir + "/smc"
    }

    // Sudoers file we install
    private static let sudoersPath = "/etc/sudoers.d/batty"

    // MARK: - Init
    private init() {
        // Check if sudoers already installed → we can operate without prompts
        isSetupComplete = isSudoersInstalled()
        setupStatus = isSetupComplete ? "Ready" : "Needs one-time setup"
        registerSleepWake()
    }

    deinit {
        if notifyToken != NOTIFY_TOKEN_INVALID { notify_cancel(notifyToken) }
        if powerToken  != NOTIFY_TOKEN_INVALID { notify_cancel(powerToken)  }
        if sleepWakePort != IO_OBJECT_NULL {
            var notifier = sleepNotifier
            IODeregisterForSystemPower(&notifier)
            IOServiceClose(sleepWakePort)
            if let portRef = sleepNotifyPortRef { IONotificationPortDestroy(portRef) }
        }
    }

    // MARK: - Public API

    func ensureSetup() async -> Bool {
        if isSetupComplete { return true }
        isSettingUp = true
        defer { isSettingUp = false }

        let ok = await installSudoers()
        if ok {
            isSetupComplete = true
            setupStatus = "Ready"
        } else {
            setupStatus = "Setup cancelled or failed"
        }
        return ok
    }

    func startEnforcement(maxCharge: Int? = nil) {
        guard isSetupComplete else { return }
        if let max = maxCharge { limitMaxCharge = max }
        startPercentLoop()
        startPowerLoop()
    }

    func stopEnforcement() {
        stopPercentLoop()
        // Also stop the plug/unplug loop — otherwise replug would restart enforcement
        if powerToken != NOTIFY_TOKEN_INVALID {
            notify_cancel(powerToken)
            powerToken = NOTIFY_TOKEN_INVALID
        }
    }

    func enforceLimit(_ maxCharge: Int, currentPct: Int, isCurrentlyCharging: Bool) {
        guard isSetupComplete, !isDischarging else { return }
        let minCharge = max(20, maxCharge - hysteresis)
        if currentPct >= maxCharge {
            // At or above limit — turn off charging regardless of current state
            if isCurrentlyCharging { disableCharging() }
        } else if currentPct < minCharge {
            // Below hysteresis floor — always re-enable charging
            if !isCurrentlyCharging { enableCharging() }
        }
        // Between minCharge and maxCharge: do nothing — respect whatever state charging is in.
        // (Charging was explicitly disabled at the limit; it stays off until hysteresis kicks in.)
    }

    func enableCharging() {
        guard isSetupComplete else { return }
        smcWrite(key: "CHTE", value: "00000000")
    }

    func disableCharging() {
        guard isSetupComplete else { return }
        smcWrite(key: "CHTE", value: "01000000")
    }

    func startDischarge(to target: Int) {
        guard isSetupComplete else { return }
        dischargeTarget = max(5, min(99, target))
        isDischarging = true
        disableCharging()
        smcWrite(key: "CHIE", value: "08")          // disable adapter → force discharge
        startEnforcement()
    }

    func stopDischarge() {
        isDischarging = false
        guard isSetupComplete else { return }
        smcWrite(key: "CHIE", value: "00")          // re-enable adapter
        enableCharging()
    }

    func restoreDefaults() {
        guard isSetupComplete else { return }
        smcWrite(key: "CHIE", value: "00")
        smcWrite(key: "CHTE", value: "00000000")
    }

    // MARK: - Sudoers installation

    private func isSudoersInstalled() -> Bool {
        guard FileManager.default.fileExists(atPath: Self.sudoersPath) else { return false }
        guard let content = try? String(contentsOfFile: Self.sudoersPath, encoding: .utf8) else { return false }
        // Verify it covers both our smc binary and pmset
        return content.contains(Self.smcPath) && content.contains("/usr/bin/pmset")
    }

    private func installSudoers() async -> Bool {
        let smc = Self.smcPath
        guard FileManager.default.fileExists(atPath: smc) else {
            setupStatus = "smc binary not found at \(smc)"
            return false
        }

        // sudoers line: allow current user to run our smc binary with sudo, no password
        guard let username = ProcessInfo.processInfo.environment["USER"], !username.isEmpty else {
            setupStatus = "Could not determine username"
            return false
        }

        let sudoersLine = "\(username) ALL=(ALL) NOPASSWD: \(smc) *, /usr/bin/pmset *\n"
        let sudoersFile = Self.sudoersPath

        // We need to write to /etc/sudoers.d/ which requires root.
        // Use osascript with administrator privileges — one-time dialog.
        let escapedFile = sudoersFile
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Write to a temp file first, then move it into sudoers.d with admin
        let tmpFile = NSTemporaryDirectory() + "batty_sudoers_\(Int.random(in: 10000...99999))"

        do {
            try sudoersLine.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        } catch {
            setupStatus = "Failed to write temp file: \(error)"
            return false
        }
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        // osascript to move temp file into /etc/sudoers.d/ with correct permissions
        let script = """
        do shell script "cp '\(tmpFile)' '\(escapedFile)' && chmod 440 '\(escapedFile)'" with administrator privileges
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                DispatchQueue.main.async {
                    if error != nil {
                        continuation.resume(returning: false)
                    } else {
                        continuation.resume(returning: true)
                    }
                }
            }
        }
    }

    // MARK: - SMC write via subprocess

    // Fire-and-forget: dispatches to a background thread so we never block the main actor.
    private func smcWrite(key: String, value: String) {
        let smc = Self.smcPath
        guard FileManager.default.fileExists(atPath: smc) else {
            os_log("Batty: smc binary not found at %{public}@", smc)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath     = "/usr/bin/sudo"
            task.arguments      = [smc, "-k", key, "-w", value]
            task.standardOutput = FileHandle.nullDevice
            task.standardError  = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    os_log("Batty: smc write %{public}@ = %{public}@ failed (exit %d)",
                           key, value, task.terminationStatus)
                }
            } catch {
                os_log("Batty: smc process error: %{public}@", error.localizedDescription)
            }
        }
    }

    // MARK: - Sleep / Wake

    private func registerSleepWake() {
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let callback: IOServiceInterestCallback = { refCon, _, messageType, messageArg in
            guard let refCon else { return }
            let manager = Unmanaged<ChargeLimitManager>.fromOpaque(refCon).takeUnretainedValue()
            switch messageType {
            case ChargeLimitManager.kIOMessageCanSystemSleep:
                IOAllowPowerChange(manager.sleepWakePort, Int(bitPattern: messageArg))
            case ChargeLimitManager.kIOMessageSystemWillSleep:
                Task { @MainActor in manager.handleWillSleep() }
                IOAllowPowerChange(manager.sleepWakePort, Int(bitPattern: messageArg))
            case ChargeLimitManager.kIOMessageSystemHasPoweredOn:
                Task { @MainActor in manager.handleWake() }
            default:
                break
            }
        }

        sleepWakePort = IORegisterForSystemPower(selfPtr, &sleepNotifyPortRef, callback, &sleepNotifier)
        if sleepWakePort != IO_OBJECT_NULL, let portRef = sleepNotifyPortRef {
            IONotificationPortSetDispatchQueue(portRef, DispatchQueue.main)
        } else {
            Unmanaged<ChargeLimitManager>.fromOpaque(selfPtr).release()
        }
    }

    private func handleWillSleep() {
        // Stop the notify loops — the SMC key state persists through sleep,
        // so we intentionally leave CHTE/CHIE as-is. Re-enabling charging here
        // would let the battery charge past the limit overnight.
        os_log("Batty: sleep — pausing enforcement loops (SMC state preserved)")
        stopPercentLoop()
        if powerToken != NOTIFY_TOKEN_INVALID {
            notify_cancel(powerToken)
            powerToken = NOTIFY_TOKEN_INVALID
        }
    }

    private func handleWake() {
        os_log("Batty: wake — re-applying settings")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.reapplyAfterWake() }
        }
    }

    private func reapplyAfterWake() {
        guard isSetupComplete else { return }

        // Read current % and charging state fresh from IOPowerSources
        var pct = 100
        var isCurrentlyCharging = false
        var isConnected = false
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources  = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for src in sources {
                if let info = IOPSGetPowerSourceDescription(snapshot, src)?.takeUnretainedValue() as? [String: Any],
                   let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                    pct                = info[kIOPSCurrentCapacityKey] as? Int ?? 100
                    isCurrentlyCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
                    isConnected        = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                    break
                }
            }
        }

        if isDischarging {
            if pct <= dischargeTarget {
                stopDischarge()
            } else {
                disableCharging()
                smcWrite(key: "CHIE", value: "08")
                startEnforcement()
            }
        } else {
            // Immediately re-enforce in case battery charged past limit during sleep
            enforceLimit(limitMaxCharge, currentPct: pct, isCurrentlyCharging: isCurrentlyCharging)
            // Restart event loops (only needed when plugged in)
            if isConnected {
                startEnforcement()
            }
        }
    }

    // MARK: - Plug / Unplug

    private func startPowerLoop() {
        guard powerToken == NOTIFY_TOKEN_INVALID else { return }
        var token: Int32 = NOTIFY_TOKEN_INVALID
        let status = notify_register_dispatch(
            "com.apple.system.powersources.limitedpower",
            &token, DispatchQueue.main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handlePowerSourceChange() }
        }
        if status == NOTIFY_STATUS_OK { powerToken = token }
    }

    private func handlePowerSourceChange() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources  = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        var connected = false
        for src in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, src)?.takeUnretainedValue() as? [String: Any],
               let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                connected = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                break
            }
        }

        if !connected {
            if isDischarging {
                isDischarging = false
                enableCharging()
                os_log("Batty: unplugged during discharge — cancelled")
            }
            stopPercentLoop()
        } else {
            startPercentLoop()
        }
    }

    // MARK: - notify % change

    private func startPercentLoop() {
        guard isSetupComplete, notifyToken == NOTIFY_TOKEN_INVALID else { return }
        var token: Int32 = NOTIFY_TOKEN_INVALID
        let status = notify_register_dispatch(
            "com.apple.system.powersources.percent",
            &token, DispatchQueue.main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handlePercentChange() }
        }
        if status == NOTIFY_STATUS_OK { notifyToken = token }
    }

    private func stopPercentLoop() {
        if notifyToken != NOTIFY_TOKEN_INVALID {
            notify_cancel(notifyToken)
            notifyToken = NOTIFY_TOKEN_INVALID
        }
    }

    private func handlePercentChange() {
        // Single IOPowerSources read — extract both percent AND charging state together
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources  = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        var pct: Int? = nil
        var isCharging = false
        for src in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, src)?.takeUnretainedValue() as? [String: Any],
               let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                pct        = info[kIOPSCurrentCapacityKey] as? Int
                isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
                break
            }
        }
        guard let pct else { return }

        if isDischarging {
            if pct <= dischargeTarget {
                os_log("Batty: discharge target reached at %d%%", pct)
                stopDischarge()
            }
            return
        }

        enforceLimit(limitMaxCharge, currentPct: pct, isCurrentlyCharging: isCharging)
    }
}
