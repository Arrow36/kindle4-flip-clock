-- Shared flip-clock renderer.
--
-- Full frames are still encoded as PNG for startup, hourly cleanup refreshes,
-- settings/help changes, and the framebuffer fallback. Normal minute changes
-- are prepared as the smallest changed-card BB8 region and kept in this process.

require("setupkoenv")

local bit = require("bit")
local ffi = require("ffi")
local BB = require("ffi/blitbuffer")
local FT = require("ffi/freetype")
local C = ffi.C
local band, bor, lshift = bit.band, bit.bor, bit.lshift

local M = {}

local font_path = "/mnt/us/extensions/kfc/fonts/DouyinSansBold.ttf"
local lunar = dofile("/mnt/us/extensions/kfc/src/lunar.lua")
local weekday_names = {"星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"}

local face_cache = {}
local card_cache = {}
local prepared = nil

local function monotonic_centiseconds()
    local file = assert(io.open("/proc/uptime", "r"), "cannot read /proc/uptime")
    local value = file:read("*n")
    file:close()
    assert(value, "invalid /proc/uptime")
    return math.floor(value * 100 + 0.5)
end
local framebuffer = nil

local function utf8_chars(text)
    local function next_char(input, pos)
        if pos > #input then return nil end
        local value = string.byte(input, pos)
        if band(value, 0x80) == 0 then
            return pos + 1, value
        end
        local code, extra
        if band(value, 0xE0) == 0xC0 then
            code, extra = band(value, 0x1F), 1
        elseif band(value, 0xF0) == 0xE0 then
            code, extra = band(value, 0x0F), 2
        elseif band(value, 0xF8) == 0xF0 then
            code, extra = band(value, 0x07), 3
        else
            return pos + 1, 0xFFFD
        end
        for index = pos + 1, pos + extra do
            local continuation = string.byte(input, index)
            if not continuation or band(continuation, 0xC0) ~= 0x80 then
                return pos + 1, 0xFFFD
            end
            code = bor(lshift(code, 6), band(continuation, 0x3F))
        end
        return pos + extra + 1, code
    end
    return next_char, text, 1
end

local function measure_text(face, text)
    local width, top, bottom = 0, 0, 0
    local previous = nil
    for _, code in utf8_chars(text) do
        local glyph = face:renderGlyph(code, false)
        if previous then width = width + face:getKerning(previous, code) end
        width = width + glyph.ax
        top = math.max(top, glyph.t)
        bottom = math.max(bottom, glyph.bb:getHeight() - glyph.t)
        previous = code
    end
    return width, top, bottom
end

local function draw_text(canvas, face, text, x, baseline, color)
    local pen, previous = 0, nil
    for _, code in utf8_chars(text) do
        local glyph = face:renderGlyph(code, false)
        if previous then pen = pen + face:getKerning(previous, code) end
        canvas:colorblitFrom(glyph.bb, x + pen + glyph.l, baseline - glyph.t,
            0, 0, glyph.bb:getWidth(), glyph.bb:getHeight(), color)
        pen = pen + glyph.ax
        previous = code
    end
    return pen
end

local function draw_right_aligned(canvas, face, text, right, baseline, color)
    local width = measure_text(face, text)
    draw_text(canvas, face, text, right - width, baseline, color)
end

local function is_landscape(orientation)
    return orientation == "landscape_right" or orientation == "landscape_left"
end

