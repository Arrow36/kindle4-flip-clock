kfc (Kindle Flip Clock) 2.2.3

Requirements:
- jailbroken Kindle 4 Non-Touch
- KUAL
- KOReader installed at /mnt/us/koreader

Install this directory at:
  /mnt/us/extensions/kfc

Start by selecting kfc in KUAL.

Exit with the Home button.
Press Back to clear the screen and force a complete redraw.
Press the Keyboard key to synchronize time immediately with KOReader SNTP.

The next minute is rendered in advance and displayed at the absolute minute
boundary. Startup, every hour, successful time synchronization, and Back use
a full clear-then-redraw refresh.

Wi-Fi stays off while the clock runs and is enabled only for manual time
synchronization. Its original state is restored when the clock exits.

After ten minutes without a physical-key press, the Kindle uses RTC suspend
between minute updates. The power button wakes it and starts a new ten-minute
awake interval; ordinary keys restart the interval while already awake.

A resume at least about two seconds before the scheduled RTC alarm is treated
as a power-button wake and also starts a new ten-minute awake interval. Normal
minute RTC wakes do not restart the interval.

Runtime frames, PID files, and events are stored in /tmp/kfc. Persistent logs
are stored in /mnt/us/extensions/kfc/logs and are visible over USB.

Project documentation and licenses are in the repository root.
