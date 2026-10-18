-- The settings, from the home screen and back to it, over the same night:
-- for now how loud the sound is (the V key goes round the same three).

local Font = require "src.font"
local Sfx = require "src.sfx"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local flair = require "src.ui.flair"
local audio = require "src.ui.audio"
local Title = require "src.ui.title"

local floor = math.floor
local box, text, inside = Draw.box, Draw.text, Draw.inside
local sound = flair.sound

local settings = {}

-- The sound's three levels, left to right.
settings.SOUND = {
    { level = 1, name = "LOUD" },
    { level = 0.5, name = "QUIET" },
    { level = 0, name = "OFF" },
}

function settings.open()
    S.menu = "settings"
    sound("panel")
end

function settings.close()
    sound("back")
    S.openHome()
end

-- BACK top left; the sound's row in the sky between the name and the sprout.
function settings.layout()
    local _, _, _, top, bottom = Title.marks()
    local L = { back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 }, sound = {} }
    local W, H, gap = 40, 14, 4
    local n = #settings.SOUND
    local x0 = floor((S.vw - (n * W + (n - 1) * gap)) / 2)
    L.head = floor(top + (bottom - top - (H + 12)) / 2)
    for k = 1, n do
        L.sound[k] = { x = x0 + (k - 1) * (W + gap), y = L.head + 12, w = W, h = H, n = k }
    end
    return L
end

settings.backdrop = Title.backdrop

function settings.draw()
    local L = settings.layout()
    local b = L.back
    box(b.x, b.y, b.w, b.h, S.hover.back and "n" or "u", S.hover.back and "t" or "k")
    text("BACK", b.x + floor((b.w - Font.width("BACK")) / 2), b.y + 4, "w")
    local head = "SOUND"
    text(head, floor((S.vw - Font.width(head)) / 2), L.head, "t")
    for k, c in ipairs(L.sound) do
        local opt = settings.SOUND[k]
        local chosen, on = Sfx.level == opt.level, S.hover.sound == k
        box(c.x, c.y, c.w, c.h, on and "n" or (chosen and "d" or "u"), chosen and "g" or (on and "t" or "c"))
        text(opt.name, c.x + floor((c.w - Font.width(opt.name)) / 2), c.y + 5, chosen and "g" or "w")
    end
end

function settings.hover(mx, my)
    local L = settings.layout()
    if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then S.hover.back = true return end
    for k, c in ipairs(L.sound) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.sound = k return end
    end
end

function settings.under()
    if S.hover.back then return function() local b = settings.layout().back return b.x, b.y, b.w, b.h end end
    local k = S.hover.sound
    if k then return function() local c = settings.layout().sound[k] return c.x, c.y, c.w, c.h end end
end

local function setSound(k)
    Sfx.level = settings.SOUND[k].level
    audio.save()
    sound("on")
end

function settings.click(b)
    if b == 2 or S.hover.back then settings.close()
    elseif S.hover.sound then setSound(S.hover.sound) end
end

function settings.key(key)
    if key == "escape" or key == "backspace" then settings.close() return end
    -- Left and right go along the row.
    local now = 1
    for k, opt in ipairs(settings.SOUND) do if Sfx.level == opt.level then now = k end end
    if key == "left" and now > 1 then setSound(now - 1)
    elseif key == "right" and now < #settings.SOUND then setSound(now + 1) end
end

return settings
