-- Persistent renderer and Kindle 4 partial-refresh service.
--
-- Protocol (tab separated):
--   PING    status
--   RENDER  status output orientation theme epoch battery help hour_mode
--   PREPARE status orientation theme current_epoch target_epoch hour_mode
--   DISPLAY status epoch

require("setupkoenv")
local ffi = require("ffi")
local renderer = dofile("/mnt/us/extensions/kfc/src/clock_renderer.lua")

pcall(ffi.cdef, [[
struct timeval {
    long tv_sec;
    long tv_usec;
};
]])
pcall(ffi.cdef, [[
int gettimeofday(struct timeval *tv, void *tz);
int settimeofday(const struct timeval *tv, const void *tz);
]])

local function adjust_system_time(offset_sec)
    local tv = ffi.new("struct timeval")
    if ffi.C.gettimeofday(tv, nil) == 0 then
        tv.tv_sec = tv.tv_sec + offset_sec
        return ffi.C.settimeofday(tv, nil) == 0
    end
    return false
end

local function split_tabs(line)
    local fields = {}
    local start = 1
    while true do
        local position = line:find("\t", start, true)
        if not position then
            fields[#fields + 1] = line:sub(start)
            return fields
        end
        fields[#fields + 1] = line:sub(start, position - 1)
        start = position + 1
    end
end

local function single_line(value)
    local sanitized = tostring(value):gsub("[\r\n\t]+", " ")
    return sanitized
end

local function publish_status(path, status, detail)
    local temporary = path .. ".tmp"
    local file, open_error = io.open(temporary, "w")
    if not file then
        io.stderr:write("render status open failed: " .. single_line(open_error) .. "\n")
        io.stderr:flush()
        return
    end
    file:write(status)
    if detail then file:write(" ", single_line(detail)) end
    file:write("\n")
    file:close()
    local renamed, rename_error = os.rename(temporary, path)
    if not renamed then
        os.remove(temporary)
        io.stderr:write("render status publish failed: " .. single_line(rename_error) .. "\n")
        io.stderr:flush()
    end
end

for line in io.lines() do
    local fields = split_tabs(line)
    local command = fields[1]
    local status_path = fields[2]
    if command == "PING" and #fields == 2 then
        publish_status(status_path, "OK", "PONG")
    elseif command == "RENDER" and #fields == 9 then
        local ok, render_error = xpcall(function()
            renderer.render_png(fields[3], fields[4], fields[5], fields[6],
                fields[7], fields[8] == "1", fields[9])
        end, debug.traceback)
        if ok then
            publish_status(status_path, "OK")
        else
            publish_status(status_path, "ERROR", render_error)
        end
        collectgarbage("step")
    elseif command == "PREPARE" and #fields == 7 then
        local ok, x, y, width, height, changed_count = xpcall(function()
            return renderer.prepare_partial(fields[3], fields[4], fields[5], fields[6], fields[7])
        end, debug.traceback)
        if ok then
            publish_status(status_path, "OK",
                string.format("PARTIAL %d %d %d %d DIGITS %d",
                    x, y, width, height, changed_count))
        else
            publish_status(status_path, "ERROR", x)
        end
        collectgarbage("step")
    elseif command == "DISPLAY" and #fields == 3 then
        local ok, x, y, width, height, changed_count,
            refresh_start_cs, refresh_end_cs = xpcall(function()
            return renderer.display_partial(fields[3])
        end, debug.traceback)
        if ok then
            publish_status(status_path, "OK",
                string.format("PARTIAL %d %d %d %d DIGITS %d START_CS %d END_CS %d",
                    x, y, width, height, changed_count,
                    refresh_start_cs, refresh_end_cs))
        else
            publish_status(status_path, "ERROR", x)
        end
    elseif command == "ADJUST" and #fields == 3 then
        local offset = tonumber(fields[3]) or 0
        if offset ~= 0 then
            local ok = adjust_system_time(offset)
            if ok then
                publish_status(status_path, "OK", string.format("ADJUST %d", offset))
            else
                publish_status(status_path, "ERROR", "settimeofday failed")
            end
        else
            publish_status(status_path, "OK", "NOOP")
        end
    else
        if status_path and status_path ~= "" then
            publish_status(status_path, "ERROR", "invalid persistent render request")
        else
            io.stderr:write("invalid persistent render request\n")
            io.stderr:flush()
        end
    end
end

pcall(renderer.close)
