-- One-shot PNG entry point. The persistent server imports the same renderer so
-- both paths share cached-card drawing behavior.
require("setupkoenv")

local renderer = dofile("/mnt/us/extensions/kfc/src/clock_renderer.lua")
renderer.render_png(
    assert(arg[1], "missing output path"),
    arg[2] or "landscape_right",
    arg[3] or "light",
    tonumber(arg[4]) or os.time(),
    tonumber(arg[5]) or 0,
    arg[6] == "1",
    arg[7] == "12" and "12" or "24"
)
renderer.close()
