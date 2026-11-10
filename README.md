# Scrcpy Launcher

A native macOS app for [scrcpy](https://github.com/Genymobile/scrcpy): mirror, record and screenshot your Android phones from a simple device list, without the terminal.

## Features

- **Device list:** every connected phone (USB or Wi-Fi), refreshed automatically.
- **Per-device buttons:**
  - **View** opens the mirror window. It becomes **Stop** while viewing.
  - **Screenshot** saves a PNG to `~/Pictures/Scrcpy`.
  - **Record** records the screen with sound to an MP4 in `~/Movies/Scrcpy`. It becomes **Stop** and shows a timer. If the cable is pulled or the connection drops, the recording is saved up to that point.
- **Multiple devices at once:** view or record several phones side by side, or view and record the same phone at the same time.
- **Default settings + per-device settings:** set defaults for every phone, and override any of them for a single phone (⚙︎ on its row). Per-phone settings follow the phone between USB and Wi-Fi.
- **All scrcpy options:** resolution, FPS, bit rate, codecs, audio source, keyboard/mouse/gamepad modes, virtual display, camera mirroring, window options and more. There's also a box for extra flags.
- **Presets and saved profiles:** Low latency, High quality, Gaming 120 fps, Battery saver, Phone as webcam, Second screen.
- **Wireless:** connect by IP, pair with a code (Android 11+), or switch a USB phone to Wi-Fi in one click.
- **Device info:** list a phone's displays, cameras, encoders and installed apps.

## Requirements

- macOS 14 or later (Apple Silicon)
- scrcpy and adb:

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

- On the phone: Developer options ▸ **USB debugging** turned on.

## Build & install

No Xcode needed: the Command Line Tools are enough.

```bash
./build.sh            # builds build/Scrcpy Launcher.app
./build.sh install    # also copies it to /Applications
```

## Troubleshooting

- **scrcpy fails to start after a Homebrew update** (`Library not loaded … dylib`): run `brew upgrade scrcpy ffmpeg`.
- **Device shows "Unlock phone and allow USB debugging":** unlock the phone and accept the prompt.
- **Something went wrong:** use ⋯ ▸ Show Log on the device row to see scrcpy's output.

## Author

Abdul Haseeb — [@iChAbdulHaseeb](https://github.com/iChAbdulHaseeb)
