-- Lettering and boxes on the HUD's picture: the palette's colours, the
-- font, words broken to fit, and the few measures every screen lays out by.

local T = require "src.tracer"
local Font = require "src.font"
local S = require "src.ui.state"

local floor = math.floor
local IDX = T.IDX

local function inside(x, y, rx, ry, rw, rh) return x >= rx and y >= ry and x < rx + rw and y < ry + rh end

-- Wider than it is tall: panels go down the side rather than across.
local function wide() return S.vw > S.vh end

-- Words broken into lines no wider than w.
local function wrapLines(str, w)
    local lines, line = {}, ""
    for word in str:gmatch("%S+") do
        local try = line == "" and word or line .. " " .. word
        if Font.width(try) > w and line ~= "" then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function number(v)
    if v == floor(v) then return tostring(v) end
    return string.format("%.1f", v)
end

local function color(k) love.graphics.setColor(T.RGB[IDX[k]]) end

local function box(x, y, w, h, fill, edge)
    color(edge or "o")
    love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2)
    color(fill or "u")
    love.graphics.rectangle("fill", x, y, w, h)
end

local function text(s, x, y, k)
    color(k or "w")
    Font.print(s, x, y)
end

local function label(s, x, y, k, fill)
    box(x - 2, y - 2, Font.width(s) + 4, 9, fill or "u")
    text(s, x, y, k)
end

-- Centred across the screen, or about `mid`.
local function centred(s, y, k, fill, mid)
    label(s, floor((mid or S.vw / 2) - Font.width(s) / 2), y, k, fill)
end

-- The same help in a finger's words: no keys, no right button, tap not click.
local function say(m, t) return S.touch and t or m end

-- Words broken into lines `w` wide, from (x, y) down, seven pixels a line.
local function wrap(s, x, y, w, k)
    local line = ""
    for word in s:gmatch("%S+") do
        local try = line == "" and word or line .. " " .. word
        if Font.width(try) > w then
            text(line, x, y, k)
            line, y = word, y + 7
        else
            line = try
        end
    end
    text(line, x, y, k)
    return y + 7
end

return {
    color = color,
    box = box,
    text = text,
    label = label,
    centred = centred,
    wrap = wrap,
    wrapLines = wrapLines,
    number = number,
    say = say,
    inside = inside,
    wide = wide,
}
