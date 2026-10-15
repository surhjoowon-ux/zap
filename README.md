# zap

**English** · [한국어](README.ko.md)

**[Download →](../../releases/latest)** `zap.dmg` for macOS, `zap-windows.zip` for Windows

A translucent ruler you can float anywhere on your screen. Measure things inside websites and apps, or hold a real object up to the screen and measure it in real millimeters.

## Install (macOS)

1. Download `zap.dmg` from [Releases](../../releases/latest).
2. Open the dmg and drag `zap` into your `Applications` folder.
3. On first launch macOS may block it as an app from an "unidentified developer", because zap isn't notarized by Apple yet.
   - Go to **System Settings → Privacy & Security** and click **Open Anyway** near the bottom, or
   - run this once in Terminal:
     ```
     xattr -dr com.apple.quarantine /Applications/zap.app
     ```

Requires macOS 12 or later. Runs natively on Apple Silicon and Intel.

### Windows

1. Download `zap-windows.zip` from [Releases](../../releases/latest), unzip it, and run `zap.exe`. There's no installer.
2. If a blue "Windows protected your PC" window appears, click **More info → Run anyway**. zap isn't code-signed yet.
3. zap lives in the system tray (the `^` next to the clock).

Runs on Windows 10/11 (uses the built-in .NET Framework 4.8). Shortcuts use `Ctrl+Alt` instead of `⌃⌥`, and the menu opens from the tray icon. Liquid Glass is macOS-only, so on Windows the ruler is drawn with a translucent fill.

## How to use

- **Show / hide**: `⌃⌥R`, or the ruler icon in the menu bar
- **Measure**: click on the ruler to set a start point, click again to set the end. The next click starts a new measurement. Click outside the ruler or press `esc` to clear
- **Move**: drag the ruler. Arrow keys nudge 1px (`⇧` for 10px)
- **Rotate / stretch**: drag the circle at the end. It snaps every 90°, hold `⇧` for 15° steps. Double-click or `R` rotates 90°, `[` `]` rotate 1°
- **Measure an area**: press `⌃⌥M` and drag a box to get its real size (mm) and pixels. `⌘C` (`Ctrl+C` on Windows) copies it
- **Scales**: the top edge shows real length (cm/inch), the bottom edge shows screen pixels. `U` switches units

## Customize (menu → Ruler Settings…)

Change the color, add a horizontal gradient, fill the ruler with a photo, and adjust opacity, thickness, and which scales are shown.
Photos are laid out in a single row at the ruler's thickness and repeated in whole-centimeter tiles.

## Calibrate your display

Some screens, like many external monitors, don't report their physical size. Open **menu → Calibrate Display…**, hold a credit card (85.60 mm) against the screen, and match its width. The result is saved per display.

## Build it yourself

```
./build.sh           # dist/zap.app, dist/zap.dmg
windows/build.sh     # dist/zap-windows.zip (needs the .NET 8 SDK; builds on macOS too)
```

---

Standing Studio
