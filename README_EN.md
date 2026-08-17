# Kindle 4 Flip Clock

[中文说明](README.md) · A full-screen KUAL flip-clock-style display for the Kindle 4 Non-Touch (K4NT).

![Kindle 4 Flip Clock preview](docs/preview.svg)

The extension shows the time, Gregorian date, weekday, Chinese lunar date, and battery level. Screen orientation, 12/24-hour mode, and light/dark themes are controlled with the Kindle's physical keys while the clock is running.

The current release uses direct minute updates instead of an animated transition. This is more reliable on the Kindle 4 E Ink display and avoids unnecessary refreshes.

## Features

- Four screen orientations
- 12-hour and 24-hour formats
- Light and dark themes
- Gregorian date, weekday, Chinese lunar date, and battery percentage
- ByteDance Douyin Sans font
- Direct refresh at each minute boundary, with periodic full refreshes to reduce ghosting
- Persistent settings and physical-key shortcuts
- First-frame validation before the Kindle framework is stopped
- Safe exit with Home or Back
- Does not change the Wi-Fi state and does not require a network connection

## Tested setup

- Kindle 4 Non-Touch
- Firmware 4.1.4
- Jailbreak and [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326)
- [KOReader](https://github.com/koreader/koreader) installed at `/mnt/us/koreader`

Other Kindle models use different resolutions, framebuffer rotations, and key codes and are not currently supported.

## Installation

1. Extract the release archive.
2. Copy the complete `kclock` directory to the Kindle's `extensions` directory.
3. Verify that the final path is `/mnt/us/extensions/kclock`.
4. Safely eject the Kindle.
5. Select `Flip Clock` in KUAL.

Do not rename the `kclock` directory; the current scripts use an absolute path.

## Physical-key shortcuts

| Key | Action | K4NT key code |
|---|---|---:|
| Left previous-page | Previous screen orientation | 193 |
| Left next-page | Next screen orientation | 104 |
| Right previous-page | Toggle light/dark theme | 109 |
| Five-way center | Toggle 12/24-hour format | 194 |
| Menu | Show/hide shortcut help | 139 |
| Back | Exit | 158 |
| Home | Exit | 102 |

The directional pad, keyboard key, and right next-page key are currently unassigned.

## Configuration

`kclock/settings.conf` contains:

```sh
ORIENTATION=landscape_right
HOUR_MODE=24
THEME=light
TIMEZONE=CST-8
```

`TIMEZONE` uses POSIX TZ syntax. Note that the sign is reversed compared with the usual UTC notation; UTC+8 is written as `CST-8`.

## Rendering

The extension uses KOReader's LuaJIT, FreeType, and BlitBuffer to produce a 600×800 grayscale PNG. The image is displayed with `eips`. Time is redrawn once per minute, a full clear is performed periodically and after manual setting changes, and the Kindle framework is restored when the clock exits.

Logs:

```text
/tmp/root/kclock.log
/mnt/us/extensions/kclock/output/render.log
```

## Font

`kclock/fonts/DouyinSansBold.ttf` is the official Douyin Sans Bold file from [ByteDance Fonts](https://github.com/bytedance/fonts). It is redistributed under the SIL Open Font License 1.1; see `kclock/fonts/OFL.txt`.

## Known limitations

- Designed for the Kindle 4 Non-Touch 600×800 framebuffer and its physical key codes.
- Keeping the device awake uses more power than normal standby.
- Battery reading depends on the Kindle 4 `gasgauge-info -c` output.
- Lunar dates are supported from 1900 through 2100.
- Seconds and per-second updates are intentionally omitted.
- Minute changes use direct refreshes and do not include a flip animation.

## Credits and license

Inspired by [LaisRast/kclock](https://github.com/LaisRast/kclock). This public edition removes the original SVG/rsvg/pngcrush pipeline and uses a new Lua/KOReader renderer.

Code is licensed under the [MIT License](LICENSE). The bundled font remains under its separate [SIL Open Font License 1.1](kclock/fonts/OFL.txt). See [NOTICE.md](NOTICE.md).

Use jailbreak software and third-party extensions at your own risk.
