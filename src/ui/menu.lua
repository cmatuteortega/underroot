-- The level picker, with the encyclopedia's button top left and the sound's
-- switch top right.

local D = require "src.defs"
local Font = require "src.font"
local Sfx = require "src.sfx"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local flair = require "src.ui.flair"
local audio = require "src.ui.audio"
local codex = require "src.ui.codex"
local Loadout = require "src.ui.loadout"

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local color, box, text, centred, wrap, say, inside = Draw.color, Draw.box, Draw.text, Draw.centred, Draw.wrap, Draw.say, Draw.inside
local sound, deny = flair.sound, flair.deny

-- The level picker: a card a level, in rows of as many as fit across (three
-- on a wide screen, two rows of them; down the middle on a narrow one), and
-- the challenge switch under them once it is open.
local LW, LH = 124, 50
local function levelCards()
    local n = #D.LEVELS
    local cols = max(1, min(3, floor((S.vw - S.inset.l - S.inset.r - 8 + 6) / (LW + 6))))
    local rows = ceil(n / cols)
    local gap = cols == 1 and 4 or 6
    local cards = {}
    local y0 = floor(S.vh / 2 - (rows * LH + (rows - 1) * gap) / 2) - 8
    for k = 1, n do
        local row, col = floor((k - 1) / cols), (k - 1) % cols
        local across = min(cols, n - row * cols)
        local x0 = floor((S.vw - (across * LW + (across - 1) * 6)) / 2)
        cards[k] = { x = x0 + col * (LW + 6), y = y0 + row * (LH + gap), w = LW, h = LH, n = k }
    end
    y0 = y0 + rows * (LH + gap) + 4
    local switch = { x = floor((S.vw - LW) / 2), y = y0, w = LW, h = 16, challenge = true }
    return cards, switch
end

local function draw()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local cards, switch = levelCards()
    centred("MYCELIO TD", cards[1].y - 30, "g", "o")
    centred("WHERE DOES THE SPROUT COME UP?", cards[1].y - 18, "t", "o")
    for k, c in ipairs(cards) do
        local l = D.LEVELS[k]
        local open, on = Profile.levelOpen(k), S.hover.level == k
        box(c.x, c.y, c.w, c.h, on and open and "n" or "u", Profile.won[l.id] and "g" or (open and (on and "l" or "c") or "k"))
        text(k .. "  " .. l.name, c.x + 4, c.y + 4, open and "w" or "k")
        if not open then
            text("WIN " .. D.LEVELS[k - 1].name, c.x + 4, c.y + 14, "r")
            text("TO OPEN IT", c.x + 4, c.y + 21, "r")
        else
            local y = wrap(l.idea, c.x + 4, c.y + 14, c.w - 8, "t")
            wrap("BOSS: " .. l.boss, c.x + 4, y + 1, c.w - 8, "r")
            local tag = Profile.won[l.id] and "WON" or (#l.waves .. " WAVES")
            text(tag, c.x + c.w - Font.width(tag) - 4, c.y + c.h - 8, Profile.won[l.id] and "g" or "s")
            -- The endless record, bottom left, once there is one.
            if Profile.records[l.id] then text("BEST " .. Profile.records[l.id], c.x + 4, c.y + c.h - 8, "r") end
        end
    end
    if Profile.challengeOpen() then
        local c = switch
        box(c.x, c.y, c.w, c.h, S.hover.challenge and "n" or "u", S.challenge and "r" or "k")
        local s = "CHALLENGE: " .. (S.challenge and "ON" or "OFF")
        text(s, c.x + floor((c.w - Font.width(s)) / 2), c.y + 5, S.challenge and "r" or "w")
        if S.hover.challenge or S.challenge then
            centred("A LAST WAVE ON ANY LEVEL: THE BOMBARDIER BEETLE", c.y + c.h + 6, "r", "o")
        end
    end
    local cb = codex.button()
    box(cb.x, cb.y, cb.w, cb.h, S.hover.codex and "n" or "u", S.hover.codex and "t" or "c")
    text("ENCYCLOPEDIA", cb.x + 4, cb.y + 4, "w")
    text("SPORES " .. Profile.spores, cb.x + cb.w + 6, S.inset.t + 7, "t")
    local sw = audio.switch()
    local lv = Sfx.level >= 1 and "LOUD" or (Sfx.level > 0 and "QUIET" or "OFF")
    box(sw.x, sw.y, sw.w, sw.h, S.hover.sound and "n" or "u", Sfx.level > 0 and "c" or "k")
    local st = "SOUND " .. lv
    text(st, sw.x + floor((sw.w - Font.width(st)) / 2), sw.y + 3, Sfx.level > 0 and "l" or "k")
    local hintY = S.vh - S.inset.b - 12
    centred(say("1-" .. #D.LEVELS .. " OR CLICK A LEVEL", "TAP A LEVEL") .. (Profile.challengeOpen() and say("   C: CHALLENGE", "") or "")
        .. say("   E: ENCYCLOPEDIA", ""), hintY, "s", "o")
end

-- What is pointed at: a level, the challenge switch, the encyclopedia or the sound.
local function hover(mx, my)
    local cards, switch = levelCards()
    for k, c in ipairs(cards) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.level = k return end
    end
    local cb = codex.button()
    if inside(mx, my, cb.x, cb.y, cb.w, cb.h) then S.hover.codex = true return end
    if Profile.challengeOpen() and inside(mx, my, switch.x, switch.y, switch.w, switch.h) then S.hover.challenge = true end
    local sw = audio.switch()
    if inside(mx, my, sw.x, sw.y, sw.w, sw.h) then S.hover.sound = true end
end

local function under()
    if S.hover.level then
        local c = levelCards()[S.hover.level]
        return function() return c.x, c.y, c.w, c.h end
    end
    if S.hover.codex then return function() local c = codex.button() return c.x, c.y, c.w, c.h end end
    if S.hover.challenge then
        local _, c = levelCards()
        return function() return c.x, c.y, c.w, c.h end
    end
    if S.hover.sound then
        local c = audio.switch()
        return function() return c.x, c.y, c.w, c.h end
    end
end

local function click(b)
    if S.hover.codex then codex.open() return end
    if S.hover.level and Profile.levelOpen(S.hover.level) then sound("select"); Loadout.open(S.hover.level)
    elseif S.hover.level then deny()
    elseif S.hover.challenge then S.challenge = not S.challenge; sound(S.challenge and "on" or "off")
    elseif S.hover.sound then Sfx.cycle(); audio.save(); sound("on") end
end

local function key(key)
    if key == "e" then codex.open() return end
    local n = tonumber(key)
    if n and D.LEVELS[n] then
        if Profile.levelOpen(n) then sound("select"); Loadout.open(n) else deny() end
    end
    if key == "c" and Profile.challengeOpen() then S.challenge = not S.challenge; sound(S.challenge and "on" or "off") end
    if key == "escape" and S.game then sound("back"); S.menu = nil end
end

return {
    draw = draw,
    hover = hover,
    under = under,
    click = click,
    key = key,
}
