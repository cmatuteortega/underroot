-- The ending: the last level (the Compost Heap) won for the first time gets
-- its own moment before the won screen's buttons. Under the night the sprout
-- grows to twice its size; then the mycelium runs out from under it to every
-- place the game has been, a node a level, each lighting up with its name and
-- a plant coming up over it, until it is under the whole garden; then the
-- garden goes down out of sight and the credits roll up (src/ui/credits.lua),
-- and last, what is open now: challenge mode. A tap goes on to the next part;
-- back (Esc) leaves it. From a run it goes back to the run's won screen, from
-- the credits back to them.

local D = require "src.defs"
local M = require "src.models"
local Font = require "src.font"
local Sfx = require "src.sfx"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Pixels = require "src.ui.pixels"
local flair = require "src.ui.flair"
local Title = require "src.ui.title"
local credits = require "src.ui.credits"
local Lang = require "src.lang"
local tr, trf = Lang.t, Lang.f

local floor, max, min, sin = math.floor, math.max, math.min, math.sin
local color, text, centred, say = Draw.color, Draw.text, Draw.centred, Draw.say
local blit = Pixels.blit

local ending = {}

-- When each part starts, in seconds from the opening: the sprout grows, the
-- threads set out (and run REACH pixels a second), the words once they are
-- all there, the garden going down and the credits.
ending.GROW, ending.THREADS, ending.REACH, ending.WORDS, ending.SINK = 1.5, 2.6, 90, 1.2, 4.5

function ending.open()
    ending.from = S.menu or "run"
    ending.t0 = flair.now()
    ending.lit = {}
    ending.grown, ending.done = false, false
    S.menu = "ending"
    Sfx.play("won", 0, 0.8)
end

function ending.close()
    flair.sound("back")
    if ending.from == "run" then S.menu = nil else S.menu = ending.from end
end

local function age() return flair.now() - (ending.t0 or 0) end
local function smooth(f) f = max(0, min(1, f)) return f * f * (3 - 2 * f) end

