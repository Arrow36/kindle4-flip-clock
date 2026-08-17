-- Render the custom flip clock with KOReader's proven graphics stack.
-- Run from /mnt/us/koreader so setupkoenv can resolve all native libraries.
require("setupkoenv")

local bit = require("bit")
local BB = require("ffi/blitbuffer")
local FT = require("ffi/freetype")
local band, bor, lshift = bit.band, bit.bor, bit.lshift

local output = assert(arg[1], "missing output path")
local orientation = arg[2] or "landscape_right"
local theme = arg[3] or "light"
local info_text = arg[4] or ""
local period = arg[5] or ""
local battery_level = tonumber(arg[6]) or 0
local top_digits = {arg[7] or "0", arg[8] or "0", arg[9] or "0", arg[10] or "0"}
local bottom_digits = {arg[11] or "0", arg[12] or "0", arg[13] or "0", arg[14] or "0"}
local show_help = arg[15] == "1"
local font_path = "/mnt/us/extensions/kclock/fonts/DouyinSansBold.ttf"

battery_level = math.max(0, math.min(100, battery_level))

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

local function make_card(digit, face, width, height, paper, card, digit_color, radius)
    local card_bb = BB.new(width, height, BB.TYPE_BB8)
    card_bb:fill(paper)
    card_bb:paintRoundedRect(0, 0, width, height, card, radius)
    local text_width, text_top, text_bottom = measure_text(face, digit)
    local baseline = math.floor((height - text_top - text_bottom) / 2 + text_top + 2)
    draw_text(card_bb, face, digit, math.floor((width - text_width) / 2), baseline, digit_color)
    return card_bb
end

local light = theme ~= "dark"
local paper = BB.Color8(light and 0xF2 or 0x11)
local ink = BB.Color8(light and 0x17 or 0xEE)
local card = BB.Color8(light and 0x17 or 0xEE)
local digit_color = BB.Color8(light and 0xF2 or 0x11)
local seam = BB.Color8(light and 0x68 or 0x77)

local landscape = orientation == "landscape_right" or orientation == "landscape_left"
local logical_width, logical_height = landscape and 800 or 600, landscape and 600 or 800
local canvas = BB.new(logical_width, logical_height, BB.TYPE_BB8)
canvas:fill(paper)

local info_size = landscape and 28 or 21
local small_size = landscape and 25 or 23
local digit_size = landscape and 270 or 235
local info_face = FT.newFaceSize(font_path, info_size)
local small_face = FT.newFaceSize(font_path, small_size)
local digit_face = FT.newFaceSize(font_path, digit_size)

local card_y, card_width, card_height, radius, colon_x
local card_x
if landscape then
    card_y, card_width, card_height, radius, colon_x = 170, 178, 260, 12, 400
    card_x = {10, 194, 428, 612}
    draw_text(canvas, info_face, info_text, 32, 55, ink)
    draw_right_aligned(canvas, small_face, period, 766, 145, ink)
else
    card_y, card_width, card_height, radius, colon_x = 260, 128, 230, 10, 300
    card_x = {6, 140, 332, 466}
    draw_text(canvas, info_face, info_text, 25, 48, ink)
    draw_right_aligned(canvas, small_face, period, 570, 235, ink)
end

local half = math.floor(card_height / 2)
for index = 1, 4 do
    local top_card = make_card(top_digits[index], digit_face, card_width, card_height,
        paper, card, digit_color, radius)
    local bottom_card = make_card(bottom_digits[index], digit_face, card_width, card_height,
        paper, card, digit_color, radius)
    canvas:blitFrom(top_card, card_x[index], card_y, 0, 0, card_width, half)
    canvas:blitFrom(bottom_card, card_x[index], card_y + half, 0, half,
        card_width, card_height - half)
    top_card:free()
    bottom_card:free()
    canvas:paintRect(card_x[index], card_y + half - 1, card_width, 2, seam)
end

if landscape then
    canvas:paintCircle(colon_x, 260, 9, ink)
    canvas:paintCircle(colon_x, 340, 9, ink)
    local battery_text = string.format("%d.0%%", battery_level)
    draw_right_aligned(canvas, small_face, battery_text, 731, 560, ink)
    canvas:paintBorder(744, 536, 42, 25, 3, ink)
    canvas:paintRect(787, 543, 4, 11, ink)
    canvas:paintRect(748, 540, math.floor(34 * battery_level / 100), 17, ink)
else
    canvas:paintCircle(colon_x, 340, 8, ink)
    canvas:paintCircle(colon_x, 410, 8, ink)
    local battery_text = string.format("%d.0%%", battery_level)
    draw_right_aligned(canvas, small_face, battery_text, 531, 755, ink)
    canvas:paintBorder(544, 732, 42, 25, 3, ink)
    canvas:paintRect(587, 739, 4, 11, ink)
    canvas:paintRect(548, 736, math.floor(34 * battery_level / 100), 17, ink)
end

if show_help then
    local orientation_names = {
        portrait = "竖屏·按键在下",
        portrait_down = "竖屏·按键在上",
        landscape_right = "横屏·按键在右",
        landscape_left = "横屏·按键在左",
    }
    local hour_name = arg[16] == "12" and "12 小时制" or "24 小时制"
    local theme_name = light and "浅色" or "深色"
    local box_x, box_y, box_width, box_height
    local text_x, header_baseline, line_baseline, line_gap
    if landscape then
        box_x, box_y, box_width, box_height = 65, 55, 670, 490
        text_x, header_baseline, line_baseline, line_gap = 95, 105, 150, 36
    else
        box_x, box_y, box_width, box_height = 35, 65, 530, 670
        text_x, header_baseline, line_baseline, line_gap = 62, 118, 170, 50
    end

    canvas:paintRoundedRect(box_x, box_y, box_width, box_height, paper, 16)
    canvas:paintBorder(box_x, box_y, box_width, box_height, 4, ink)
    local header_face = FT.newFaceSize(font_path, landscape and 34 or 29)
    draw_text(canvas, header_face, "Flip Clock 快捷键", text_x, header_baseline, ink)

    local lines = {
        "屏幕方向：" .. (orientation_names[orientation] or orientation),
        "时间制式：" .. hour_name,
        "显示主题：" .. theme_name,
        "",
        "左侧上一页 / 下一页：切换屏幕方向",
        "右侧可用翻页键：切换浅色 / 深色",
        "五向键确认：切换 12 / 24 小时制",
        "菜单键：关闭说明",
        "返回键 / Home：退出时钟",
    }
    for _, line in ipairs(lines) do
        if line ~= "" then
            draw_text(canvas, small_face, line, text_x, line_baseline, ink)
        end
        line_baseline = line_baseline + line_gap
    end
    header_face:done()
end

local final = canvas
if orientation == "landscape_right" then
    final = canvas:rotatedCopy(90)
elseif orientation == "landscape_left" then
    final = canvas:rotatedCopy(270)
elseif orientation == "portrait_down" then
    final = canvas:rotatedCopy(180)
end

assert(final:getWidth() == 600 and final:getHeight() == 800,
    string.format("unexpected output dimensions: %dx%d", final:getWidth(), final:getHeight()))
final:writePNG(output)

info_face:done()
small_face:done()
digit_face:done()
if final ~= canvas then final:free() end
canvas:free()
