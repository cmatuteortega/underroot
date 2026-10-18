-- The level picker, from the home screen (src/ui/home.lua), with BACK to it
-- top left and the spores in the bank beside it, under the same night with
-- the sprout down at the bottom (the name goes up off the top for it).

local D = require "src.defs"
local Font = require "src.font"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local flair = require "src.ui.flair"
local Loadout = require "src.ui.loadout"
local Title = require "src.ui.title"

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local box, text, centred, wrap, say, inside = Draw.box, Draw.text, Draw.centred, Draw.wrap, Draw.say, Draw.inside
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

-- The challenge switch goes OFF, then through each challenge open, and back.
local function toggleChallenge()
    local open = Profile.challenges()
    local nxt = open[1]
    for k, c in ipairs(open) do if c.id == S.challenge then nxt = open[k + 1] end end
    S.challenge = nxt and nxt.id or false
    sound(S.challenge and "on" or "off")
end

local function backButton() return { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 } end

-- Back to the run if one is still being played, else to the home screen.
local function back()
    sound("back")
    if S.game and S.game.phase ~= "lost" and S.game.phase ~= "won" then S.menu = nil else S.openHome() end
end

-- A level picked: the sprout sinks out of sight and the stars go out
-- (src/ui/title.lua), and then its loadout comes in. The shots go straight there.
local function pick(n)
    sound("select")
    if S.script then Loadout.open(n) else Title.sinkTo = n end
end

local function draw()
    if Title.sinkTo and Title.f.sink >= 1 then
        local n = Title.sinkTo
        Title.sinkTo = nil
        Loadout.open(n)
    end
    local cards, switch = levelCards()
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
        local s = "CHALLENGE: " .. (S.challenge and D.CHALLENGE[S.challenge].name or "OFF")
        text(s, c.x + floor((c.w - Font.width(s)) / 2), c.y + 5, S.challenge and "r" or "w")
        if S.challenge then
            centred(D.CHALLENGE[S.challenge].blurb, c.y + c.h + 6, "r", "o")
        elseif S.hover.challenge then
            centred("A LAST WAVE ON ANY LEVEL, A BOSS IN IT", c.y + c.h + 6, "r", "o")
        end
    end
    local bb = backButton()
    box(bb.x, bb.y, bb.w, bb.h, S.hover.back and "n" or "u", S.hover.back and "t" or "k")
    text("BACK", bb.x + floor((bb.w - Font.width("BACK")) / 2), bb.y + 4, "w")
    text("SPORES " .. Profile.spores, bb.x + bb.w + 6, S.inset.t + 7, "t")
    local hintY = S.vh - S.inset.b - 12
    centred(say("1-" .. #D.LEVELS .. " OR CLICK A LEVEL", "TAP A LEVEL") .. (Profile.challengeOpen() and say("   C: CHALLENGE", "") or "")
        .. say("   ESC: BACK", ""), hintY, "s", "o")
end

-- What is pointed at: a level, the challenge switch or BACK.
local function hover(mx, my)
    if Title.sinkTo then return end
    local cards, switch = levelCards()
    for k, c in ipairs(cards) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.level = k return end
    end
    local bb = backButton()
    if inside(mx, my, bb.x, bb.y, bb.w, bb.h) then S.hover.back = true return end
    if Profile.challengeOpen() and inside(mx, my, switch.x, switch.y, switch.w, switch.h) then S.hover.challenge = true end
end

local function under()
    if S.hover.level then
        local c = levelCards()[S.hover.level]
        return function() return c.x, c.y, c.w, c.h end
    end
    if S.hover.back then return function() local c = backButton() return c.x, c.y, c.w, c.h end end
    if S.hover.challenge then
        local _, c = levelCards()
        return function() return c.x, c.y, c.w, c.h end
    end
end

local function click(b)
    if Title.sinkTo then return end
    if b == 2 or S.hover.back then back() return end
    if S.hover.level and Profile.levelOpen(S.hover.level) then pick(S.hover.level)
    elseif S.hover.level then deny()
    elseif S.hover.challenge then toggleChallenge() end
end

local function key(key)
    if Title.sinkTo then return end
    local n = tonumber(key)
    if n and D.LEVELS[n] then
        if Profile.levelOpen(n) then pick(n) else deny() end
    end
    if key == "c" and Profile.challengeOpen() then toggleChallenge() end
    if key == "escape" or key == "backspace" then back() end
end

return {
    backdrop = Title.backdrop,
    draw = draw,
    hover = hover,
    under = under,
    click = click,
    key = key,
}
