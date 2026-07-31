# MIDI Tap Tempo Indicator

A macOS menu bar app that listens for MIDI tap-tempo presses, tracks BPM internally, and blinks one or more controller LEDs at that tempo. Useful when your DAW or host maps a controller button to tap tempo but doesn’t expose BPM for LED feedback.

## Features

- **Menu bar BPM** — live tempo in the status item; dimmed when idle, warning when a selected device drops
- **Shared controller** — other apps can keep using the same MIDI device
- **Channel-aware Learn** — capture tap input and LED outputs (CC/note + channel)
- **Multiple LED outputs** — blink several LEDs, or use different CCs for tap-in vs LED-out
- **Echo filtering** — ignores LED feedback loops if the device echoes outbound CCs
- **Beat subdivisions** — quarter, eighth, or downbeat-only flash
- **BPM nudge / slider** — fine-tune when tap is close but not exact
- **Resume last BPM** — remembers tempo across launches; blink resumes on controller activity
- **Controller idle timeout** — any MIDI keeps the blink alive (minutes, up to 60)
- **Test blink** — verify external LED mode without tapping tempo
- **First-run onboarding** — pick device → Learn → test LED
- **Import / export settings** — JSON snapshot of mappings and preferences
- **Launch at login** — optional (requires the `.app` bundle)

## Requirements

- macOS 13 (Ventura) or later
- [Swift](https://swift.org) toolchain (Xcode or Command Line Tools)
- A MIDI controller with externally controllable LEDs (typically via CC)
- Optional: any DAW or host that also listens to the same controller

## Hardware setup

1. Configure your controller so button LEDs can be driven by incoming MIDI (often called External LED mode).
2. Keep your existing host mappings on the physical controller.
3. If a tap LED flickers oddly, disable host MIDI feedback for that button and let this app own its LED.

## Install

### Option 1: Build a `.app` bundle (recommended)

```bash
./scripts/build-app.sh --install
```

```bash
./scripts/build-app.sh          # build only
./scripts/build-app.sh --open   # build and launch
./scripts/build-app.sh --install --open
```

### Option 2: Run from source

```bash
swift run
```

Launch at login requires the `.app` bundle.

## Usage

1. Launch the app (menu bar shows a metronome + BPM).
2. Complete onboarding, or open **Settings…**
3. Select MIDI **Input** / **Output** (or **Use same device**).
4. Learn the **Tap Input**, then configure **LED Outputs** if needed.
5. Tap a tempo — BPM appears in the menu bar and LEDs blink.
6. Use **Test Blink** to verify LEDs without tapping.
7. Nudge BPM from the menu (+1 / −1) or the settings slider.

## Development

```bash
swift build
swift run
swift build -c release
./scripts/ci-verify.sh   # requires full Xcode for tests
```

CI, signing, and notarization are documented in [`docs/ci-cd.md`](docs/ci-cd.md).

## License

Copyright © 2026 New Day Naz. All rights reserved.
