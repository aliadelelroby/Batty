# Contributing to Batty

Thanks for your interest. Batty is a small, focused app — contributions that keep it simple and maintainable are most welcome.

## Ground rules

- No Xcode project files — SPM only
- No Apple Developer account / no code signing / no notarization required to build or run
- No external dependencies — pure Swift, IOKit, AppKit, SwiftUI
- Keep the UI monochrome: `Color.primary` with opacity variations only, no accent colors
- Format code with the existing style (4-space indentation, `// MARK: -` sections)

## How to contribute

1. Fork the repo and create a branch: `git checkout -b my-feature`
2. Make your changes and verify the build: `swift build -c release`
3. Test manually by running `bash install.sh`
4. Open a pull request with a clear description of what and why

## What's welcome

- Bug fixes
- Support for Intel Macs (different SMC keys — `CH0C` for charging, `CH0J` for adapter)
- Improved time-remaining accuracy
- Additional battery detail rows
- Menu bar icon improvements

## What to avoid

- Adding a Xcode project or workspace
- Requiring code signing or entitlements
- Adding third-party Swift packages
- Color / gradient UI changes
- Rewriting the SMC approach to use a privileged XPC daemon (out of scope for this project)

## Reporting bugs

Open a GitHub issue with:

- macOS version and Mac model (e.g. M2 Max MacBook Pro, macOS 14.4)
- What you expected vs. what happened
- Relevant output from: `log show --predicate 'process == "Batty"' --last 5m`
- Current SMC key values: `sudo /Applications/Batty.app/Contents/Resources/smc -k CHTE -r`
