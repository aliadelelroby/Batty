import AppKit
import SwiftUI
import IOKit.ps
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var batteryMonitor = BatteryMonitor()
    private var updateTimer: Timer?
    // Track previous state for charging change detection
    private var wasCharging: Bool = false
    private var lastNotifiedPercentage: Int = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestNotificationPermission()
        setupStatusItem()
        setupPopover()
        startUpdateTimer()
        registerPowerSourceNotification()
        registerSleepWakeObservers()
        // Re-render menu bar whenever prefs change
        NotificationCenter.default.addObserver(
            forName: .menuBarPrefsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateMenuBarIcon() }
        }
        // Show onboarding on first run (sudoers not yet installed)
        if !ChargeLimitManager.shared.isSetupComplete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                OnboardingWindowController.shared.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restore SMC to safe defaults so battery charges normally after quit
        ChargeLimitManager.shared.restoreDefaults()
    }

    // MARK: - Sleep / Wake (AppDelegate side — timer + UI)

    private func registerSleepWakeObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWillSleep() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDidWake() }
        }
    }

    private func handleWillSleep() {
        // Pause the polling timer while sleeping — ChargeLimitManager handles SMC
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func handleDidWake() {
        // Give the OS ~1 second to settle power sources after wake
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.batteryMonitor.refresh()
                self.updateMenuBarIcon()
                self.checkThresholdNotifications()
                self.startUpdateTimer()   // restart the polling timer
            }
        }
    }

    // MARK: - Notification Permission
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Power Source Notification (real-time plug/unplug)
    private var powerSourceRunLoopSource: CFRunLoopSource?

    private func registerPowerSourceNotification() {
        let context = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(self).toOpaque()
        )
        powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in
                delegate.powerSourceChanged()
            }
        }, context)?.takeRetainedValue()

        if let source = powerSourceRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func powerSourceChanged() {
        let prevCharging = batteryMonitor.isCharging
        batteryMonitor.refresh()
        updateMenuBarIcon()

        let nowCharging = batteryMonitor.isCharging

        // Haptic + notification on plug/unplug
        if !prevCharging && nowCharging {
            performHaptic(.levelChange)
            scheduleNotification(
                title: "Plugged in",
                body: "Charging from \(batteryMonitor.percentage)%"
            )
        } else if prevCharging && !nowCharging {
            performHaptic(.levelChange)
            scheduleNotification(
                title: "Unplugged",
                body: "\(batteryMonitor.percentage)% · \(batteryMonitor.timeRemainingString)"
            )
        }
        wasCharging = nowCharging
    }

    // MARK: - Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateMenuBarIcon()
        }
    }

    // MARK: - Popover
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 480)
        popover?.behavior = .transient
        popover?.animates = true
        let contentView = ContentView().environmentObject(batteryMonitor)
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    // MARK: - Update Timer
    // 60-second heartbeat — only to catch drift/edge cases.
    // Real-time updates are driven by IOPSNotificationCreateRunLoopSource (plug/unplug/% change).
    private func startUpdateTimer() {
        guard updateTimer == nil else { return }   // don't double-schedule
        wasCharging = batteryMonitor.isCharging
        batteryMonitor.refresh()
        updateMenuBarIcon()
        checkThresholdNotifications()

        updateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.batteryMonitor.refresh()
                self?.updateMenuBarIcon()
                self?.checkThresholdNotifications()
            }
        }
        updateTimer?.tolerance = 10.0  // allow OS to coalesce wake-ups with other timers
    }

    // MARK: - Menu Bar Icon
    func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let pct       = batteryMonitor.percentage
        let charging  = batteryMonitor.isCharging
        let connected = batteryMonitor.isConnected
        let defaults  = UserDefaults.standard

        let showIcon       = defaults.object(forKey: "menuBarShowIcon")       as? Bool ?? true
        let showPct        = defaults.object(forKey: "menuBarShowPercentage") as? Bool ?? true
        let boltCharging   = defaults.object(forKey: "menuBarBoltWhenCharging") as? Bool ?? true
        let showTime       = defaults.object(forKey: "menuBarShowTime")       as? Bool ?? false

        // Consider "limit reached" as not-actively-charging for icon/time purposes
        let limitEnabled   = defaults.object(forKey: "isLimitEnabled") as? Bool
                             ?? batteryMonitor.isLimitEnabled
        let chargeLimit    = defaults.integer(forKey: "chargeLimit")
        let effectiveLimit = chargeLimit > 0 ? chargeLimit : 80
        let limitReached   = limitEnabled && pct >= effectiveLimit
        let activelyCharging = charging && !limitReached

        // Icon
        if showIcon {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let iconName: String
            if activelyCharging && boltCharging {
                iconName = "bolt.fill"
            } else if connected {
                iconName = "powerplug"
            } else if pct > 75 {
                iconName = "battery.100"
            } else if pct > 50 {
                iconName = "battery.75"
            } else if pct > 25 {
                iconName = "battery.50"
            } else if pct > 10 {
                iconName = "battery.25"
            } else {
                iconName = "battery.0"
            }
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig)
            button.imagePosition = (showPct || showTime) ? .imageLeft : .imageOnly
        } else {
            button.image = nil
        }

        // Text: percentage and/or time remaining
        var parts: [String] = []
        if showPct  { parts.append("\(pct)%") }
        if showTime, let timeStr = batteryMonitor.timeRemainingShort { parts.append(timeStr) }

        if parts.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
        } else {
            let titleStr = " " + parts.joined(separator: "  ")
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            button.attributedTitle = NSAttributedString(string: titleStr, attributes: attrs)
        }
    }

    // MARK: - Threshold Notifications (20%, 10%)
    private func checkThresholdNotifications() {
        let pct = batteryMonitor.percentage
        guard !batteryMonitor.isCharging else {
            lastNotifiedPercentage = -1
            return
        }
        if pct <= 10 && lastNotifiedPercentage != 10 {
            lastNotifiedPercentage = 10
            performHaptic(.generic)
            scheduleNotification(title: "Low Battery", body: "\(pct)% · \(batteryMonitor.timeRemainingString)")
        } else if pct <= 20 && lastNotifiedPercentage != 20 && lastNotifiedPercentage != 10 {
            lastNotifiedPercentage = 20
            scheduleNotification(title: "Battery Getting Low", body: "\(pct)% remaining")
        }
    }

    // MARK: - Haptic
    private func performHaptic(_ type: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(type, performanceTime: .default)
    }

    // MARK: - User Notifications
    private func scheduleNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .none

        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - Toggle Popover
    @objc func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Haptic on open
            performHaptic(.alignment)
            batteryMonitor.refresh()
            updateMenuBarIcon()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}


