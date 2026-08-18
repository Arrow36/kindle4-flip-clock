# Contributing

Issues and pull requests are welcome, especially for verified support on other Kindle models.

## Before opening an issue

Please include:

- Kindle model and firmware version
- KOReader version or build date
- Selected orientation, time format, and theme
- `kfc/logs/launcher.log`
- `kfc/logs/kfc.log`

Remove serial numbers, Wi-Fi details, or other personal information before attaching logs.

## Development notes

- Shell scripts target the Kindle BusyBox `/bin/sh`; avoid Bash-only syntax.
- Keep the extension directory name `kfc` unless all absolute paths are updated.
- The renderer must always output a 600×800 grayscale PNG for the K4NT framebuffer.
- Rendering must succeed before the Kindle framework is stopped.
- Input listeners should only publish events; the main loop owns rendering and settings writes.
- Avoid per-second refreshes unless they are explicitly optional, because they increase ghosting, power use, and flash frequency.

Run at least:

```sh
sh -n kfc/src/start.sh
sh -n kfc/src/time_sync.sh
```

Test Home cleanup, Back forced refresh, minute-boundary publication, and Wi-Fi restoration on the real device before submitting a release.
