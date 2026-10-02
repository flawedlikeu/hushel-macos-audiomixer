Hushel-AudioMixer

A tiny per-app volume mixer for macOS, living in your menu bar.

Hushel lets you set the volume of each app separately: turn the browser down to 50% while music, calls and everything else keep playing at full volume. The system volume slider is not touched and keeps working as usual. If you've used EarTrumpet on Windows, this is the same idea.

Features
Menu bar app, no Dock icon
Lists every app that is currently playing audio
One slider per app (0–100%)
Doesn't affect the system volume or other apps
Remembers your levels between launches
Follows the output device: switching to headphones just works
Groups browser helper processes under the main app (e.g. Chrome)

***Requirements***
macOS 14.2 or later


The app is signed locally and not notarized, so macOS may say the developer can't be verified. Right-click the app and choose Open, or allow it under System Settings → Privacy & Security.

Usage

Click the menu bar icon and move the slider next to an app. At 100% the app is left completely untouched.

How it works

Hushel uses Core Audio process taps (macOS 14.2+), so no virtual audio driver is needed.

It polls the system for processes that are outputting audio and groups them by app.
When you lower an app below 100%, Hushel creates a tap on that app's processes. The original sound is muted.
The tapped audio is scaled by your slider value and played to the current output device.

Apps at 100% have no tap, so they are never routed through Hushel.

Limitations
Volume can only be lowered, not boosted above 100%.
Some apps play audio from system helper processes (Safari's WebKit processes, for example) and may appear as a separate entry under a different name.
Routing audio through a tap adds a small amount of latency.
