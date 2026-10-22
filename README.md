# QEMU-iOS for Android (iPod touch 2G)

An unofficial **Android port** of [QEMU-iOS](https://github.com/devos50/qemu-ios), the emulator for
legacy Apple devices created by **Martijn de Vos ([devos50](https://github.com/devos50))**.
It boots iPhone OS 2.1 on an emulated iPod touch 2G, as an installable app, built entirely by
GitHub Actions.

> **All of the hard work is not mine.** The iPod touch 1G/2G hardware emulation, the boot process,
> the multitouch, LCD and crypto engines, and the reverse engineering behind them are devos50's
> work. This fork only adds an Android wrapper and a CI pipeline around it. If you like this,
> please star and support the [original project](https://github.com/devos50/qemu-ios) and read his
> write-ups:
> [part 1](https://devos50.github.io/blog/2022/ipod-touch-qemu/) and
> [part 2](https://devos50.github.io/blog/2022/ipod-touch-qemu-pt2/).
>
> This project is not affiliated with or endorsed by devos50, the QEMU project or Apple.

## Using the app

1. Download the APK from the [latest release](../../releases/tag/android-latest) and install it
   (arm64, Android 10 or newer).
2. Get the three firmware files from the upstream
   [`n72ap_v1` release](https://github.com/devos50/qemu-ios/releases/tag/n72ap_v1):
   `bootrom_240_4`, `nor_n72ap.bin` and `nand_n72ap.zip`. They contain Apple software, so they are
   **not** included in this repository or the APK. Instructions for generating them yourself are in
   the upstream [`RUNNING.md`](RUNNING.md) and its linked repositories.
3. Open the app, tap **Import firmware files…**, select all three files (the NAND zip is extracted
   for you), then tap **Start iPod touch**.

### In the emulator

- The buttons under the screen are the iPod's **Power** (sleep/wake), **Home**, and **Volume**
  buttons. iOS auto-locks after a while; tap Power or Home to wake it.
- The overlay in the top-left corner is a heartbeat: green = running, orange = idle, red = app
  paused. The **HUD** button hides it. Leaving the screen black with a green dot usually just
  means iOS put its screen to sleep.
- The Android back gesture is disabled on purpose so an accidental swipe cannot kill the emulator
  while it is writing to the NAND. Swipe the app away from recents to quit.
- On the launcher, **Show QEMU log** displays QEMU's error output, and **Verbose QEMU log**
  turns on unimplemented-hardware logging.

## How the Android build works

Everything is cross-compiled in CI ([`.github/workflows/android.yml`](.github/workflows/android.yml)):

| Step | What happens |
| --- | --- |
| `android/build-deps.sh` | Builds zlib, libffi, pcre2, glib, pixman, OpenSSL and SDL2 for arm64 with the Android NDK |
| `android/build-qemu.sh` | Cross-compiles `qemu-system-arm`, then relinks the same objects as `libmain.so` (entry point `SDL_main`) |
| `android/project/` | Gradle project: a launcher/importer activity and an `SDLActivity` that starts QEMU in-process |
| CI | Builds the APK and publishes it as the `android-latest` release |

Changes to QEMU itself are small: `system/main.c` (SDL entry point and stderr capture on Android)
and `ui/sdl2.c` (repaint after the app is paused/resumed). Guest code is run by QEMU's TCG
interpreter-JIT; there is no KVM on Android.

Build it yourself by pushing to the `android-port` branch of a fork with Actions enabled.

## Known issues

- Performance on your device is unknown until you try it; there is no audio or Wi-Fi emulation
  (same as upstream).
- Only the iPod touch 2G machine is wired up in the app.
- Upstream notes the emulator is experimental; expect crashes in some apps.

## Credits

- **[devos50](https://github.com/devos50)** and contributors: QEMU-iOS, the whole emulated device
  ([upstream README](README.upstream.md)).
- The **[QEMU project](https://www.qemu.org)**.
- **[SDL](https://libsdl.org)** for the Android windowing/input layer, plus glib, pixman, libffi,
  pcre2, zlib and OpenSSL.

## License

QEMU is licensed under the GNU GPL, version 2 (see [`COPYING`](COPYING) and [`LICENSE`](LICENSE)),
and the Android additions in `android/` are released under the same terms. The debug keystore in
`android/` is a throwaway key used only so that CI-built APKs can update each other.
