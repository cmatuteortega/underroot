-- The title, the first thing up when the game opens: the name over the
-- night, the sprout on the ground and the network growing out under it, lit
-- by nutrients on their way up. Any key, click or tap sends the sprout down and
-- the home screen's choices up (src/ui/home.lua).

local M = require "src.models"
local Font = require "src.font"
local Sfx = require "src.sfx"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Pixels = require "src.ui.pixels"
local flair = require "src.ui.flair"
local Palette = require "src.palette"

local floor, max, min = math.floor, math.max, math.min
local color, text, centred, say = Draw.color, Draw.text, Draw.centred, Draw.say
local blit = Pixels.blit
local sound = flair.sound

local title = {}

function title.open()
    -- Back from the home screen, the network goes on from where it had got to.
    S.menu, title.t0, title.down = "title", title.t0 or flair.now(), nil
    S.mode, S.drag, S.selected = "grow", nil, nil
end

-- Tapped: the sprout and the ground under it go down, and the home screen's
-- choices come up in the sky they leave.
function title.leave()
    sound("select")
    title.down = flair.now()
    S.openHome()
end

-- The threads under the sprout, grown once for a screen size: each a list of
-- pixels { x, y, d }, d how far it is along the network from the sprout.
function title.grow(cx, gy)
    local rng = love.math.newRandomGenerator(7)
    local threads = {}
    local function thread(x, y, a, d, len, depth)
        local t = {}
        threads[#threads + 1] = t
        for _ = 1, len do
            a = a + (rng:random() - 0.5) * 0.5
            -- Down, never back up through the ground.
            a = max(0.15, min(math.pi - 0.15, a))
            x, y, d = x + math.cos(a), y + math.sin(a) * 0.7, d + 1
            if y >= S.vh - 1 or x < 0 or x >= S.vw then break end
            t[#t + 1] = { x = floor(x), y = floor(y), d = d }
            if depth < 3 and rng:random() < 0.035 then
                thread(x, y, a + (rng:random() < 0.5 and -1 or 1) * (0.5 + rng:random() * 0.6), d,
                    floor(len * (0.4 + rng:random() * 0.3)), depth + 1)
            end
        end
    end
    local reach = max(S.vw, S.vh)
    for k = 0, 6 do
        thread(cx, gy + 1, 0.3 + k * (math.pi - 0.6) / 6, 0, floor(reach * (0.3 + rng:random() * 0.25)), 0)
    end
    return threads
end

-- Where the ground is on the title, and how far it goes down once the title is
-- tapped, making room in the sky for the home screen's choices
-- (src/ui/home.lua); how long that takes, the name going up off the top
-- for the level picker, and the sprout sinking out of sight under the stars
-- dimming as a level is picked, before its loadout comes in.
title.DROP_TIME, title.NAME_TIME, title.SINK_TIME = 0.7, 0.35, 0.45
title.sinkTo = nil -- the level whose loadout opens once the sprout is out of sight
function title.ground() return floor(S.vh * 0.6), max(floor(S.vh * 0.6), floor(S.vh * 0.88)) end

-- How far down the ground is (0 where the title has it, 1 all the way), how
-- far up the name is (0 in place, 1 off the top) and how far the sprout has
-- sunk (0 not at all, 1 out of sight under a sky gone dark), each going
-- toward where the screen up wants it, a frame at a time. Back from the
-- loadout or a run, the sprout comes back up and the stars out.
title.f = { drop = 0, name = 0, sink = 0 }
local function toward(v, want, step)
    if v < want then return min(want, v + step) end
    return max(want, v - step)
end
local function smooth(f) return f * f * (3 - 2 * f) end

function title.ease()
    local now = flair.now()
    local dt = min(0.1, now - (title.last or now))
    title.last = now
    local f = title.f
    local drop, name = S.menu == "title" and 0 or 1, S.menu == true and 1 or 0
    local sink = (title.sinkTo or S.menu == "loadout") and 1 or 0
    -- The shots photograph where it is going, not on the way.
    if S.script then f.drop, f.name, f.sink = drop, name, sink end
    f.drop = toward(f.drop, drop, dt / title.DROP_TIME)
    f.name = toward(f.name, name, dt / title.NAME_TIME)
    f.sink = toward(f.sink, sink, dt / title.SINK_TIME)
end

-- How far down the ground is now, in pixels: the drop, and the sprout
-- sinking all the way under the bottom of the screen.
function title.drop()
    local gy, low = title.ground()
    local under = S.vh - low + M.sprout(0).oj + 2
    return floor((low - gy) * smooth(title.f.drop) + under * smooth(title.f.sink) + 0.5)
end

-- Where the name goes and how big (x, y, scale), where the lettering under it
-- ends, and where the top of the sprout is once the ground has dropped: what
-- the home screen fits its choices between.
function title.marks()
    local gy, low = title.ground()
    local name = "MYCELIO TD"
    local s = max(1, min(5, floor((S.vw - 24) / Font.width(name))))
    local x, y = floor((S.vw - Font.width(name) * s) / 2), max(S.inset.t + 8, floor(gy * 0.3) - 3 * s)
    return x, y, s, y + 6 * s + 11, low - M.sprout(0).oj
end

-- The night, the ground as far down as it has got, the network and the sprout
-- on it, and the name over it all, unless it has gone up: the backdrop the
-- title, the home screen, the settings and the level picker share, which stays
-- put while they slide (src/ui/slide.lua).
function title.backdrop()
    title.ease()
    local drop = title.drop()
    local T0 = title
    local age = flair.now() - (T0.t0 or 0)
    local cx = floor(S.vw / 2)
    local gy0 = title.ground()
    if T0.w ~= S.vw or T0.h ~= S.vh then T0.w, T0.h, T0.threads = S.vw, S.vh, T0.grow(cx, gy0) end
    local gy = gy0 + drop
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    title.stars(gy, 0, 0, 0, floor(smooth(title.f.sink) * 3 + 0.5))
    -- The ground: a lip of lit soil, then deep soil to the bottom.
    color("u")
    love.graphics.rectangle("fill", 0, gy, S.vw, S.vh - gy)
    color("n")
    love.graphics.rectangle("fill", 0, gy, S.vw, 2)
    color("m")
    love.graphics.rectangle("fill", 0, gy - 1, S.vw, 1)
    -- The network, reaching further every frame for its first few seconds, and
    -- nutrients running up it toward the sprout.
    local reach = age * 45
    for _, t in ipairs(T0.threads) do
        for _, p in ipairs(t) do
            if p.d > reach or p.y + drop >= S.vh then break end
            local lit = (p.d + age * 30) % 48 < 2
            color(lit and "l" or (p.d > reach - 3 and "l" or "c"))
            love.graphics.rectangle("fill", p.x, p.y + drop, 1, 1)
        end
    end
    blit(M.sprout(0), cx, gy)
    local _, _, _, under = title.marks()
    title.name(-floor(smooth(title.f.name) * (under + 2) + 0.5))
end

-- A few stars over ground at `gy`, each blinking on its own beat, strewn
-- down to where the ground ends up so the dropping ground uncovers more of
-- them; `dx`, `dy` moves them (round the screen across), none are drawn
-- above `top`, and each is `dim` steps darker (three and they are out). The
-- network's screen has the same night over its ground.
function title.stars(gy, dx, dy, top, dim)
    local _, low = title.ground()
    local age = flair.now() - (title.t0 or 0)
    local rng = love.math.newRandomGenerator(3)
    for _ = 1, floor(S.vw * low / 900) do
        local x, y, beat = rng:random(0, S.vw - 1), rng:random(0, low - 4), rng:random() * 6
        x, y = (x + dx) % S.vw, y + dy
        if y < gy - 4 and y >= top and (age + beat) % 6 > 0.4 then
            local k = rng:random() < 0.3 and "s" or "k"
            for _ = 1, dim or 0 do k = Palette.darker[k] end
            if k ~= "o" then
                color(k)
                love.graphics.rectangle("fill", x, y, 1, 1)
            end
        else
            rng:random()
        end
    end
end

-- The name, as big as the screen's width allows, on a teal shadow, and the
-- line under it; `dy` pixels down from its place.
function title.name(dy)
    local name = "MYCELIO TD"
    local x, y, s = title.marks()
    y = y + dy
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(s, s)
    color("c")
    Font.print(name, 0, 1)
    color("l")
    Font.print(name, 0, 0)
    love.graphics.pop()
    local sub = "A TOWER DEFENSE UNDER A SPROUT"
    text(sub, floor((S.vw - Font.width(sub)) / 2), y + 6 * s + 6, "t")
end

function title.draw()
    local age = flair.now() - (title.t0 or 0)
    if age % 1.2 < 0.8 then
        centred(say("PRESS ANY KEY", "TAP TO BEGIN"), S.vh - S.inset.b - 14, "w", "o")
    end
end

-- The title's own sounds: a patter as the network reaches out under the
-- sprout, then a drink each time the nutrients running up it get there.
function title.sounds()
    local T0 = title
    local age = flair.now() - (T0.t0 or 0)
    if age < 3 then
        local k = floor(age / 0.22)
        if k ~= T0.grew then T0.grew = k; Sfx.play("grow", 0, 0.35, 0.8 + age * 0.15) end
    else
        -- A nutrient is lit at the sprout when (d + age * 30) % 48 < 2 at d = 0.
        local k = floor(age * 30 / 48)
        if k ~= T0.drank then T0.drank = k; Sfx.play("drink", 0, 0.6) end
    end
end

-- Any key, click or tap goes on.
function title.hover() end
function title.under() end
function title.click() title.leave() end
function title.key() title.leave() end

return title
