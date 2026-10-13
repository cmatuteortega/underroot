-- Everything that is painted on its own rather than into the board: the sprout,
-- the fruiting bodies, the enemies and what is left of them.
--
-- Survive School's lesson, straight across: a pose is *numbers*, not a held
-- picture. Each model here is a function from a few numbers (a heading, a leg
-- phase, how far a puffball is squashed) to a list of ellipsoids, and its
-- picture is asked for those numbers rounded to a few steps and kept under that
-- key. Two hundred ants walking the trail cost what one costs: they are all
-- looking the same handful of pictures up.
--
-- What does not need a picture of its own does not get one. A starved mushroom
-- is its own picture laid down one step darker, a dormant one two, and a thing
-- that has just been hit is laid down in cream -- remaps at stamp time (see
-- T.DARKER, T.FLASH), not paintings.
--
-- And what was learned on the whistle holds: don't model a face. An ant's eyes,
-- a puffball's warts, a pillbug's plates are printed on the ball at the hit
-- point, not built.

local T = require "src.tracer"
local A = T.Affine

local sin, cos, atan2, abs, floor, sqrt = math.sin, math.cos, math.atan2, math.abs, math.floor, math.sqrt
local ell, RAMP, IDX = T.ell, T.RAMP, T.IDX
local TAU = 2 * math.pi

local M = {}

local cache = {}
local function kept(key, build)
    local p = cache[key]
    if not p then
        p = T.paint(build(), 2)
        cache[key] = p
    end
    return p
end
M.count = function()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end

-- Turns a list of parts by heading h (model front, +x, points along (cos h, sin h)
-- on the ground) and whatever else is handed in, outermost first.
local function place(parts, ...)
    local m = select("#", ...) == 1 and ... or A.mul(...)
    for _, p in ipairs(parts) do p.at = A.mul(m, p.at) end
    return parts
end
local function heading(h) return A.rotY(-h) end

local function step(h, n) return floor(((h % TAU) / TAU) * n + 0.5) % n end

