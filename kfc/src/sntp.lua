-- Minimal SNTP client for the LuaJIT and LuaSocket bundled with KOReader.
-- It tries each server in order and sets the system clock only after checking
-- the response mode, leap indicator, stratum, and echoed client timestamp.

package.path = "/mnt/us/koreader/common/?.lua;/mnt/us/koreader/common/?/init.lua;" .. package.path
package.cpath = "/mnt/us/koreader/common/?.so;/mnt/us/koreader/common/?/?.so;" .. package.cpath

local ffi = require("ffi")
local socket = require("socket")

ffi.cdef([[
struct timeval {
    long tv_sec;
    long tv_usec;
};
int settimeofday(const struct timeval *tv, const void *tz);
]])

local NTP_UNIX_DELTA = 2208988800
local UINT32 = 4294967296

local function uint32_be(value)
    value = math.floor(value) % UINT32
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256
    )
end

local function read_uint32_be(data, offset)
    local a, b, c, d = data:byte(offset, offset + 3)
    if not d then return nil end
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function encode_timestamp(unix_time)
    local ntp_time = unix_time + NTP_UNIX_DELTA
    local seconds = math.floor(ntp_time)
    local fraction = math.floor((ntp_time - seconds) * UINT32)
    return uint32_be(seconds) .. uint32_be(fraction)
end

local function decode_timestamp(data, offset)
    local seconds = read_uint32_be(data, offset)
    local fraction = read_uint32_be(data, offset + 4)
    if not seconds or not fraction then return nil end
    if seconds < NTP_UNIX_DELTA then seconds = seconds + UINT32 end
    return seconds - NTP_UNIX_DELTA + fraction / UINT32
end

local function set_system_time(unix_time)
    local seconds = math.floor(unix_time)
    local microseconds = math.floor((unix_time - seconds) * 1000000 + 0.5)
    if microseconds >= 1000000 then
        seconds = seconds + 1
        microseconds = microseconds - 1000000
    end

    local value = ffi.new("struct timeval")
    value.tv_sec = seconds
    value.tv_usec = microseconds
    if ffi.C.settimeofday(value, nil) ~= 0 then
        return nil, "settimeofday failed with errno " .. tostring(ffi.errno())
    end
    return true
end

-- Declare this before synchronize(): Lua lexical scope starts at the
-- declaration, so a later local would make synchronize() read a global.
local check_only = false

local function synchronize(server)
    local udp, create_error = socket.udp()
    if not udp then return nil, "UDP socket creation failed: " .. tostring(create_error) end
    udp:settimeout(8)

    local peer_ok, peer_error = udp:setpeername(server, 123)
    if not peer_ok then
        udp:close()
        return nil, "DNS/peer setup failed: " .. tostring(peer_error)
    end

    local sent_at = socket.gettime()
    local request = string.char(0x23) .. string.rep("\0", 39) .. encode_timestamp(sent_at)
    local sent, send_error = udp:send(request)
    if not sent then
        udp:close()
        return nil, "send failed: " .. tostring(send_error)
    end

    local response, receive_error = udp:receive()
    local received_at = socket.gettime()
    udp:close()
    if not response then return nil, "receive failed: " .. tostring(receive_error) end
    if #response < 48 then return nil, "short response: " .. tostring(#response) .. " bytes" end

    local first = response:byte(1)
    local leap = math.floor(first / 64)
    local mode = first % 8
    local stratum = response:byte(2)
    if leap == 3 then return nil, "server clock is unsynchronized" end
    if mode ~= 4 and mode ~= 5 then return nil, "unexpected NTP mode: " .. tostring(mode) end
    if not stratum or stratum < 1 or stratum > 15 then
        return nil, "invalid stratum: " .. tostring(stratum)
    end

    local echoed_at = decode_timestamp(response, 25)
    local server_received = decode_timestamp(response, 33)
    local server_sent = decode_timestamp(response, 41)
    if not echoed_at or not server_received or not server_sent then
        return nil, "response timestamps are incomplete"
    end
    if math.abs(echoed_at - sent_at) > 1 then
        return nil, "response did not echo this request"
    end

    local offset = ((server_received - sent_at) + (server_sent - received_at)) / 2
    local delay = (received_at - sent_at) - (server_sent - server_received)
    local corrected_time = received_at + offset
    if corrected_time < 1577836800 or corrected_time > 4102444800 then
        return nil, "server returned an implausible time"
    end

    if not check_only then
        local set_ok, set_error = set_system_time(corrected_time)
        if not set_ok then return nil, set_error end
    end
    return {offset = offset, delay = delay, stratum = stratum}
end

local servers = {}
for index = 1, #arg do
    if arg[index] == "--check-only" then
        check_only = true
    else
        servers[#servers + 1] = arg[index]
    end
end
if #servers == 0 then
    servers = {"ntp1.aliyun.com", "ntp2.aliyun.com", "ntp.aliyun.com"}
end

local prefix = check_only and "SNTP check: " or "SNTP success: "
local cache_path = "/tmp/kfc/last_sntp_check"
local function sntp_log(msg)
    local ts = os.date("[%Y-%m-%d %H:%M:%S] ")
    io.stdout:write(ts .. msg .. "\n")
    io.stdout:flush()
end

for _, server in ipairs(servers) do
    sntp_log("SNTP trying " .. server)
    local result, err = synchronize(server)
    if result then
        local extra = ""
        local now_epoch = socket.gettime()
        local last_file = io.open(cache_path, "r")
        if last_file then
            local content = last_file:read("*a")
            last_file:close()
            local last_epoch, last_offset = content:match("([%d%.]+)%s+([%-%d%.]+)")
            last_epoch = tonumber(last_epoch)
            last_offset = tonumber(last_offset)
            if last_epoch and last_offset and (now_epoch - last_epoch) > 5 then
                local delta_s = result.offset - last_offset
                local elapsed_s = now_epoch - last_epoch
                local ppm = (delta_s / elapsed_s) * 1000000
                extra = string.format(" (delta=%+.4fs in %.0fs, rate=%+.1f ppm)", delta_s, elapsed_s, ppm)
            end
        end

        local write_file = io.open(cache_path, "w")
        if write_file then
            local stored_offset = check_only and result.offset or 0.0
            write_file:write(string.format("%.4f %.6f\n", now_epoch, stored_offset))
            write_file:close()
        end

        sntp_log(string.format(
            "%sserver=%s stratum=%d offset=%+.6fs delay=%.6fs%s",
            prefix, server, result.stratum, result.offset, result.delay, extra
        ))
        os.exit(0)
    end
    sntp_log("SNTP failed: " .. server .. ": " .. tostring(err))
end

os.exit(1)