-- The garden for this screen size: the ground's line, the sprout's place and
-- a node a level spread across under the ground (three rows of depth, so their
-- names have room), each with the thread to it from under the sprout, a list
-- of pixels { x, y, d } with d how far along it is.
local garden
local function layout()
    if garden and garden.w == S.vw and garden.h == S.vh and garden.lang == Lang.code then return garden end
    local gy = floor(S.vh * 0.5)
    local cx = floor(S.vw / 2)
    local n = #D.LEVELS
    local m = 16
    local G = { w = S.vw, h = S.vh, lang = Lang.code, gy = gy, cx = cx, nodes = {}, long = 0 }
    local seeds = {}
    for _, sd in ipairs(D.SEEDS) do seeds[#seeds + 1] = sd.id end
    for k, l in ipairs(D.LEVELS) do
        local x = floor(m + (k - 1) * (S.vw - 2 * m) / max(1, n - 1) + 0.5)
        local y = gy + 16 + ((k - 1) % 3) * 12
        local name = l.name
        -- Its article left off, on a narrow screen.
        if S.vw < 360 then for _, a in ipairs({ "THE ", "EL ", "LA " }) do name = name:gsub("^" .. a, "") end end
        local path = {}
        local x0, y0 = cx, gy + 2
        local len = max(1, floor(math.sqrt((x - x0) ^ 2 + (y - y0) ^ 2)))
        for s = 0, len do
            local f = s / len
            -- A wobble across it, gone at either end, so no two run alike.
            local wob = sin(f * math.pi) * sin(f * 9 + k * 1.7) * 4
            local px = x0 + (x - x0) * f
            local py = y0 + (y - y0) * f + wob + sin(f * math.pi) * 6
            path[#path + 1] = { x = floor(px + 0.5), y = floor(py + 0.5), d = s }
        end
        G.long = max(G.long, len)
        G.nodes[k] = { x = x, y = y, name = name, path = path, len = len, seed = seeds[(k - 1) % #seeds + 1],
            centre = math.abs(x - cx) < 6 }
    end
    garden = G
    return G
end

-- Seconds until each part, now the garden's size is known.
local function times()
    local G = layout()
    local all = ending.THREADS + G.long / ending.REACH
    local words = all + ending.WORDS
    local sink = words + ending.SINK
    return all, words, sink
end

-- The challenges the last level opens, by name.
local function opened()
    local list = {}
    for _, c in ipairs(D.CHALLENGES) do
        if c.won == D.LEVELS[#D.LEVELS].id then list[#list + 1] = c end
    end
    return list
end

function ending.draw()
    local t = age()
    local G = layout()
    local all, _, sink = times()
    local down = floor(smooth((t - sink) / 1.6) * (S.vh - G.gy + 70))
    local gy = G.gy + down
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    Title.stars(gy, 0, 0, 0, 0)
    color("u")
    love.graphics.rectangle("fill", 0, gy, S.vw, S.vh - gy)
    color("n")
    love.graphics.rectangle("fill", 0, gy, S.vw, 2)
    color("m")
    love.graphics.rectangle("fill", 0, gy - 1, S.vw, 1)

    -- The threads, as far as they have run, nutrients running up them; each
    -- node lit, named and planted once its thread is there.
    local reach = (t - ending.THREADS) * ending.REACH
    for k, nd in ipairs(G.nodes) do
        for _, p in ipairs(nd.path) do
            if p.d > reach then break end
            local y = p.y + down
            if y < S.vh then
                local lit = (nd.len - p.d + t * 30) % 40 < 2
                color(lit and "l" or (p.d > reach - 3 and "l" or "c"))
                love.graphics.rectangle("fill", p.x, y, 1, 1)
            end
        end
        if reach >= nd.len then
            if not ending.lit[k] then
                ending.lit[k] = true
                Sfx.play("linked", (nd.x / S.vw) * 2 - 1, 0.7, 0.8 + k * 0.05)
            end
            local y = nd.y + down
            color("l")
            love.graphics.rectangle("fill", nd.x - 1, y - 1, 3, 3)
            color("w")
            love.graphics.rectangle("fill", nd.x, y, 1, 1)
            local nx = max(S.inset.l + 1, min(S.vw - S.inset.r - Font.width(nd.name) - 1, nd.x - floor(Font.width(nd.name) / 2)))
            if y + 4 < S.vh then text(nd.name, nx, y + 4, "t") end
            if not nd.centre then blit(M.sprout(0, nd.seed), nd.x, gy) end
        end
    end
    -- The sprout in the middle, twice as big once it has grown.
    local seed = Profile.sown[D.LEVELS[#D.LEVELS].id]
    local pic = M.sprout(0, seed)
    if t >= ending.GROW then
        if not ending.grown then ending.grown = true; Sfx.play("grow", 0, 1, 0.7) end
        love.graphics.push()
        love.graphics.translate(G.cx, gy)
        love.graphics.scale(2, 2)
        blit(pic, 0, 0)
        love.graphics.pop()
    else
        blit(pic, G.cx, gy)
    end

    -- The words over it.
    local wy = S.inset.t + floor(S.vh * 0.08) - down
    if t > 0.4 and wy > -10 then centred(tr("THE SPROUT HAS GROWN"), wy, "g", "o") end
    if t > all and wy + 14 > -10 then
        centred(tr("AND THE MYCELIUM IS UNDER THE WHOLE GARDEN,"), wy + 14, "w", "o")
        centred(trf("FROM %s TO %s", D.LEVELS[1].name, D.LEVELS[#D.LEVELS].name), wy + 24, "w", "o")
    end

    -- The credits, rolling up once the garden is going down, then what is open.
    -- Held once its last line is a little over half way up.
    local rolled = min((t - sink - 0.6) * credits.SPEED, S.vh + credits.height() - floor(S.vh * 0.45) + 1)
    if rolled > 0 then
        local y = credits.roll(floor(S.vh - rolled))
        if y < floor(S.vh * 0.45) then
            local cy = max(y + 10, floor(S.vh * 0.45))
            for n, c in ipairs(opened()) do
                centred(trf("CHALLENGE MODE IS OPEN: THE %s", c.name), cy + (n - 1) * 11, "r", "o")
            end
            if floor(t * 1.5) % 2 == 0 then centred(tr(say("CLICK TO GO ON", "TAP TO GO ON")), cy + #opened() * 11 + 8, "s", "o") end
            ending.done = true
        end
    end
    if not S.touch and not ending.done then text(tr("ESC: SKIP"), S.vw - S.inset.r - Font.width(tr("ESC: SKIP")) - 3, S.vh - S.inset.b - 8, "k") end
end

-- A tap goes on to the next part; once it is all there, it is over.
function ending.next()
    local t = age()
    local all, _, sink = times()
    if ending.done then ending.close()
    elseif t < all then ending.t0 = flair.now() - all
    elseif t < sink then ending.t0 = flair.now() - sink
    else
        -- On through the credits to their end.
        ending.t0 = flair.now() - (sink + 0.6 + (S.vh + credits.height() - floor(S.vh * 0.45)) / credits.SPEED)
    end
end

function ending.hover() end
function ending.under() end
function ending.click(b)
    if b == 2 then ending.close() else ending.next() end
end
function ending.key(key)
    if key == "escape" or key == "backspace" then ending.close()
    elseif key == "space" or key == "return" then ending.next() end
end

return ending