-- Points on a unit ball, scattered evenly enough, for warts and spots.
local SPOTS = {}
for n = 0, 13 do
    local a, e = n * 2.39996, math.asin(-0.2 + (n % 7) * 0.17)
    SPOTS[#SPOTS + 1] = { cos(a) * cos(e), sin(e), sin(a) * cos(e) }
end
local function spotted(limit, key)
    return function(ux, uy, uz, lev)
        if lev == 1 then return end
        for _, d in ipairs(SPOTS) do
            if ux * d[1] + uy * d[2] + uz * d[3] > limit then return key end
        end
    end
end

--- the sprout -------------------------------------------------------------------

-- Two seed leaves on a stem, the brightest thing there is. `wilt` 0..1 droops
-- the leaves and bends the stem as the Heart is hurt: you see it before the
-- number tells you.
function M.sprout(wilt)
    local ws = floor(wilt * 4 + 0.5)
    return kept("sprout" .. ws, function()
        local w = ws / 4
        local up = 0.42 - 0.95 * w
        local parts = {
            { id = 1, ramp = RAMP.sprout, at = ell(0, 6, 0, 1.2, 6, 1.2) },
            { id = 2, ramp = RAMP.sprout, at = A.mul(A.move(0, 12, 0), A.rotZ(up), A.move(3.6, 0, 0), A.scale(4.2, 0.9, 2.3)),
                print = function(ux, uy, uz) if abs(uz) < 0.08 and uy > 0 then return IDX.m end end },
            { id = 3, ramp = RAMP.sprout, at = A.mul(A.move(0, 12, 0), A.rotZ(-up), A.move(-3.6, 0, 0), A.scale(4.2, 0.9, 2.3)),
                print = function(ux, uy, uz) if abs(uz) < 0.08 and uy > 0 then return IDX.m end end },
            { id = 4, ramp = RAMP.sprout, at = ell(0, 12.6, 0, 1.1, 1.5, 1.1) },
        }
        return place(parts, A.scale(1.5, 1.5, 1.5), A.rotZ(-0.25 * w), A.rotY(0.7))
    end)
end

--- fruiting bodies ------------------------------------------------------------------

local FLESH = RAMP.flesh

-- The starter: a puffball that squashes as it lets go (`squash` 0..1).
function M.puffer(squash)
    local s = floor(squash * 2 + 0.5)
    return kept("puffer" .. s, function()
        local q = s / 2
        return {
            { id = 1, ramp = RAMP.crumb, at = ell(0, 1, 0, 3.2, 1.3, 3.2) },
            { id = 2, ramp = FLESH, at = ell(0, 4.8 - 1.2 * q, 0, 4.7 + 0.8 * q, 4.1 - 1.2 * q, 4.7 + 0.8 * q),
                print = function(ux, uy, uz, lev)
                    if uy > 0.93 then return IDX.n end -- the pore it puffs from
                    return spotted(0.975, IDX.t)(ux, uy, uz, lev)
                end },
        }
    end)
end

-- The sniper: a clump of enoki, tall thin stalks with pin-head caps.
local ENOKI = { { 0, 0, 12 }, { 2.2, 1, 10 }, { -2, 1.4, 9.5 }, { 1.2, -2.2, 10.5 }, { -1.5, -1.8, 8.5 } }
function M.needle()
    return kept("needle", function()
        local parts = { { id = 1, ramp = RAMP.crumb, at = ell(0, 0.6, 0, 3.6, 1.2, 3.6) } }
        for n, s in ipairs(ENOKI) do
            local lean = A.mul(A.rotZ(-s[1] * 0.05), A.rotX(s[2] * 0.05))
            parts[#parts + 1] = { id = n * 2, ramp = FLESH, at = A.mul(lean, ell(s[1], s[3] / 2, s[2], 0.75, s[3] / 2, 0.75)) }
            parts[#parts + 1] = { id = n * 2 + 1, ramp = FLESH, at = A.mul(lean, ell(s[1], s[3], s[2], 1.7, 0.9, 1.7)) }
        end
        return parts
    end)
end

-- The healer: a shaggy white shelf on a stub, hung all round with spines.
function M.mane()
    return kept("mane", function()
        local parts = {
            { id = 1, ramp = RAMP.crumb, at = ell(0, 2, 0, 1.8, 2.4, 1.8) },
            { id = 2, ramp = FLESH, at = ell(0, 7, 0, 6, 3.4, 5.6),
                print = function(ux, uy, uz, lev)
                    if lev >= 2 and sin(atan2(uz, ux) * 13 + uy * 3) > 0.3 then
                        return uy < 0 and IDX.w or IDX.t
                    end
                end },
        }
        for n = 0, 8 do
            local a = n * 0.698 + 0.2
            parts[#parts + 1] = { id = 3 + n % 2, ramp = FLESH,
                at = ell(cos(a) * 4.4, 3.8, sin(a) * 4, 0.8, 2.4, 0.8) }
        end
        return parts
    end)
end

-- The hub: a low teal dome whose rings run outward (`beat` 0..3).
function M.relay(beat)
    return kept("relay" .. beat, function()
        return {
            { id = 1, ramp = RAMP.teal, at = ell(0, 1.6, 0, 5.4, 3.2, 5.4),
                print = function(ux, uy, uz)
                    local r = sqrt(ux * ux + uz * uz)
                    if uy > 0 and abs((r + beat * 0.08) % 0.32 - 0.16) < 0.04 then return IDX.l end
                end },
            { id = 2, ramp = T.ramp("w", "w", "l", "c"), at = ell(0, 4.6, 0, 1.9, 1.9, 1.9) },
        }
    end)
end

-- Laid on the trail rather than grown on a pocket: a flat glistening mat.
function M.mat()
    return kept("mat", function()
        return {
            { id = 1, ramp = T.ramp("w", "l", "c", "d"), at = ell(0, 0, 0, 7.2, 1.5, 7.2),
                print = spotted(0.985, IDX.w) },
            { id = 2, ramp = T.ramp("w", "l", "c", "d"), at = ell(2.5, 0.2, -2, 3.6, 1.4, 3.2) },
            { id = 2, ramp = T.ramp("w", "l", "c", "d"), at = ell(-2.6, 0.1, 2.2, 3.2, 1.4, 3.6) },
        }
    end)
end

--- enemies ----------------------------------------------------------------------------

-- A worker ant, front +x. `leg` 0/1 is which tripod is forward.
local function antParts(leg)
    local parts = {
        { id = 1, ramp = RAMP.ant, at = ell(3.4, 2.3, 0, 1.3, 1.1, 1.1),
            print = function(ux, uy, uz) if ux > 0.3 and abs(uz) > 0.6 and uy > 0 then return IDX.o end end },
        { id = 2, ramp = RAMP.ant, at = ell(1.2, 2.2, 0, 1.5, 0.85, 0.9) },
        { id = 3, ramp = RAMP.ant, at = ell(-0.3, 2.0, 0, 0.5, 0.5, 0.5) },
        { id = 4, ramp = RAMP.ant, at = ell(-2.4, 2.6, 0, 2.1, 1.6, 1.6),
            print = function(ux) if abs((ux + 1) % 0.5 - 0.25) < 0.04 then return IDX.n end end },
    }
    for n, x in ipairs({ 2.0, 1.2, 0.4 }) do
        for _, side in ipairs({ -1, 1 }) do
            local swing = ((n + (side > 0 and 1 or 0) + leg) % 2 == 0) and 0.45 or -0.45
            parts[#parts + 1] = { id = 5, ramp = RAMP.ink,
                at = A.mul(A.move(x, 1.3, 0), A.rotY(side * swing), A.rotX(side * 0.5), ell(0, 0, side * 1.6, 0.3, 0.3, 1.6)) }
        end
    end
    for _, side in ipairs({ -1, 1 }) do
        parts[#parts + 1] = { id = 6, ramp = RAMP.ink, at = A.mul(A.move(4.2, 3.4, side * 0.7), A.rotX(-side * 0.4), A.rotZ(-0.7), A.scale(0.25, 1.4, 0.25)) }
    end
    return parts
end

function M.ant(h, leg)
    local hs = step(h, 32)
    return kept("ant" .. hs .. ":" .. leg, function() return place(antParts(leg), heading(hs / 32 * TAU), A.scale(1.4, 1.4, 1.4)) end)
end

-- A pillbug: plated and slow on its feet, or rolled into a ball (`roll` 0..3
-- is how far round the plates have turned) and fast.
function M.pillbug(h, rolled, roll)
    local hs = step(h, 16)
    return kept("bug" .. hs .. (rolled and ("r" .. roll) or "w"), function()
        local parts
        if rolled then
            local a = roll / 4 * math.pi
            parts = { { id = 1, ramp = RAMP.bug, at = ell(0, 3.1, 0, 3.1, 3.1, 3.1),
                print = function(ux, uy, uz)
                    local v = ux * cos(a) + uy * sin(a)
                    if abs((v + 1) % 0.42 - 0.21) < 0.05 then return IDX.k end
                end } }
        else
            parts = {
                { id = 1, ramp = RAMP.bug, at = ell(0, 2.2, 0, 4.6, 2.4, 3.1),
                    print = function(ux, uy) if uy > -0.2 and abs((ux + 1) % 0.29 - 0.145) < 0.035 then return IDX.k end end },
                { id = 2, ramp = RAMP.bug, at = ell(4.1, 1.4, 0, 1.3, 1.1, 1.9) },
            }
            for _, side in ipairs({ -1, 1 }) do
                parts[#parts + 1] = { id = 3, ramp = RAMP.ink, at = A.mul(A.move(5.2, 2, side * 1), A.rotY(side * 0.5), A.rotZ(-1.1), A.scale(0.25, 1.6, 0.25)) }
            end
        end
        return place(parts, heading(hs / 16 * TAU), A.scale(1.2, 1.2, 1.2))
    end)
end

-- A mite: a speck with a front. Too small to need more than eight headings.
function M.mite(h)
    local hs = step(h, 8)
    return kept("mite" .. hs, function()
        return place({
            { id = 1, ramp = RAMP.mite, at = ell(0, 1.5, 0, 2, 1.5, 1.7) },
            { id = 2, ramp = RAMP.mite, at = ell(1.9, 1.2, 0, 0.9, 0.7, 0.8) },
        }, heading(hs / 8 * TAU))
    end)
end

-- A drop of brine. It has no front; it wobbles (`wob` 0..1).
function M.brine(wob)
    return kept("brine" .. wob, function()
        local s = wob == 1 and 0.12 or 0
        return place({
            { id = 1, ramp = RAMP.salt, at = ell(0, 2.5 - s * 2, 0, 2.8 + s * 3, 2.5 - s * 3, 2.8 + s * 3),
                print = function(ux, uy, uz, lev) if uy < -0.2 and lev >= 3 and abs(ux + uz) < 0.3 then return IDX.c end end },
            { id = 1, ramp = RAMP.salt, at = ell(0, 4.8 - s * 4, 0, 1.0, 1.7, 1.0) },
        }, A.scale(1.4, 1.4, 1.4))
    end)
end

-- What is left: the body on its back, for the network to drink.
function M.corpse(kind, h)
    local hs = step(h, 8)
    return kept("dead" .. kind .. hs, function()
        local parts
        if kind == "ant" then
            parts = place(antParts(0), A.scale(1.4, 1.4, 1.4), A.move(0, 3.6, 0), A.rotX(math.pi))
        elseif kind == "pillbug" then
            parts = { { id = 1, ramp = RAMP.bug, at = ell(0, 1.6, 0, 4.4, 1.7, 3) },
                { id = 2, ramp = RAMP.ink, at = ell(0, 2.6, 0, 3.2, 0.6, 2) } }
        else
            parts = { { id = 1, ramp = RAMP.mite, at = ell(0, 0.5, 0, 1.2, 0.6, 1.1) } }
        end
        return place(parts, heading(hs / 8 * TAU))
    end)
end

-- The pocket's tower by name, for the toolbar and the board alike.
function M.tower(kind, t)
    t = t or 0
    if kind == "puffer" then return M.puffer(0) end
    if kind == "needle" then return M.needle() end
    if kind == "mane" then return M.mane() end
    if kind == "relay" then return M.relay(floor(t * 3) % 4) end
    if kind == "mat" then return M.mat() end
end

return M
