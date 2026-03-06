# Batty

A minimal macOS menu bar app that enforces real hardware charge limits on Apple Silicon MacBooks — no Xcode, no Apple Developer account, no subscription.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-black) ![License MIT](https://img.shields.io/badge/license-MIT-black)

---

## What it does

- **Hard charge limit** — writes the `CHTE` SMC key directly so charging stops at your chosen percentage (e.g. 80%), even if the charger stays plugged in
- **Controlled discharge** — disables the adapter via the `CHIE` SMC key so the battery drains while plugged in, down to the charge limit; useful when you accidentally charged past your limit
- **Battery health details** — cycle count, capacity, temperature, voltage, current, system load, adapter wattage
- **Menu bar display** — battery icon, percentage, time remaining (all optional)
- **Launch at login** — via `SMAppService`
- **Low battery notifications** — at 20% and 10%
- **Sleep / wake aware** — restores SMC defaults on sleep, re-applies on wake

All of this runs with no background daemon, no Apple Developer account, and no code signing.

---

## How the charge limit works

Batty writes Apple SMC keys directly using a bundled `smc` binary with passwordless `sudo`. A one-time admin password is required during install to write `/etc/sudoers.d/batty`. After that, no further prompts ever appear.

| SMC key | Type | OFF (limit active) | ON (normal) | Purpose |
|---------|------|--------------------|-------------|---------|
| `CHTE`  | ui32 | `01 00 00 00`      | `00 00 00 00` | Disable/enable charging |
| `CHIE`  | hex_ | `08`               | `00`          | Disable/enable adapter (force discharge) |

Enforcement fires on every 1% battery change via `notify_register_dispatch("com.apple.system.powersources.percent")` — no polling.

**Hysteresis:** charging is disabled at the limit (e.g. 80%) and re-enabled 5% below it (e.g. 75%), preventing rapid on/off cycling.

---

## Requirements

- Apple Silicon MacBook (M1 / M2 / M3 / M4)
- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`)
- No Apple Developer account needed

---

## Install

```bash
git clone https://github.com/aliadelelroby/Batty.git
cd Batty
bash install.sh
```

The installer will:
1. Kill any running instance and wipe the previous install
2. Build a release binary with Swift Package Manager
3. Copy the app bundle to `/Applications/Batty.app`
4. Ask for your admin password **once** to write `/etc/sudoers.d/batty`
5. Run a quick SMC write test to confirm everything works
6. Launch the app

After install, Batty lives in the menu bar. Open it → **Settings** → set your limit → tap **Apply**.

---

## Uninstall

```bash
sudo rm /etc/sudoers.d/batty
sudo rm -rf /Applications/Batty.app
```

---

## Building manually

```bash
swift build -c release
```

The binary is at `.build/release/Batty`. The `smc` binary must be present at `Sources/Batty/Resources/smc` (already included in the repo).

---

## Project structure

```
Sources/
  Batty/
    BattyApp.swift          — @main entry point
    AppDelegate.swift       — NSStatusItem, popover, timer, notifications
    BatteryMonitor.swift    — IOKit battery reads, charge limit logic, persistence
    ChargeLimitManager.swift — SMC writes via sudo smc, sleep/wake, enforcement loop
    ContentView.swift       — Tab container with sliding animation and glass tab bar
    OverviewTab.swift       — Hero percentage, stats, progress bar, limit strip
    DetailsTab.swift        — All battery detail rows
    SettingsTab.swift       — Limit slider, mode presets, discharge, menu bar prefs
    Resources/
      smc                   — Bundled SMC CLI binary (arm64)
install.sh                  — One-command installer
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

MIT — see [LICENSE](LICENSE).
