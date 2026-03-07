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

## Install

### Option 1 — DMG (recommended, no Terminal needed)

1. Download `Batty.dmg` from [Releases](https://github.com/aliadelelroby/Batty/releases)
2. Open the DMG and drag **Batty** to your **Applications** folder
3. Launch Batty from Applications — it will appear in the menu bar
4. On first launch, Batty shows a setup screen — click **Grant Permission** and enter your admin password once
5. Done. Open the menu bar icon → **Settings** → set your limit → tap **Apply**

### Option 2 — Build from source

```bash
git clone https://github.com/aliadelelroby/Batty.git
cd Batty
bash install.sh
```

The installer builds a release binary, creates the app bundle at `/Applications/Batty.app`, and handles the one-time sudoers setup.

---

## How the charge limit works

Batty writes Apple SMC keys using a bundled `smc` binary with passwordless `sudo`. A one-time admin password is required during first launch (or install) to write `/etc/sudoers.d/batty`. After that, no further prompts ever appear.

| SMC key | Type  | OFF (limit active) | ON (normal)   | Purpose                                  |
| ------- | ----- | ------------------ | ------------- | ---------------------------------------- |
| `CHTE`  | ui32  | `01 00 00 00`      | `00 00 00 00` | Disable/enable charging                  |
| `CHIE`  | hex\_ | `08`               | `00`          | Disable/enable adapter (force discharge) |

Enforcement fires on every 1% battery change via `notify_register_dispatch("com.apple.system.powersources.percent")` — no polling.

**Hysteresis:** charging is disabled at the limit (e.g. 80%) and re-enabled 5% below it (e.g. 75%), preventing rapid on/off cycling.

---

## Requirements

- Apple Silicon MacBook (M1 / M2 / M3 / M4)
- macOS 13 Ventura or later
- No Apple Developer account needed

---

## Uninstall

```bash
sudo rm /etc/sudoers.d/batty
sudo rm -rf /Applications/Batty.app
```

---

## Building the DMG

```bash
bash make-dmg.sh
# Output: dist/Batty.dmg
```

Requires only Xcode Command Line Tools (`xcode-select --install`). No external tools needed.

---

## Project structure

```
Sources/
  Batty/
    BattyApp.swift           — @main entry point
    AppDelegate.swift        — NSStatusItem, popover, timer, notifications
    BatteryMonitor.swift     — IOKit battery reads, charge limit logic, persistence
    ChargeLimitManager.swift — SMC writes via sudo smc, sleep/wake, enforcement loop
    OnboardingWindow.swift   — First-launch setup window (welcome → permission → done)
    ContentView.swift        — Tab container with sliding animation and glass tab bar
    OverviewTab.swift        — Hero percentage, stats, progress bar, limit strip
    DetailsTab.swift         — All battery detail rows
    SettingsTab.swift        — Limit slider, mode presets, discharge, menu bar prefs
    Resources/
      smc                    — Bundled SMC CLI binary (arm64)
install.sh                   — Developer one-command installer (builds + bundles + sudoers)
make-dmg.sh                  — Builds a distributable Batty.dmg
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

MIT — see [LICENSE](LICENSE).
