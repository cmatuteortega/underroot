-- The title, the first thing up when the game opens: the name over the
-- night, the sprout on the ground and the network growing out under it, lit
-- by nutrients on their way up. Any key, click or tap goes on to the levels.

local M = require "src.models"
local Font = require "src.font"
local Sfx = require "src.sfx"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Pixels = require "src.ui.pixels"
local flair = require "src.ui.flair"

local floor, max, min = math.floor, math.max, math.min
local color, text, centred, say = Draw.color, Draw.text, Draw.centred, Draw.say
local blit = Pixels.blit
local sound = flair.sound

local title = {}

function title.open()
    S.menu, title.t0 = "title", flair.now()
    S.mode, S.drag, S.selected = "grow", nil, nil
end

function title.leave()
    sound("select")
    S.openMenu()
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

function title.draw()
    local T0 = title
    local age = flair.now() - (T0.t0 or 0)
    local cx, gy = floor(S.vw / 2), floor(S.vh * 0.6)
    if T0.w ~= S.vw or T0.h ~= S.vh then T0.w, T0.h, T0.threads = S.vw, S.vh, T0.grow(cx, gy) end
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    -- A few stars, each blinking on its own beat.
    local rng = love.math.newRandomGenerator(3)
    for _ = 1, floor(S.vw * gy / 900) do
        local x, y, beat = rng:random(0, S.vw - 1), rng:random(0, gy - 4), rng:random() * 6
        if (age + beat) % 6 > 0.4 then
            color(rng:random() < 0.3 and "s" or "k")
            love.graphics.rectangle("fill", x, y, 1, 1)
        end
    end
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
            if p.d > reach then break end
            local lit = (p.d + age * 30) % 48 < 2
            color(lit and "l" or (p.d > reach - 3 and "l" or "c"))
            love.graphics.rectangle("fill", p.x, p.y, 1, 1)
        end
    end
    blit(M.sprout(0), cx, gy)
    -- The name, as big as the screen's width allows, on a teal shadow.
    local name = "MYCELIO TD"
    local s = max(1, min(5, floor((S.vw - 24) / Font.width(name))))
    local x, y = floor((S.vw - Font.width(name) * s) / 2), max(S.inset.t + 8, floor(gy * 0.3) - 3 * s)
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
