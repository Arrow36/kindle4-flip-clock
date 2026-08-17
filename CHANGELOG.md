# Changelog

All notable changes to this project are documented here.

## 2.1.0 - 2026-08-18

Initial public release of the custom Kindle 4 flip clock edition.

### Added

- Flip-clock-style four-digit layout rendered with KOReader's graphics stack
- Portrait and landscape orientations in all four rotations
- Light/dark themes and 12/24-hour formats
- Gregorian date, weekday, Chinese lunar date, AM/PM, and battery display
- Persistent settings controlled by physical keys
- Physical-key shortcuts and an on-screen shortcut page
- Direct minute refresh with periodic full clears
- First-frame validation and guarded cleanup to restore the Kindle framework
- Official Douyin Sans Bold font with its OFL-1.1 license

### Changed from the original concept

- Replaced the SVG, `rsvg-convert`, and `pngcrush` pipeline with LuaJIT, FreeType, and BlitBuffer from KOReader
- Kept Wi-Fi state unchanged
- Removed the simulated transition frame in favor of direct refreshes
