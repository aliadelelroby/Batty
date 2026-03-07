import Foundation
import os.log

// MARK: - PowerManager
//
// Reads and writes macOS power management settings via pmset.
// Requires the sudoers entry installed by ChargeLimitManager (which includes
// /usr/bin/pmset after setup).
//
// Settings are read-parsed from `pmset -g custom` and written via
// `sudo pmset [-b | -c | -a] KEY VALUE`.
//
// Profiles:
//   -b  battery power only
//   -c  AC power only
//   -a  both

@MainActor
final class PowerManager: ObservableObject {

    static let shared = PowerManager()

    // MARK: - Published state

    // Low Power Mode (per-source)
    @Published var lowPowerModeBattery: Bool = false
    @Published var lowPowerModeAC: Bool = false

    // High Power Mode (AC only — M-Pro/Max chips)
    @Published var highPowerModeAC: Bool = false

    // Power Nap (background fetch while asleep)
    @Published var powerNapBattery: Bool = true
    @Published var powerNapAC: Bool = true

    // Display sleep (minutes, 0 = never)
    @Published var displaySleepBattery: Int = 2
    @Published var displaySleepAC: Int = 10

    // System sleep (minutes, 0 = never)
    @Published var systemSleepBattery: Int = 1
    @Published var systemSleepAC: Int = 1


    // MARK: - Init
    private init() {
        refresh()
    }

    // MARK: - Read

    func refresh() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let output = runCommand("/usr/bin/pmset", args: ["-g", "custom"]) ?? ""
            await MainActor.run {
                self?.parse(output)
            }
        }
    }

    private func parse(_ output: String) {
        var inBattery = false
        var inAC = false

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Battery Power") { inBattery = true; inAC = false; continue }
            if trimmed.hasPrefix("AC Power")      { inAC = true; inBattery = false; continue }

            func intVal(_ key: String) -> Int? {
                guard trimmed.hasPrefix(key) else { return nil }
                let rest = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
                return Int(rest.components(separatedBy: .whitespaces).first ?? "")
            }

            if let v = intVal("lowpowermode") {
                if inBattery { lowPowerModeBattery = v != 0 }
                if inAC      { lowPowerModeAC      = v != 0 }
            }
            if let v = intVal("powermode") {
                // powermode 2 = high power, 0 = normal
                if inAC { highPowerModeAC = v == 2 }
            }
            if let v = intVal("powernap") {
                if inBattery { powerNapBattery = v != 0 }
                if inAC      { powerNapAC      = v != 0 }
            }
            if let v = intVal("displaysleep") {
                if inBattery { displaySleepBattery = v }
                if inAC      { displaySleepAC      = v }
            }
            if let v = intVal("sleep") {
                if inBattery { systemSleepBattery = v }
                if inAC      { systemSleepAC      = v }
            }
        }
    }

    // MARK: - Write helpers

    func setLowPowerMode(_ on: Bool, source: Source) {
        pmset(source, key: "lowpowermode", value: on ? "1" : "0")
        switch source {
        case .battery: lowPowerModeBattery = on
        case .ac:      lowPowerModeAC = on
        case .all:     lowPowerModeBattery = on; lowPowerModeAC = on
        }
    }

    func setHighPowerMode(_ on: Bool) {
        // High power mode is AC-only; powermode 2 = high, 0 = automatic
        pmset(.ac, key: "powermode", value: on ? "2" : "0")
        highPowerModeAC = on
        // Mutually exclusive with low power on AC
        if on { lowPowerModeAC = false }
    }

    func setPowerNap(_ on: Bool, source: Source) {
        pmset(source, key: "powernap", value: on ? "1" : "0")
        switch source {
        case .battery: powerNapBattery = on
        case .ac:      powerNapAC = on
        case .all:     powerNapBattery = on; powerNapAC = on
        }
    }

    func setDisplaySleep(_ minutes: Int, source: Source) {
        pmset(source, key: "displaysleep", value: "\(minutes)")
        switch source {
        case .battery: displaySleepBattery = minutes
        case .ac:      displaySleepAC = minutes
        case .all:     displaySleepBattery = minutes; displaySleepAC = minutes
        }
    }

    func setSystemSleep(_ minutes: Int, source: Source) {
        pmset(source, key: "sleep", value: "\(minutes)")
        switch source {
        case .battery: systemSleepBattery = minutes
        case .ac:      systemSleepAC      = minutes
        case .all:     systemSleepBattery = minutes; systemSleepAC = minutes
        }
    }

    // MARK: - Source enum

    enum Source {
        case battery, ac, all
        var flag: String {
            switch self {
            case .battery: return "-b"
            case .ac:      return "-c"
            case .all:     return "-a"
            }
        }
    }

    // MARK: - pmset write (sudo)

    private func pmset(_ source: Source, key: String, value: String) {
        guard ChargeLimitManager.shared.isSetupComplete else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/usr/bin/sudo"
            task.arguments  = ["/usr/bin/pmset", source.flag, key, value]
            task.standardOutput = FileHandle.nullDevice
            task.standardError  = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    os_log("Batty: pmset %{public}@ %{public}@ %{public}@ failed (exit %d)",
                           source.flag, key, value, task.terminationStatus)
                }
            } catch {
                os_log("Batty: pmset error: %{public}@", error.localizedDescription)
            }
        }
    }
}

// MARK: - Helpers

private func runCommand(_ path: String, args: [String]) -> String? {
    let task = Process()
    task.launchPath = path
    task.arguments  = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError  = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    } catch {
        return nil
    }
}
