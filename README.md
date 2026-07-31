# MIDI Tap Tempo Indicator

A macOS menu bar app that listens for MIDI tap-tempo presses, tracks BPM internally, and blinks the same control’s LED at that tempo. Useful when your DAW or host maps a controller button to tap tempo but doesn’t expose BPM for LED feedback.

## Features

- **Menu bar app** — runs in the background with no Dock icon
- **Shared controller** — other apps can keep using the same MIDI device; no virtual MIDI remapping required
- **Tap tempo tracking** — rolling average BPM from learned CC/note presses
- **LED blink** — sends CC back to the controller at the current BPM
- **Controller idle timeout** — any knob, fader, or button use keeps the blink alive; silence stops it
- **Learn mode** — capture the tap button mapping from hardware
- **Launch at login** — optional (requires the `.app` bundle)
- **Persistent settings** — saved via UserDefaults

## Requirements

- macOS 13 (Ventura) or later
- [Swift](https://swift.org) toolchain (Xcode or Command Line Tools)
- A MIDI controller with externally controllable LEDs (typically via CC)
- Optional: any DAW or host that also listens to the same controller

## Hardware setup

1. Configure your controller so the tap button’s LED can be driven by incoming MIDI (often called External LED mode in the manufacturer’s editor).
2. Keep your existing host mappings on the physical controller.

If the tap LED flickers oddly, disable host MIDI feedback for that specific button and let this app own its LED.

## Install

### Option 1: Build a `.app` bundle (recommended)

```bash
./scripts/build-app.sh --install
```

This compiles a release build, packages `dist/MidiTapTempoIndicator.app`, signs it ad-hoc, and copies it to `/Applications`.

```bash
./scripts/build-app.sh          # build only
./scripts/build-app.sh --open   # build and launch
./scripts/build-app.sh --install --open
```

### Option 2: Run from source

```bash
swift run
```

Launch at login is **not** available when running this way — use the `.app` bundle for that.

## Usage

1. Launch the app (menu bar icon: metronome).
2. Open **Settings…**
3. Select your controller for **Input** and **Output**, then **Refresh** if needed.
4. On the **Mapping** tab, click **Learn** and press your tap-tempo button.
5. Tap a tempo — the menu bar shows BPM and the button LED blinks in time.
6. Moving any control on the board keeps the blink running; after the idle timeout with no MIDI, the LED turns off.

### Settings overview

| Section | Description |
|---------|-------------|
| **Startup** | Open at login (`.app` only) |
| **MIDI Devices** | Input (listen) and output (LED) endpoints |
| **Tempo & Blink** | LED enable, controller idle timeout, BPM clamp, LED on/off values, MIDI channel |
| **Mapping** | Tap tempo CC/note with Learn |

**Controller idle timeout:** any MIDI from the selected input refreshes activity. The LED keeps blinking at the last BPM while the controller is in use, and stops after the configured number of minutes (1–60) with no MIDI.

## How it works

```
Controller ──MIDI──▶ Host / DAW   (existing tap mapping)
     │
     └────MIDI──▶ Tap Tempo Indicator ──CC LED──▶ Controller
```

Core MIDI delivers each hardware message to every connected client, so your host keeps receiving taps while this app calculates BPM and drives the LED. No IAC or virtual port is required for v1.

## Development

```bash
swift build
swift run
swift build -c release
```

Unit tests (`swift test`) require a full Xcode install (XCTest is not available with Command Line Tools alone).

## License

Copyright © 2026 New Day Naz. All rights reserved.
