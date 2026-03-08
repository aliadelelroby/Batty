# Batty

Batty is a native macOS menu bar app for Apple Silicon MacBooks that applies real hardware charge limits, lets you discharge while still plugged in, and surfaces useful battery and power details in one lightweight UI.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-black) ![License MIT](https://img.shields.io/badge/license-MIT-black)

## Why Batty

macOS offers Optimized Battery Charging, but it does not let you choose your own hard ceiling or manually bring an overcharged battery back down while the charger stays connected. Batty fills that gap.

- Set a hardware-backed charge cap such as `80%`
- Force a controlled discharge back down to your target while remaining plugged in
- See cycle count, health, temperature, voltage, amperage, adapter wattage, and more
- Configure menu bar display, low battery alerts, and launch at login
- Adjust power-related settings like Low Power Mode, High Power Mode, and Power Nap from the same app

Batty runs as a regular app with a bundled helper binary. It does not require an Apple Developer account, Xcode project setup, or a subscription.

## Features

- **Hard charge limit** - writes the `CHTE` SMC key so charging stops at your chosen percentage, even if the charger stays connected
- **Controlled discharge** - writes the `CHIE` SMC key so the battery can drain while plugged in until it reaches your configured target
- **Battery details** - shows cycle count, capacity, temperature, voltage, current, system load, and adapter wattage
- **Menu bar controls** - optional battery icon, percentage, charging bolt, and time remaining
- **Power settings** - manages Low Power Mode, High Power Mode, and Power Nap based on the current power source
- **Wake-aware enforcement** - restores defaults during sleep and reapplies limits after wake
- **One-time setup** - asks for admin authentication once, then reuses the installed sudoers rule for future SMC access

## Requirements

- Apple Silicon MacBook
- macOS 13 Ventura or later
- Administrator access once during setup

## Install

### Option 1 - Download the DMG

1. Download `Batty.dmg` from [Releases](https://github.com/aliadelelroby/Batty/releases).
2. Open the DMG and drag `Batty.app` into `/Applications`.
3. Launch Batty from Applications.
4. On first launch, use the onboarding flow to grant permission when prompted.
5. Open Batty in the menu bar, choose your charge limit, then click `Apply`.

### Option 2 - Build and install from source

```bash
git clone https://github.com/aliadelelroby/Batty.git
cd Batty
bash install.sh
```

The installer:

- stops and removes any previous Batty install
- builds the app in release mode with SwiftPM
- creates `/Applications/Batty.app`
- installs `/etc/sudoers.d/batty`
- verifies the bundled `smc` binary can be invoked with passwordless `sudo`
- launches Batty when setup completes

## How it works

Batty uses a bundled `smc` binary and a one-time sudoers entry to write Apple SMC keys directly. During setup, it installs a rule in `/etc/sudoers.d/batty` so the app can perform future SMC operations without repeatedly asking for your password.

| SMC key | Type | Limit active | Normal | Purpose |
| ------- | ---- | ------------ | ------ | ------- |
| `CHTE` | `ui32` | `01 00 00 00` | `00 00 00 00` | Disable or enable charging |
| `CHIE` | `hex_` | `08` | `00` | Disable or enable the adapter for forced discharge |

Enforcement listens for battery percentage updates through `notify_register_dispatch("com.apple.system.powersources.percent")`, so Batty reacts to 1% changes instead of polling constantly.

Batty also applies hysteresis: charging turns off at the selected limit and turns back on 5% below it, which helps avoid rapid toggling near the threshold.

## Safety notes

- Batty is intended for Apple Silicon MacBooks only.
- The app modifies charging behavior through undocumented SMC keys.
- A full shutdown or reboot can reset platform charging state before Batty starts again.
- If your battery is already above the selected cap, use `Discharge` to bring it back down while plugged in.

## Uninstall

```bash
sudo rm /etc/sudoers.d/batty
sudo rm -rf /Applications/Batty.app
```

If you installed from source, that fully removes the app bundle and the sudoers rule.

## Build the DMG

```bash
bash make-dmg.sh
```

Output:

```text
dist/Batty.dmg
```

Requirements:

- Xcode Command Line Tools via `xcode-select --install`
- built-in macOS `hdiutil`

## Project structure

```text
Sources/
  Batty/
    BattyApp.swift           - App entry point
    AppDelegate.swift        - Status item, popover, timers, notifications
    BatteryMonitor.swift     - Battery reads, charge logic, persistence
    ChargeLimitManager.swift - SMC access, setup flow, enforcement
    ContentView.swift        - Main tab container
    OverviewTab.swift        - Primary battery overview UI
    DetailsTab.swift         - Detailed battery metrics
    SettingsTab.swift        - Charge, discharge, menu bar, and power settings
    OnboardingWindow.swift   - First-launch permission flow
    Resources/
      smc                    - Bundled arm64 SMC command-line helper
install.sh                   - Local installer for source builds
make-dmg.sh                  - DMG packaging script
Package.swift                - Swift package definition
```

## Contributing

See `CONTRIBUTING.md`.

## License

MIT. See `LICENSE`.
