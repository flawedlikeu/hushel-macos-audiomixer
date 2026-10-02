# Hushel

A tiny per-app volume mixer for macOS, living in your menu bar.

Hushel lets you set the volume of each app separately: turn the browser down to 50% while music, calls and everything else keep playing at full volume. The system volume slider is not touched and keeps working as usual. If you've used EarTrumpet on Windows, this is the same idea.

## Features

- Menu bar app, no Dock icon
- Lists every app that is currently playing audio
- One slider per app (0–100%)
- Doesn't affect the system volume or other apps
- Remembers your levels between launches
- Optional 5-band equalizer for any app you choose
- Launch at login
- English and Russian interface (follows the system language)
- Follows the output device: switching to headphones just works
- Groups browser helper processes under the main app (e.g. Chrome)

## Requirements

- macOS 14.2 or later

## Install

1. Download `Hushel.dmg` from the latest release.
2. Open it and drag Hushel to Applications.
3. Launch it. A slider icon appears in the menu bar.
4. Allow audio access when macOS asks. Hushel can't mix app audio without it.

The app is signed locally and not notarized, so macOS may say the developer can't be verified. Right-click the app and choose **Open**, or allow it under **System Settings → Privacy & Security**.

## Usage

Click the menu bar icon and move the slider next to an app. At 100% the app is left completely untouched.

## Equalizer

Click the gear icon in the panel (or right-click the menu bar icon and choose **Settings…**), then open the **Equalizer** tab. Add any app (running or picked from Applications), then adjust five bands (60 Hz, 250 Hz, 1 kHz, 4 kHz, 12 kHz) by ±12 dB. Only the apps you add are processed; everything else is untouched.

## Build from source

You need Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/flawedlikeu/hushel-macos-audiomixer.git
cd hushel-macos-audiomixer
bash build.sh
```

This builds `build/Hushel.app` and launches it.

## How it works

Hushel uses Core Audio process taps (macOS 14.2+), so no virtual audio driver is needed.

1. It polls the system for processes that are outputting audio and groups them by app.
2. When you lower an app below 100%, Hushel creates a tap on that app's processes. The original sound is muted.
3. The tapped audio is scaled by your slider value and played to the current output device.

Apps at 100% have no tap, so they are never routed through Hushel.

## Limitations

- Volume can only be lowered, not boosted above 100%.
- Some apps play audio from system helper processes (Safari's WebKit processes, for example) and may appear as a separate entry under a different name.
- Routing audio through a tap adds a small amount of latency.