local function layout_for(orientation)
    local landscape = is_landscape(orientation)
    if landscape then
        return {
            landscape = true,
            logical_width = 800,
            logical_height = 600,
            info_size = 28,
            small_size = 25,
            digit_size = 270,
            card_y = 170,
            card_width = 178,
            card_height = 260,
            radius = 12,
            colon_x = 400,
            colon_y = {260, 340},
            colon_radius = 9,
            card_x = {10, 194, 428, 612},
            region_x = 10,
            region_y = 170,
            region_width = 780,
            region_height = 260,
        }
    end
    return {
        landscape = false,
        logical_width = 600,
        logical_height = 800,
        info_size = 21,
        small_size = 23,
        digit_size = 235,
        card_y = 260,
        card_width = 128,
        card_height = 230,
        radius = 10,
        colon_x = 300,
        colon_y = {340, 410},
        colon_radius = 8,
        card_x = {6, 140, 332, 466},
        region_x = 6,
        region_y = 260,
        region_width = 588,
        region_height = 230,
    }
end

local function palette_for(theme, inverted)
    local light = theme ~= "dark"
    local values = {
        paper = light and 0xF2 or 0x11,
        ink = light and 0x17 or 0xEE,
        card = light and 0x17 or 0xEE,
        digit = light and 0xF2 or 0x11,
        seam = light and 0x68 or 0x77,
    }
    if inverted then
        for name, value in pairs(values) do values[name] = 0xFF - value end
    end
    return {
        light = light,
        paper = BB.Color8(values.paper),
        ink = BB.Color8(values.ink),
        card = BB.Color8(values.card),
        digit = BB.Color8(values.digit),
        seam = BB.Color8(values.seam),
    }
end

local function get_faces(layout)
    local key = layout.landscape and "landscape" or "portrait"
    local faces = face_cache[key]
    if not faces then
        faces = {
            info = FT.newFaceSize(font_path, layout.info_size),
            small = FT.newFaceSize(font_path, layout.small_size),
            digit = FT.newFaceSize(font_path, layout.digit_size),
        }
        face_cache[key] = faces
    end
    return faces
end

local function make_card(digit, face, layout, colors)
    local width, height = layout.card_width, layout.card_height
    local card_bb = BB.new(width, height, BB.TYPE_BB8)
    card_bb:fill(colors.paper)
    card_bb:paintRoundedRect(0, 0, width, height, colors.card, layout.radius)
    local text_width, text_top, text_bottom = measure_text(face, digit)
    local baseline = math.floor((height - text_top - text_bottom) / 2 + text_top + 2)
    draw_text(card_bb, face, digit, math.floor((width - text_width) / 2), baseline, colors.digit)
    local half = math.floor(height / 2)
    card_bb:paintRect(0, half - 1, width, 2, colors.seam)
    return card_bb
end

local function get_card(digit, orientation, theme, inverted, layout, faces, colors)
    local size_key = layout.landscape and "landscape" or "portrait"
    local key = table.concat({size_key, theme, inverted and "raw-inverted" or "normal", digit}, ":")
    local card_bb = card_cache[key]
    if not card_bb then
        card_bb = make_card(digit, faces.digit, layout, colors)
        card_cache[key] = card_bb
    end
    return card_bb
end

local function warm_digit_cache(orientation, theme, inverted, layout, faces, colors)
    for digit = 0, 9 do
        get_card(tostring(digit), orientation, theme, inverted, layout, faces, colors)
    end
end

local function clock_digits(target_epoch, hour_mode)
    local clock = os.date("*t", target_epoch)
    local display_hour = clock.hour
    if hour_mode == "12" then
        display_hour = clock.hour % 12
        if display_hour == 0 then display_hour = 12 end
    end
    local text = string.format("%02d%02d", display_hour, clock.min)
    return clock, {
        text:sub(1, 1), text:sub(2, 2), text:sub(3, 3), text:sub(4, 4),
    }
end

local function render_logical_time_region(orientation, theme, target_epoch, hour_mode, inverted)
    local layout = layout_for(orientation)
    local colors = palette_for(theme, inverted)
    local faces = get_faces(layout)
    warm_digit_cache(orientation, theme, inverted, layout, faces, colors)
    local _, digits = clock_digits(target_epoch, hour_mode)
    local region = BB.new(layout.region_width, layout.region_height, BB.TYPE_BB8)
    region:fill(colors.paper)

    for index = 1, 4 do
        local card_bb = get_card(digits[index], orientation, theme, inverted, layout, faces, colors)
        region:blitFrom(card_bb,
            layout.card_x[index] - layout.region_x,
            layout.card_y - layout.region_y,
            0, 0, layout.card_width, layout.card_height)
    end
    for _, y in ipairs(layout.colon_y) do
        region:paintCircle(layout.colon_x - layout.region_x,
            y - layout.region_y, layout.colon_radius, colors.ink)
    end
    return region, layout
end

local function render_changed_digit_region(orientation, theme, current_epoch, target_epoch, hour_mode, inverted)
    local layout = layout_for(orientation)
    local colors = palette_for(theme, inverted)
    local faces = get_faces(layout)
    warm_digit_cache(orientation, theme, inverted, layout, faces, colors)
    local _, current_digits = clock_digits(current_epoch, hour_mode)
    local _, target_digits = clock_digits(target_epoch, hour_mode)
    local changed = {}
    local left, right = layout.logical_width, 0
    for index = 1, 4 do
        if current_digits[index] ~= target_digits[index] then
            changed[#changed + 1] = index
            left = math.min(left, layout.card_x[index])
            right = math.max(right, layout.card_x[index] + layout.card_width)
        end
    end
    assert(#changed > 0, "partial frame has no changed digits")

    local region_x = left
    local region_y = layout.card_y
    local region_width = right - left
    local region_height = layout.card_height
    local region = BB.new(region_width, region_height, BB.TYPE_BB8)
    region:fill(colors.paper)
    for _, index in ipairs(changed) do
        local card_bb = get_card(target_digits[index], orientation, theme, inverted, layout, faces, colors)
        region:blitFrom(card_bb, layout.card_x[index] - region_x, 0,
            0, 0, layout.card_width, layout.card_height)
    end

    -- A normal minute changes only the last one or two cards. Keep this
    -- generic for guarded catch-up paths that might span the colon.
    if region_x <= layout.colon_x + layout.colon_radius and
       region_x + region_width >= layout.colon_x - layout.colon_radius then
        for _, y in ipairs(layout.colon_y) do
            region:paintCircle(layout.colon_x - region_x,
                y - region_y, layout.colon_radius, colors.ink)
        end
    end
    return region, layout, region_x, region_y, region_width, region_height, #changed
end

local function rotate_full(canvas, orientation)
    if orientation == "landscape_right" then return canvas:rotatedCopy(90) end
    if orientation == "landscape_left" then return canvas:rotatedCopy(270) end
    if orientation == "portrait_down" then return canvas:rotatedCopy(180) end
    return canvas
end

local function rotate_region(region, orientation)
    if orientation == "landscape_right" then return region:rotatedCopy(90) end
    if orientation == "landscape_left" then return region:rotatedCopy(270) end
    if orientation == "portrait_down" then return region:rotatedCopy(180) end
    return region
end

local function physical_region_position(layout, orientation, x, y, w, h)
    if orientation == "landscape_right" then
        return y, layout.logical_width - (x + w)
    elseif orientation == "landscape_left" then
        return layout.logical_height - (y + h), x
    elseif orientation == "portrait_down" then
        return layout.logical_width - (x + w), layout.logical_height - (y + h)
    end
    return x, y
end

local function render_full_canvas(orientation, theme, target_epoch, battery_level, show_help, hour_mode)
    local layout = layout_for(orientation)
    local colors = palette_for(theme, false)
    local faces = get_faces(layout)
    local clock = clock_digits(target_epoch, hour_mode)
    local lunar_text = lunar.convert(clock.year, clock.month, clock.day)
    local info_text = string.format("%d年%d月%d日  %s  农历%s",
        clock.year, clock.month, clock.day, weekday_names[clock.wday] or "星期六", lunar_text)
    local period = ""
    if hour_mode == "12" then period = clock.hour < 12 and "AM" or "PM" end

    battery_level = math.max(0, math.min(100, tonumber(battery_level) or 0))
    local canvas = BB.new(layout.logical_width, layout.logical_height, BB.TYPE_BB8)
    canvas:fill(colors.paper)

    if layout.landscape then
        draw_text(canvas, faces.info, info_text, 32, 55, colors.ink)
        draw_right_aligned(canvas, faces.small, period, 766, 145, colors.ink)
    else
        draw_text(canvas, faces.info, info_text, 25, 48, colors.ink)
        draw_right_aligned(canvas, faces.small, period, 570, 235, colors.ink)
    end

    local time_region = render_logical_time_region(orientation, theme, target_epoch, hour_mode, false)
    canvas:blitFrom(time_region, layout.region_x, layout.region_y)
    time_region:free()

    local battery_text = string.format("%d.0%%", battery_level)
    if layout.landscape then
        draw_right_aligned(canvas, faces.small, battery_text, 731, 560, colors.ink)
        canvas:paintBorder(744, 536, 42, 25, 3, colors.ink)
        canvas:paintRect(787, 543, 4, 11, colors.ink)
        canvas:paintRect(748, 540, math.floor(34 * battery_level / 100), 17, colors.ink)
    else
        draw_right_aligned(canvas, faces.small, battery_text, 531, 755, colors.ink)
        canvas:paintBorder(544, 732, 42, 25, 3, colors.ink)
        canvas:paintRect(587, 739, 4, 11, colors.ink)
        canvas:paintRect(548, 736, math.floor(34 * battery_level / 100), 17, colors.ink)
    end

    if show_help then
        local orientation_names = {
            portrait = "竖屏·按键在下",
            portrait_down = "竖屏·按键在上",
            landscape_right = "横屏·按键在右",
            landscape_left = "横屏·按键在左",
        }
        local hour_name = hour_mode == "12" and "12 小时制" or "24 小时制"
        local theme_name = colors.light and "浅色" or "深色"
        local box_x, box_y, box_width, box_height
        local text_x, header_baseline, line_baseline, line_gap
        if layout.landscape then
            box_x, box_y, box_width, box_height = 65, 55, 670, 490
            text_x, header_baseline, line_baseline, line_gap = 95, 105, 150, 36
        else
            box_x, box_y, box_width, box_height = 35, 65, 530, 670
            text_x, header_baseline, line_baseline, line_gap = 62, 118, 170, 50
        end

        canvas:paintRoundedRect(box_x, box_y, box_width, box_height, colors.paper, 16)
        canvas:paintBorder(box_x, box_y, box_width, box_height, 4, colors.ink)
        local header_key = layout.landscape and "header_landscape" or "header_portrait"
        local header_face = face_cache[header_key]
        if not header_face then
            header_face = FT.newFaceSize(font_path, layout.landscape and 34 or 29)
            face_cache[header_key] = header_face
        end
        draw_text(canvas, header_face, "kfc 快捷键", text_x, header_baseline, colors.ink)
        local lines = {
            "屏幕方向：" .. (orientation_names[orientation] or orientation),
            "时间制式：" .. hour_name,
            "显示主题：" .. theme_name,
            "",
            "左侧上一页 / 下一页：切换屏幕方向",
            "右侧可用翻页键：切换浅色 / 深色",
            "五向键确认：切换 12 / 24 小时制",
            "键盘键：立即联网校时",
            "菜单键：关闭说明",
            "返回键：强制全刷　Home：退出时钟",
        }
        for _, line in ipairs(lines) do
            if line ~= "" then draw_text(canvas, faces.small, line, text_x, line_baseline, colors.ink) end
            line_baseline = line_baseline + line_gap
        end
    end

    return canvas
end

local function errno_text(prefix)
    local errno = ffi.errno()
    return string.format("%s: %s (errno %d)", prefix, ffi.string(C.strerror(errno)), errno)
end

local function page_align(size)
    return band(size + 4095, -4096)
end

local function close_framebuffer()
    if not framebuffer then return end
    if framebuffer.data then C.munmap(framebuffer.data, framebuffer.map_size) end
    if framebuffer.fd and framebuffer.fd >= 0 then C.close(framebuffer.fd) end
    framebuffer = nil
end

local function open_framebuffer()
    if framebuffer then return framebuffer end
    require("ffi/posix_h")
    require("ffi/linux_fb_h")

    local fd = C.open("/dev/fb0", C.O_RDWR)
    if fd == -1 then error(errno_text("cannot open /dev/fb0")) end
    local finfo = ffi.new("struct fb_fix_screeninfo")
    local vinfo = ffi.new("struct fb_var_screeninfo")
    if C.ioctl(fd, C.FBIOGET_FSCREENINFO, finfo) ~= 0 then
        C.close(fd)
        error(errno_text("cannot read fixed framebuffer info"))
    end
    if C.ioctl(fd, C.FBIOGET_VSCREENINFO, vinfo) ~= 0 then
        C.close(fd)
        error(errno_text("cannot read variable framebuffer info"))
    end

    local width = tonumber(vinfo.xres)
    local height = tonumber(vinfo.yres)
    local bpp = tonumber(vinfo.bits_per_pixel)
    local stride = tonumber(finfo.line_length)
    local driver_id = ffi.string(finfo.id)
    local is_einkfb = driver_id:sub(1, 7) == "eink_fb"
    if width ~= 600 or height ~= 800 or bpp ~= 8 or stride < width then
        C.close(fd)
        error(string.format("unsupported framebuffer: %dx%d %dbpp stride=%d", width, height, bpp, stride))
    end

    if is_einkfb then
        require("ffi/einkfb_h")
    else
        require("ffi/mxcfb_kindle_h")
    end

    local fb_size = stride * height
    local map_size = page_align(fb_size)
    local data = C.mmap(nil, map_size, bor(C.PROT_READ, C.PROT_WRITE), C.MAP_SHARED, fd, 0)
    if tonumber(ffi.cast("intptr_t", data)) == C.MAP_FAILED then
        C.close(fd)
        error(errno_text("cannot mmap framebuffer"))
    end

    framebuffer = {
        fd = fd,
        data = data,
        bytes = ffi.cast("uint8_t *", data),
        width = width,
        height = height,
        stride = stride,
        map_size = map_size,
        driver = is_einkfb and "einkfb" or "mxcfb",
        inverted = is_einkfb,
        marker = 0,
    }
    if not is_einkfb then
        framebuffer.update = ffi.new("struct mxcfb_update_data")
        framebuffer.update.temp = C.TEMP_USE_AUTO
    end
    return framebuffer
end

function M.render_png(output, orientation, theme, target_epoch, battery_level, show_help, hour_mode)
    orientation = orientation or "landscape_right"
    theme = theme or "light"
    target_epoch = tonumber(target_epoch) or os.time()
    show_help = show_help == true or show_help == "1"
    hour_mode = hour_mode == "12" and "12" or "24"
    local canvas = render_full_canvas(orientation, theme, target_epoch, battery_level, show_help, hour_mode)
    local final = rotate_full(canvas, orientation)
    assert(final:getWidth() == 600 and final:getHeight() == 800,
        string.format("unexpected output dimensions: %dx%d", final:getWidth(), final:getHeight()))
    final:writePNG(assert(output, "missing output path"))
    if final ~= canvas then final:free() end
    canvas:free()
end

function M.prepare_partial(orientation, theme, current_epoch, target_epoch, hour_mode)
    orientation = orientation or "landscape_right"
    theme = theme or "light"
    current_epoch = assert(tonumber(current_epoch), "invalid current epoch")
    target_epoch = assert(tonumber(target_epoch), "invalid target epoch")
    hour_mode = hour_mode == "12" and "12" or "24"
    local fb = open_framebuffer()
    local logical, layout, region_x, region_y, region_width, region_height, changed_count =
        render_changed_digit_region(orientation, theme, current_epoch,
            target_epoch, hour_mode, fb.inverted)
    local physical = rotate_region(logical, orientation)
    if physical ~= logical then logical:free() end
    local x, y = physical_region_position(layout, orientation,
        region_x, region_y, region_width, region_height)
    local width, height = physical:getWidth(), physical:getHeight()
    assert(x >= 0 and y >= 0 and x + width <= fb.width and y + height <= fb.height,
        string.format("partial region out of bounds: %dx%d@%d,%d", width, height, x, y))
    if prepared and prepared.bb then prepared.bb:free() end
    prepared = {
        bb = physical,
        epoch = target_epoch,
        x = x,
        y = y,
        width = width,
        height = height,
        changed_count = changed_count,
    }
    return x, y, width, height, changed_count
end

function M.display_partial(target_epoch)
    target_epoch = assert(tonumber(target_epoch), "invalid display epoch")
    assert(prepared and prepared.epoch == target_epoch,
        string.format("prepared epoch mismatch: expected=%d actual=%s",
            target_epoch, prepared and tostring(prepared.epoch) or "missing"))
    local fb = open_framebuffer()
    local source = ffi.cast("uint8_t *", prepared.bb.data)
    for row = 0, prepared.height - 1 do
        local destination_offset = (prepared.y + row) * fb.stride + prepared.x
        ffi.copy(fb.bytes + destination_offset, source + row * prepared.bb.stride, prepared.width)
    end

    local refresh_start_cs = monotonic_centiseconds()
    if fb.driver == "einkfb" then
        local area = ffi.new("struct update_area_t[1]")
        area[0].x1 = prepared.x
        area[0].y1 = prepared.y
        area[0].x2 = prepared.x + prepared.width
        area[0].y2 = prepared.y + prepared.height
        area[0].which_fx = C.fx_update_partial
        area[0].buffer = nil
        if C.ioctl(fb.fd, C.FBIO_EINK_UPDATE_DISPLAY_AREA, area) == -1 then
            error(errno_text("FBIO_EINK_UPDATE_DISPLAY_AREA failed"))
        end
    else
        fb.marker = fb.marker + 1
        if fb.marker > 0x7FFFFFF0 then fb.marker = 1 end
        local update = fb.update
        update.update_region.left = prepared.x
        update.update_region.top = prepared.y
        update.update_region.width = prepared.width
        update.update_region.height = prepared.height
        update.waveform_mode = C.WAVEFORM_MODE_GL16_FAST
        update.update_mode = C.UPDATE_MODE_PARTIAL
        update.update_marker = fb.marker
        update.temp = C.TEMP_USE_AUTO
        update.flags = 0
        update.hist_bw_waveform_mode = C.WAVEFORM_MODE_DU
        update.hist_gray_waveform_mode = C.WAVEFORM_MODE_GC16_FAST
        if C.ioctl(fb.fd, C.MXCFB_SEND_UPDATE, update) == -1 then
            error(errno_text("MXCFB_SEND_UPDATE failed"))
        end
    end
    local refresh_end_cs = monotonic_centiseconds()
    return prepared.x, prepared.y, prepared.width, prepared.height,
        prepared.changed_count, refresh_start_cs, refresh_end_cs
end

function M.close()
    if prepared and prepared.bb then prepared.bb:free() end
    prepared = nil
    for _, card_bb in pairs(card_cache) do card_bb:free() end
    card_cache = {}
    for key, value in pairs(face_cache) do
        if type(value) == "table" then
            value.info:done()
            value.small:done()
            value.digit:done()
        else
            value:done()
        end
        face_cache[key] = nil
    end
    close_framebuffer()
end

return M
