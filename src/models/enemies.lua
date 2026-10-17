-- The enemies, the bosses, and what is left of them (see src/models.lua).

local T = require "src.tracer"
local A = T.Affine

local sin, cos, atan2, abs = math.sin, math.cos, math.atan2, math.abs
local ell, RAMP, IDX = T.ell, T.RAMP, T.IDX
local TAU = 2 * math.pi
local K = require "src.models.kit"
local kept, place, heading, step, seg, limb, spotted, R = K.kept, K.place, K.heading, K.step, K.seg, K.limb, K.spotted, K.R

local M = {}

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

-- A fungus gnat: a dark speck on glassy wings, legs trailing. Its pivot is
-- its body, not the ground: it flies.
local function gnatParts(wing)
    local up = wing == 0 and 0.5 or -0.35
    local parts = {
        { id = 1, ramp = R.black, at = ell(0, 0, 0, 1.5, 1.0, 1.0) },
        { id = 2, ramp = R.black, at = ell(1.5, 0.3, 0, 0.75, 0.75, 0.75) },
        { id = 3, ramp = R.black, at = ell(-1.9, -0.3, 0, 1.9, 0.75, 0.75),
            print = function(ux) if abs((ux + 1) % 0.5 - 0.25) < 0.06 then return IDX.u end end },
    }
    for _, side in ipairs({ -1, 1 }) do
        parts[#parts + 1] = { id = 4, ramp = R.wing, at = A.mul(A.move(-0.4, 0.8, side * 0.6), A.rotX(side * up), A.move(-0.6, 0, side * 1.6), A.scale(2.2, 0.15, 1.4)) }
        parts[#parts + 1] = seg(0.3, -0.6, side * 0.4, -0.6, -2.8, side * 1.2, 0.2, R.ink, 5)
    end
    return parts
end

function M.gnat(h, wing)
    local hs = step(h, 8)
    return kept("gnat" .. hs .. wing, function() return place(gnatParts(wing), heading(hs / 8 * TAU), A.scale(1.3, 1.3, 1.3)) end)
end

-- A slug: a long wet foot with a mantle and two eyestalks. It crawls by
-- stretching (`crawl` 0/1).
local function slugParts(crawl)
    local s = crawl == 1 and 1.06 or 1
    local parts = {
        { id = 1, ramp = R.slug, at = ell(0, 1.6 / s, 0, 7 * s, 1.8 / s, 2.6),
            print = function(ux, uy, uz, lev)
                if lev >= 2 and abs((ux * 7 + abs(uz) * 3) % 1 - 0.5) < 0.08 then return IDX.n end
            end },
        { id = 2, ramp = R.slug, at = ell(2.2 * s, 2.7, 0, 3.2, 1.5, 2.4),
            print = function(ux, uy, uz) if abs(uz) < 0.1 and uy > 0.2 then return IDX.u end end },
        { id = 3, ramp = R.slug, at = ell(6.2 * s, 1.5, 0, 1.8, 1.4, 1.7) },
    }
    for _, side in ipairs({ -1, 1 }) do
        parts[#parts + 1] = seg(6.6 * s, 2.4, side * 0.6, 7.6 * s, 5, side * 1.1, 0.3, R.slug, 4)
        parts[#parts + 1] = { id = 5, ramp = R.black, at = ell(7.7 * s, 5.2, side * 1.15, 0.5, 0.5, 0.5) }
    end
    return parts
end

function M.slug(h, crawl)
    local hs = step(h, 16)
    return kept("slug" .. hs .. crawl, function() return place(slugParts(crawl), heading(hs / 16 * TAU), A.scale(1.3, 1.3, 1.3)) end)
end

-- A wolf spider: a striped body slung between eight jointed legs.
local function spiderParts(leg)
    local parts = {
        { id = 1, ramp = R.spider, at = ell(1.8, 3.0, 0, 2.2, 1.5, 1.9),
            print = function(ux, uy, uz)
                if ux > 0.75 and uy > 0 and abs(uz) < 0.45 then return IDX.o end
                if abs(uz) < 0.18 and uy > 0.3 then return IDX.t end
            end },
        { id = 2, ramp = R.spider, at = ell(-2.4, 3.4, 0, 3.0, 2.2, 2.4),
            print = function(ux, uy, uz)
                if uy > 0.2 and abs(uz) < 0.2 then return IDX.t end
                if uy > 0 and abs((ux * 3 + abs(uz) * 2) % 1 - 0.5) < 0.1 then return IDX.u end
            end },
    }
    for n, x in ipairs({ 2.8, 2.0, 1.2, 0.4 }) do
        for _, side in ipairs({ -1, 1 }) do
            local fwd = ((n + (side > 0 and 1 or 0) + leg) % 2 == 0) and 1.6 or -1.6
            local reach = 7.5 - math.abs(n - 2.5) * 0.6
            local fx = x + (n - 2.5) * 2.4 + fwd
            limb(parts, x, 3, side * 1.2, fx, side * reach, 2.6, 0.38, R.spider, 3)
        end
    end
    parts[#parts + 1] = seg(3.8, 2.6, -0.6, 4.6, 1.8, -0.7, 0.4, R.spider, 4)
    parts[#parts + 1] = seg(3.8, 2.6, 0.6, 4.6, 1.8, 0.7, 0.4, R.spider, 4)
    return parts
end

function M.spider(h, leg)
    local hs = step(h, 16)
    return kept("spider" .. hs .. leg, function() return place(spiderParts(leg), heading(hs / 16 * TAU), A.scale(1.15, 1.15, 1.15)) end)
end

-- A beetle knight: black plate with a tan rim, a shield of a pronotum and a horn.
local function knightParts(leg)
    local parts = {
        { id = 1, ramp = R.black, at = ell(-1.2, 3.2, 0, 4.2, 2.6, 3.2),
            print = function(ux, uy, uz)
                if abs(uz) < 0.05 and uy > 0 then return IDX.o end
                if uy > 0.2 and abs(abs(uz) - 0.5) < 0.05 then return IDX.u end
            end },
        { id = 2, ramp = R.black, at = ell(3.0, 3.3, 0, 2.0, 2.2, 3.0),
            print = function(ux, uy, uz)
                if ux > 0.55 then return IDX.t end -- the gilded edge
            end },
        { id = 3, ramp = R.black, at = ell(4.9, 2.3, 0, 1.3, 1.1, 1.5) },
    }
    parts[#parts + 1] = seg(5.2, 2.8, 0, 7.4, 5.6, 0, 0.55, R.jaw, 4)
    parts[#parts + 1] = seg(7.4, 5.6, 0, 7.0, 6.8, 0, 0.4, R.jaw, 4)
    for n, x in ipairs({ 3.2, 1.0, -1.4 }) do
        for _, side in ipairs({ -1, 1 }) do
            local fwd = ((n + (side > 0 and 1 or 0) + leg) % 2 == 0) and 1.3 or -1.3
            limb(parts, x, 2.6, side * 2.2, x + (n - 2) * 1.6 + fwd, side * 5.4, 1.6, 0.42, R.ink, 5)
        end
    end
    return parts
end

function M.knight(h, leg)
    local hs = step(h, 16)
    return kept("knight" .. hs .. leg, function() return place(knightParts(leg), heading(hs / 16 * TAU), A.scale(1.2, 1.2, 1.2)) end)
end

-- A springtail: a long soft grey body in segments, feelers longer than its
-- head, and under its tail the fork it springs off. Hopping (`hop`), it arches
-- and the fork snaps out behind it.
local function springtailParts(leg, hop)
    local arch = hop and 0.35 or 0
    local parts = {
        { id = 1, ramp = R.springtail, at = A.mul(A.move(-1.4, 2.2 + arch * 2, 0), A.rotZ(arch), A.scale(3.4, 1.5, 1.6)),
            print = function(ux) if abs((ux + 1) % 0.5 - 0.25) < 0.05 then return IDX.k end end },
        { id = 2, ramp = R.springtail, at = ell(2.2, 2.2, 0, 1.6, 1.3, 1.4),
            print = function(ux, uy, uz) if ux > 0.3 and uy > 0 and abs(uz) > 0.6 then return IDX.o end end },
    }
    -- The fork: tucked under the belly, or kicked out behind.
    for _, side in ipairs({ -1, 1 }) do
        if hop then
            parts[#parts + 1] = seg(-4.2, 2, side * 0.3, -7, 0.4, side * 1, 0.3, R.springtail, 3)
        else
            parts[#parts + 1] = seg(-4.4, 1.4, side * 0.3, -1.6, 0.6, side * 0.6, 0.28, R.springtail, 3)
        end
        parts[#parts + 1] = seg(3.4, 2.8, side * 0.5, 5.6, 4.6, side * 1.5, 0.22, R.ink, 4)
        parts[#parts + 1] = seg(5.6, 4.6, side * 1.5, 7.2, 4.2, side * 2.4, 0.2, R.ink, 4)
    end
    for n, x in ipairs({ 1.4, 0.4, -0.6 }) do
        for _, side in ipairs({ -1, 1 }) do
            local fwd = ((n + (side > 0 and 1 or 0) + leg) % 2 == 0) and 0.6 or -0.6
            if hop then fwd = -0.8 end
            limb(parts, x, 1.6, side * 0.9, x + fwd, side * 2.6, 0.6, 0.25, R.ink, 5)
        end
    end
    return parts
end

function M.springtail(h, leg, hop)
    local hs = step(h, 16)
    return kept("spring" .. hs .. leg .. (hop and "h" or ""), function()
        return place(springtailParts(leg, hop), heading(hs / 16 * TAU), A.scale(1.3, 1.3, 1.3))
    end)
end

--- the bosses: the big bugs ---------------------------------------------------------------

-- The Queen Ant: an ant made heavy, with a swollen banded gaster, a broad
-- thorax and her wings still on.
local function queenParts(leg)
    local ant = RAMP.ant
    local parts = {
        { id = 1, ramp = ant, at = ell(4.0, 2.9, 0, 1.6, 1.4, 1.5),
            print = function(ux, uy, uz)
                if ux > 0.2 and abs(uz) > 0.55 and uy > -0.1 then return IDX.o end
                if ux > 0.85 then return IDX.u end
            end },
        { id = 2, ramp = ant, at = ell(1.4, 2.9, 0, 2.1, 1.3, 1.35),
            print = function(ux, uy, uz) if uy > 0.4 and abs(uz) < 0.12 then return IDX.n end end },
        { id = 3, ramp = ant, at = ell(-0.9, 2.5, 0, 0.6, 0.7, 0.6) },
        { id = 4, ramp = ant, at = ell(-3.8, 3.2, 0, 3.4, 2.5, 2.4),
            print = function(ux, uy, uz, lev)
                if abs((ux + 1) % 0.4 - 0.2) < 0.05 then return IDX.u end
                if lev >= 2 and abs((ux + 1) % 0.4 - 0.2) < 0.09 then return IDX.n end
            end },
    }
    -- Mandibles.
    for _, side in ipairs({ -1, 1 }) do
        parts[#parts + 1] = seg(5.2, 2.4, side * 0.6, 6.2, 2.2, side * 0.1, 0.3, R.jaw, 5)
    end
    -- Wings, folded back over the gaster.
    for _, side in ipairs({ -1, 1 }) do
        for w = 0, 1 do
            parts[#parts + 1] = { id = 6 + w, ramp = R.wing,
                at = A.mul(A.move(0.8 - w * 0.6, 4.2 + w * 0.2, side * (0.6 + w * 0.3)), A.rotY(side * (0.15 + w * 0.12)), A.rotX(side * 0.15),
                    A.move(-3.4, 0, 0), A.scale(3.8 - w * 0.8, 0.15, 1.2 - w * 0.2)),
                print = function(ux, uy, uz) if abs((ux * 3 + uz) % 1 - 0.5) < 0.06 or abs(uz) > 0.85 then return IDX.k end end }
        end
    end
    for n, x in ipairs({ 2.2, 1.4, 0.6 }) do
        for _, side in ipairs({ -1, 1 }) do
            local fwd = ((n + (side > 0 and 1 or 0) + leg) % 2 == 0) and 1.1 or -1.1
            limb(parts, x, 2.3, side * 1.0, x + (n - 2) * 2.2 + fwd, side * 4.6, 1.4, 0.32, R.ink, 8)
        end
    end
    for _, side in ipairs({ -1, 1 }) do
        parts[#parts + 1] = seg(4.8, 3.9, side * 0.6, 5.0, 5.6, side * 1.2, 0.22, R.ink, 9)
        parts[#parts + 1] = seg(5.0, 5.6, side * 1.2, 6.9, 5.0, side * 1.8, 0.2, R.ink, 9)
    end
    return parts
end

function M.queen(h, leg)
    local hs = step(h, 16)
    return kept("queen" .. hs .. leg, function() return place(queenParts(leg), heading(hs / 16 * TAU), A.scale(3.3, 3.3, 3.3)) end)
end

-- The Stag Beetle: glossy wing cases, a broad head, and jaws as long as the
-- rest of it, forked and toothed. Charging, it drops its head and opens them.
local function stagParts(leg, charge)
    local open = charge and 1.5 or 0
    local lift = charge and 1.4 or 0
    local parts = {
        { id = 1, ramp = R.shell, at = ell(-3, 4, 0, 5.5, 3.0, 4.0),
            print = function(ux, uy, uz)
                if abs(uz) < 0.04 and uy > 0 then return IDX.o end
                if uy > 0.3 and abs(abs(uz) - 0.55) < 0.03 then return IDX.u end
            end },
        { id = 2, ramp = R.shell, at = ell(2.6, 4.2, 0, 2.6, 2.4, 3.8),
            print = function(ux, uy, uz) if abs(uz) > 0.8 and uy > 0 then return IDX.u end end },
        { id = 3, ramp = R.shell, at = ell(5.4, 3.6 - lift * 0.5, 0, 2.1, 1.9, 3.4),
            print = function(ux, uy, uz) if ux > 0.3 and uy > 0.2 and abs(abs(uz) - 0.6) < 0.12 then return IDX.o end end },
    }
    -- The jaws: a curved beam each side, a tine inward, teeth along the inside.
    for _, side in ipairs({ -1, 1 }) do
        local b0 = { 6.6, 3.8 - lift * 0.3, side * 1.8 }
        local b1 = { 11.5, 4.8 + lift, side * (3.8 + open) }
        local b2 = { 16, 5.2 + lift * 1.4, side * (1.2 + open) }
        parts[#parts + 1] = seg(b0[1], b0[2], b0[3], b1[1], b1[2], b1[3], 1.3, R.mandible, 4, 1.0)
        parts[#parts + 1] = seg(b1[1], b1[2], b1[3], b2[1], b2[2], b2[3], 1.0, R.mandible, 4, 0.8)
        parts[#parts + 1] = seg(b1[1] + 0.5, b1[2], b1[3], b1[1] + 1.6, b1[2] + 2.4, b1[3] - side * 1.6, 0.6, R.mandible, 4)
        for t = 1, 3 do
            local f = t / 4
            local x, z = b0[1] + (b1[1] - b0[1]) * f, b0[3] + (b1[3] - b0[3]) * f
            parts[#parts + 1] = seg(x, b0[2] + 0.4, z, x + 0.5, b0[2] + 0.3, z - side * 1.3, 0.35, R.mandible, 4)
        end
    end
    for n, x in ipairs({ 3.6, 0.6, -2.6 }) do
        for _, side in ipairs({ -1, 1 }) do
            local fwd = ((n + (side > 0 and 1 or 0) + leg) % 2 == 0) and 1.4 or -1.4
            limb(parts, x, 3, side * 2.6, x + (n - 2) * 2.4 + fwd, side * 7, 2.2, 0.5, R.shell, 5)
        end
    end
    for _, side in ipairs({ -1, 1 }) do
        parts[#parts + 1] = seg(6.6, 4.6, side * 2, 7.6, 6.8, side * 2.6, 0.22, R.ink, 6)
        parts[#parts + 1] = seg(7.6, 6.8, side * 2.6, 8.8, 6.2, side * 3.4, 0.25, R.ink, 6)
    end
    return parts
end

function M.stag(h, leg, charge)
    local hs = step(h, 16)
    return kept("stag" .. hs .. leg .. (charge and "c" or ""), function()
        return place(stagParts(leg, charge), heading(hs / 16 * TAU), A.scale(1.7, 1.7, 1.7))
    end)
end

-- The Dung Beetle, head down, its back legs up on the ball behind it -- so it
-- walks backwards, and the game turns it round (heading + pi).
local function dungParts(leg)
    local parts = {
        { id = 1, ramp = R.black, at = A.mul(A.move(-1, 3.6, 0), A.rotZ(0.35), A.scale(4.2, 2.6, 3.8)),
            print = function(ux, uy, uz)
                if abs(uz) < 0.04 and uy > 0 then return IDX.o end
                if uy > 0 and abs((abs(uz) * 4) % 1 - 0.5) < 0.05 then return IDX.u end
            end },
        { id = 2, ramp = R.black, at = ell(2.6, 2.6, 0, 2.2, 2.0, 3.4) },
        -- The spade of a head, its rim toothed.
        { id = 3, ramp = R.black, at = A.mul(A.move(4.6, 1.5, 0), A.rotZ(-0.25), A.scale(2.4, 0.9, 3.4)),
            print = function(ux, uy, uz)
                if uy > 0 and abs((atan2(uz, ux) * 8 / math.pi) % 1 - 0.5) < 0.1 and ux > 0.4 then return IDX.u end
                if ux > 0.9 then return IDX.k end
            end },
    }
    -- Front legs dig in ahead, middle ones brace, the hind ones reach up the ball.
    for _, side in ipairs({ -1, 1 }) do
        local fwd = (leg + (side > 0 and 1 or 0)) % 2 == 0 and 1 or -1
        limb(parts, 3, 2, side * 2.4, 6 + fwd, side * 5.2, 1.2, 0.5, R.black, 4)
        limb(parts, 0.6, 2.4, side * 3, 0.6 - fwd, side * 6.4, 1.8, 0.45, R.black, 4)
        local hx, hy, hz = -3.6, 5.2, side * 2.6
        local kx, ky, kz = -6, 8.4 + fwd * 0.6, side * 4.4
        local fx, fy, fz = -8.4, 9.4 - fwd * 0.6, side * 2.2
        parts[#parts + 1] = seg(hx, hy, hz, kx, ky, kz, 0.6, R.black, 4)
        parts[#parts + 1] = seg(kx, ky, kz, fx, fy, fz, 0.45, R.black, 4)
        for t = 1, 3 do
            local f = t / 4
            local x, y, z = kx + (fx - kx) * f, ky + (fy - ky) * f, kz + (fz - kz) * f
            parts[#parts + 1] = seg(x, y, z, x, y + 0.9, z + side * 0.3, 0.18, R.ink, 6)
        end
    end
    return parts
end

function M.dung(h, leg)
    local hs = step(h, 16)
    return kept("dung" .. hs .. leg, function() return place(dungParts(leg), heading(hs / 16 * TAU), A.scale(1.7, 1.7, 1.7)) end)
end

-- Its ball: dung and grit and bits of straw, turning over as it rolls
-- (`roll` 0..3) about the axis across heading h.
function M.ball(h, roll, cracked)
    local hs = step(h, 8)
    return kept("ball" .. hs .. roll .. (cracked and "x" or ""), function()
        local a = roll / 4 * math.pi
        local ca, sa = cos(a), sin(a)
        return place({ { id = 1, ramp = R.dung, at = ell(0, 9, 0, 9, 9, 9),
            print = function(ux, uy, uz, lev)
                -- Turn the point back by the roll, so the print rolls with the ball.
                local px, py = ux * ca - uy * sa, ux * sa + uy * ca
                local g = sin(px * 23.1 + uz * 17.3) * sin(py * 19.7 - uz * 13.1)
                if cracked and abs(sin(px * 6 + uz * 4)) < 0.08 then return IDX.o end
                if abs((px * 2 + uz + py * 0.5) % 0.7 - 0.35) < 0.025 and abs(py) < 0.6 then return IDX.t end -- straw
                if g > 0.72 then return IDX.u end
                if g < -0.8 and lev <= 3 then return IDX.t end
            end } }, heading(hs / 8 * TAU))
    end)
end

-- A night moth: a furred body on two pairs of broad dusty wings with eye
-- spots, feathered feelers. Its pivot is its body: it flies. `wing` 0/1.
local function mothParts(wing)
    local up = wing == 0 and 0.55 or -0.3
    local parts = {
        { id = 1, ramp = R.crumb, at = ell(-0.6, 0, 0, 2.4, 1.1, 1.1),
            print = function(ux) if abs((ux + 1) % 0.4 - 0.2) < 0.05 then return IDX.n end end },
        { id = 2, ramp = R.crumb, at = ell(1.7, 0.2, 0, 1.0, 0.95, 0.95) },
    }
    for _, side in ipairs({ -1, 1 }) do
        for w = 0, 1 do
            local wl, ww = w == 0 and 3.2 or 2.4, w == 0 and 3.2 or 2.4
            parts[#parts + 1] = { id = 3 + w, ramp = R.wingtan,
                at = A.mul(A.move(0.6 - w * 1.6, 0.6, side * 0.6), A.rotX(side * up), A.rotY(side * (w == 0 and -0.35 or 0.4)),
                    A.move(0, 0, side * ww), A.scale(wl, 0.15, ww)),
                print = function(ux, uy, uz)
                    local r = (ux - 0.1) ^ 2 + (uz - side * 0.2) ^ 2
                    if r < 0.05 then return IDX.o end            -- the eye spot
                    if r < 0.11 then return IDX.w end
                    if abs(ux * 0.7 + abs(uz) * 0.3 - 0.45) < 0.06 then return IDX.u end
                end }
        end
        parts[#parts + 1] = seg(2.4, 0.6, side * 0.3, 3.6, 2.4, side * 1.4, 0.25, R.crumb, 5)
    end
    return parts
end

function M.moth(h, wing)
    local hs = step(h, 8)
    return kept("moth" .. hs .. wing, function() return place(mothParts(wing), heading(hs / 8 * TAU), A.scale(1.8, 1.8, 1.8)) end)
end

-- The Giant Water Bug: a flat brown shield of a body, a short stabbing beak,
-- forelegs like folded pincers and oar-flat hind legs. Grabbing, it reaches
-- the forelegs out.
local function waterbugParts(leg, grab)
    local parts = {
        { id = 1, ramp = R.shell, at = ell(-1.4, 2.3, 0, 6.2, 1.6, 3.6),
            print = function(ux, uy, uz)
                if uy > 0 and abs(uz) < 0.04 and ux < 0.4 then return IDX.o end -- where the wings meet
                if uy > 0.2 and ux < -0.2 and abs(abs(uz) - (0.2 - ux * 0.5)) < 0.04 then return IDX.u end
            end },
        { id = 2, ramp = R.shell, at = ell(3.6, 2.4, 0, 2.2, 1.4, 3.0),
            print = function(ux, uy, uz) if ux > 0.5 and uy > -0.3 and abs(uz) > 0.55 then return IDX.o end end }, -- eyes
        { id = 3, ramp = R.shell, at = ell(5.6, 2.1, 0, 1.4, 0.9, 1.3) },
    }
    parts[#parts + 1] = seg(6.6, 2, 0, 8.2, 1, 0, 0.35, R.jaw, 4) -- the beak
    for _, side in ipairs({ -1, 1 }) do
        -- Forelegs: a thick femur, a tibia folded back along it, a claw.
        local reach = grab and 4 or 0
        local kx, ky, kz = 7 + reach, 3.6 + (grab and 0.6 or 0), side * 3
        parts[#parts + 1] = seg(4.4, 2, side * 1.6, kx, ky, kz, 0.85, R.shell, 5)
        local tx, tz = grab and (kx + 2.6) or (kx - 3.2), side * (grab and 1.8 or 3.6)
        parts[#parts + 1] = seg(kx, ky, kz, tx, 1.4, tz, 0.55, R.shell, 5)
        parts[#parts + 1] = seg(tx, 1.4, tz, tx + 0.8, 0.8, tz - side * 0.8, 0.3, R.jaw, 5)
        -- Middle legs walk; the hind legs are oars.
        local fwd = (leg + (side > 0 and 1 or 0)) % 2 == 0 and 1.2 or -1.2
        limb(parts, 0.6, 2, side * 2.6, 0.6 + fwd, side * 7, 1.6, 0.45, R.shell, 6)
        parts[#parts + 1] = seg(-2.6, 2, side * 2.8, -6 - fwd, 1.8, side * 7.4, 0.5, R.shell, 7, 0.25)
        parts[#parts + 1] = seg(-6 - fwd, 1.8, side * 7.4, -10 - fwd, 1.2, side * 6, 0.9, R.shell, 7, 0.22)
    end
    return parts
end

function M.waterbug(h, leg, grab)
    local hs = step(h, 16)
    return kept("wbug" .. hs .. leg .. (grab and "g" or ""), function()
        return place(waterbugParts(leg, grab), heading(hs / 16 * TAU), A.scale(1.9, 1.9, 1.9))
    end)
end

-- The Giant Centipede, made of parts that are each an enemy: a head with
-- antennae and poison claws, and segments, each a banded plate on a pair of
-- long legs. `leg` 0/1 swings them.
local function centiHeadParts(leg)
    local parts = {
        { id = 1, ramp = R.centi, at = ell(0, 2, 0, 3.4, 1.5, 3.2),
            print = function(ux, uy, uz)
                if ux > 0.4 and uy > -0.2 and abs(uz) > 0.55 and abs(uz) < 0.8 then return IDX.o end
                if uy > 0.5 and abs(uz) < 0.1 then return IDX.n end
            end },
    }
    for _, side in ipairs({ -1, 1 }) do
        -- Poison claws, curled in under the head.
        parts[#parts + 1] = seg(2.4, 1.4, side * 1.8, 4.4, 1, side * 2, 0.6, R.black, 2)
        parts[#parts + 1] = seg(4.4, 1, side * 2, 5.2, 0.9, side * 0.4, 0.4, R.black, 2)
        -- Antennae, long and waving.
        local wave = (leg == 0 and 0.6 or -0.6) * side
        parts[#parts + 1] = seg(2.6, 2.6, side * 1, 6, 4.2, side * (3 + wave), 0.3, R.centi, 3)
        parts[#parts + 1] = seg(6, 4.2, side * (3 + wave), 9.6, 3.6, side * (4.8 + wave), 0.22, R.centi, 3)
        limb(parts, -1.2, 1.6, side * 2.4, -0.6 + (leg == 0 and 1 or -1) * side, side * 6.4, 1.6, 0.4, R.jaw, 4)
    end
    return parts
end

local function centiSegParts(leg)
    local parts = {
        { id = 1, ramp = R.centi, at = ell(0, 2, 0, 3.6, 1.5, 3.3),
            print = function(ux, uy, uz)
                if ux < -0.6 then return IDX.u end                     -- the dark band at the back
                if uy > 0.5 and abs(uz) < 0.08 then return IDX.n end
                if uy > 0 and abs(abs(uz) - 0.6) < 0.05 then return IDX.n end
            end },
    }
    for _, side in ipairs({ -1, 1 }) do
        local fwd = (leg + (side > 0 and 1 or 0)) % 2 == 0 and 1.5 or -1.5
        limb(parts, 0, 1.6, side * 2.6, fwd, side * 7, 2.2, 0.38, R.jaw, 2)
    end
    return parts
end

-- `s`: how big; the small centipede is the Giant's head and segments, less
-- than half the size.
function M.centipede(h, leg, s)
    local hs = step(h, 16)
    s = s or 1.7
    return kept("chead" .. hs .. leg .. ":" .. s, function() return place(centiHeadParts(leg), heading(hs / 16 * TAU), A.scale(s, s, s)) end)
end

function M.centseg(h, leg, s)
    local hs = step(h, 16)
    s = s or 1.6
    return kept("cseg" .. hs .. leg .. ":" .. s, function() return place(centiSegParts(leg), heading(hs / 16 * TAU), A.scale(s, s, s)) end)
end

-- The Bombardier Beetle: a rust head and thorax, black wing cases banded in
-- tan, long tan legs. Spraying, it lifts the wing cases and curls the tip of
-- its abdomen out from under them, behind it.
local function bombardierParts(leg, spray)
    local lift = spray and 0.3 or 0
    local parts = {
        { id = 1, ramp = R.black, at = A.mul(A.move(-2, 3.4, 0), A.rotZ(-lift), A.scale(4.6, 2.4, 3.4)),
            print = function(ux, uy, uz)
                if uy > 0 and abs(uz) < 0.04 then return IDX.o end
                if uy > 0.1 and abs(ux + 0.15) < 0.12 then return IDX.t end  -- the band across the wing cases
                if uy > 0.3 and abs((abs(uz) * 5) % 1 - 0.5) < 0.06 then return IDX.u end
            end },
        { id = 2, ramp = R.bombard, at = ell(2.8, 3.2, 0, 1.8, 1.7, 2.2) },
        { id = 3, ramp = R.bombard, at = ell(4.9, 2.7, 0, 1.4, 1.2, 1.6),
            print = function(ux, uy, uz) if ux > 0.4 and abs(uz) > 0.6 and uy > -0.2 then return IDX.o end end },
    }
    if spray then
        parts[#parts + 1] = seg(-5.6, 2.6, 0, -7.6, 4.4, 0, 0.9, R.bombard, 4)
    end
    for _, side in ipairs({ -1, 1 }) do
        parts[#parts + 1] = seg(5.8, 3, side * 0.6, 7.8, 4.6, side * 1.6, 0.22, R.jaw, 5)
        parts[#parts + 1] = seg(7.8, 4.6, side * 1.6, 9.8, 4, side * 2.6, 0.2, R.jaw, 5)
    end
    for n, x in ipairs({ 2.8, 0.6, -1.8 }) do
        for _, side in ipairs({ -1, 1 }) do
            local fwd = ((n + (side > 0 and 1 or 0) + leg) % 2 == 0) and 1.2 or -1.2
            limb(parts, x, 2.6, side * 1.8, x + (n - 2) * 2.2 + fwd, side * 5.6, 1.8, 0.4, R.jaw, 6)
        end
    end
    return parts
end

function M.bombardier(h, leg, spray)
    local hs = step(h, 16)
    return kept("bomb" .. hs .. leg .. (spray and "s" or ""), function()
        return place(bombardierParts(leg, spray), heading(hs / 16 * TAU), A.scale(2.3, 2.3, 2.3))
    end)
end

-- The Click Beetle: long and narrow, wing cases grooved end to end, a domed
-- pronotum whose back corners run out in spines, saw-toothed feelers. It
-- walks (`pose` nil), lies on its back kicking (`"belly"`), or turns over in
-- the air as it leaps (`"leap"`, `spin` 0..3 a quarter turn each).
local function clickParts(leg)
    local parts = {
        { id = 1, ramp = R.click, at = ell(-2.6, 3.2, 0, 5.2, 2.2, 2.8),
            print = function(ux, uy, uz)
                if uy > 0 and abs(uz) < 0.04 then return IDX.o end
                if uy > 0.1 and abs((abs(uz) * 6) % 1 - 0.5) < 0.08 then return IDX.u end -- the grooves
            end },
        { id = 2, ramp = R.click, at = ell(3.0, 3.4, 0, 2.4, 2.1, 2.7),
            print = function(ux, uy, uz) if uy > 0.6 and abs(uz) < 0.15 then return IDX.t end end },
        { id = 3, ramp = R.click, at = ell(5.6, 2.8, 0, 1.3, 1.3, 1.7),
            print = function(ux, uy, uz) if ux > 0.3 and abs(uz) > 0.6 and uy > -0.2 then return IDX.o end end },
    }
    for _, side in ipairs({ -1, 1 }) do
        -- The spines at the pronotum's back corners: the click is there.
        parts[#parts + 1] = seg(2.0, 3.2, side * 2.2, 0.6, 3.0, side * 3.2, 0.45, R.click, 4)
        -- Feelers, toothed.
        parts[#parts + 1] = seg(6.4, 3.2, side * 0.8, 8.4, 4.0, side * 2.4, 0.3, R.jaw, 5)
        parts[#parts + 1] = seg(8.4, 4.0, side * 2.4, 10, 3.4, side * 3.4, 0.28, R.jaw, 5)
    end
    for n, x in ipairs({ 3.2, 0.8, -1.6 }) do
        for _, side in ipairs({ -1, 1 }) do
            local fwd = ((n + (side > 0 and 1 or 0) + leg) % 2 == 0) and 1.1 or -1.1
            limb(parts, x, 2.4, side * 1.6, x + (n - 2) * 1.8 + fwd, side * 4.8, 1.4, 0.38, R.ink, 6)
        end
    end
    return parts
end

function M.click(h, leg, pose, spin)
    local hs = step(h, 16)
    local key = "click" .. hs .. leg .. (pose or "") .. (spin or "")
    return kept(key, function()
        local parts = clickParts(leg)
        local s = A.scale(2.2, 2.2, 2.2)
        if pose == "belly" then
            -- On its back, legs in the air.
            parts = place(parts, A.move(0, 6.6, 0), A.rotX(math.pi))
        elseif pose == "leap" then
            -- Turning over about its length as it flies.
            parts = place(parts, A.move(0, 3.2, 0), A.rotX(math.pi * (spin or 0) / 2), A.move(0, -3.2, 0))
        end
        return place(parts, heading(hs / 16 * TAU), s)
    end)
end

-- The Mole Cricket: a velvet-brown helmet of a pronotum, a soft banded
-- abdomen ending in two long cerci, cricket hind legs, and in front a pair of
-- broad toothed shovels for forelegs. Digging (`dig`), it hunches down and
-- the shovels scoop in turn, `leg` 0/1.
local function moleParts(leg, dig)
    local duck = dig and 0.6 or 0
    local parts = {
        { id = 1, ramp = R.mole, at = ell(-3.2, 2.8, 0, 4.6, 2.3, 2.8),
            print = function(ux, uy, uz)
                if uy > 0 and abs((ux + 1) % 0.33 - 0.165) < 0.03 then return IDX.u end -- the bands
                if uy > 0.4 and abs(uz) < 0.05 then return IDX.u end
            end },
        { id = 2, ramp = R.mole, at = A.mul(A.move(1.8, 3.6 - duck, 0), A.rotZ(-duck * 0.4), A.scale(3.0, 2.7, 2.9)),
            print = function(ux, uy, uz)
                if uy > 0.3 and abs(uz) < 0.05 then return IDX.o end -- the seam down the helmet
                if uy > 0.5 and ux < -0.3 then return IDX.t end       -- velvet catching the light
            end },
        { id = 3, ramp = R.mole, at = ell(4.8, 2.7 - duck, 0, 1.6, 1.5, 1.7),
            print = function(ux, uy, uz) if ux > 0.3 and abs(uz) > 0.6 and uy > -0.1 then return IDX.o end end },
    }
    for _, side in ipairs({ -1, 1 }) do
        -- Short feelers, and the two cerci trailing behind.
        parts[#parts + 1] = seg(6, 3.2 - duck, side * 0.7, 7.8, 3.8 - duck, side * 1.6, 0.22, R.jaw, 4)
        parts[#parts + 1] = seg(-7.6, 2.8, side * 0.8, -9.8, 3.4, side * 1.8, 0.25, R.jaw, 4)
        -- The shovels: a thick arm out to the side, and a broad toothed blade.
        local scoop = dig and ((leg + (side > 0 and 1 or 0)) % 2 == 0 and 1.6 or -0.8) or 0
        local sx, sy, sz = 6.6 + scoop, (dig and 0.9 or 1.6), side * (dig and 2.6 or 3.4)
        parts[#parts + 1] = seg(3.6, 2.4 - duck, side * 1.8, sx - 0.8, sy + 0.6, sz, 1.0, R.mole, 5)
        parts[#parts + 1] = { id = 6, ramp = R.jaw,
            at = A.mul(A.move(sx, sy, sz), A.rotY(side * 0.5), A.scale(1.6, 0.7, 2.0)),
            print = function(ux, uy, uz) if ux > 0.5 and abs((uz * 4) % 1 - 0.5) < 0.18 then return IDX.o end end }
        -- Short middle legs; the hind legs a cricket's, thick thighs folded
        -- along its sides.
        local fwd = (leg + (side > 0 and 1 or 0)) % 2 == 0 and 0.9 or -0.9
        if dig then fwd = 0 end
        limb(parts, 0.4, 2.2, side * 2.2, 0.6 + fwd, side * 4.6, 1.0, 0.36, R.jaw, 7)
        parts[#parts + 1] = seg(-1.6, 2.6, side * 2.4, -5.2, 4.0, side * 3.4, 0.95, R.mole, 8)
        parts[#parts + 1] = seg(-5.2, 4.0, side * 3.4, -7.2 - fwd * 0.5, 0.4, side * 3.8, 0.38, R.jaw, 8)
    end
    return parts
end

-- `s`: how big; the cricket nymph is the boss at under two thirds the size.
function M.mole(h, leg, dig, s)
    local hs = step(h, 16)
    s = s or 2.2
    return kept("mole" .. hs .. leg .. (dig and "d" or "") .. ":" .. s, function()
        return place(moleParts(leg, dig), heading(hs / 16 * TAU), A.scale(s, s, s))
    end)
end

--- what is left -----------------------------------------------------------------------

local function fruit(parts, x, y)
    for k = 0, 2 do
        local a = k * 2.1
        local fx, fz = x + cos(a) * 1.4, sin(a) * 1.4
        parts[#parts + 1] = seg(fx, y, fz, fx + cos(a) * 1.2, y + 4 + k, fz + sin(a) * 1.2, 0.45, R.cord, 30)
    end
    return parts
end

-- The body on its back, for the network to drink. `fruit`: a cordyceps host,
-- with the orange clubs coming up out of it.
function M.corpse(kind, h, fruited)
    local hs = step(h, 8)
    return kept("dead" .. kind .. hs .. (fruited and "f" or ""), function()
        local parts
        local top = 3
        local flip = function(p, lift, s) return place(p, A.scale(s, s, s), A.move(0, lift, 0), A.rotX(math.pi)) end
        if kind == "ant" then
            parts = flip(antParts(0), 3.6, 1.4)
        elseif kind == "pillbug" then
            parts = { { id = 1, ramp = RAMP.bug, at = ell(0, 1.6, 0, 4.4, 1.7, 3) },
                { id = 2, ramp = RAMP.ink, at = ell(0, 2.6, 0, 3.2, 0.6, 2) } }
        elseif kind == "gnat" then
            parts = place(gnatParts(1), A.scale(1.3, 1.3, 1.3), A.move(0, 1, 0), A.rotZ(0.3))
            top = 1
        elseif kind == "slug" then
            parts = place(slugParts(1), A.scale(1.3, 0.5, 1.3))
            top = 1.5
        elseif kind == "spider" then
            parts = flip(spiderParts(0), 6, 1.1)
            top = 5
        elseif kind == "knight" then
            parts = flip(knightParts(0), 6.4, 1.2)
            top = 5
        elseif kind == "queen" then
            parts = flip(queenParts(0), 6, 3.3)
            top = 10
        elseif kind == "stag" then
            parts = flip(stagParts(0), 8, 1.7)
            top = 12
        elseif kind == "dung" then
            parts = flip(dungParts(0), 7, 1.7)
            top = 10
        elseif kind == "moth" then
            parts = place(mothParts(1), A.scale(1.4, 1.4, 1.4), A.move(0, 1, 0), A.rotZ(0.15))
            top = 1
        elseif kind == "waterbug" then
            parts = flip(waterbugParts(0), 5.5, 1.9)
            top = 8
        elseif kind == "centipede" then
            parts = flip(centiHeadParts(0), 4.4, 1.7)
            top = 5
        elseif kind == "centseg" then
            parts = flip(centiSegParts(0), 4.4, 1.6)
            top = 5
        elseif kind == "bombardier" then
            parts = flip(bombardierParts(0), 9, 2.3)
            top = 11
        elseif kind == "springtail" then
            parts = flip(springtailParts(0), 3.4, 1.3)
            top = 2
        elseif kind == "click" then
            parts = flip(clickParts(0), 7, 2.2)
            top = 9
        elseif kind == "mole" then
            parts = flip(moleParts(0), 7, 2.2)
            top = 9
        elseif kind == "cricket" then
            parts = flip(moleParts(0), 4.3, 1.35)
            top = 5
        elseif kind == "centi" then
            parts = flip(centiHeadParts(0), 2.3, 0.9)
            top = 3
        elseif kind == "centiseg" then
            parts = flip(centiSegParts(0), 2.2, 0.85)
            top = 3
        elseif kind == "ball" then
            -- A broken ball is a heap.
            parts = {}
            for k = 0, 6 do
                local a = k * 2.39
                local r = k == 0 and 0 or 4 + (k % 3) * 1.6
                parts[#parts + 1] = { id = 1 + k, ramp = R.dung, at = ell(cos(a) * r, 2, sin(a) * r, 4.2 - r * 0.25, 2.6 - r * 0.15, 4 - r * 0.2),
                    print = spotted(0.96, IDX.t) }
            end
        else
            parts = { { id = 1, ramp = RAMP.mite, at = ell(0, 0.5, 0, 1.2, 0.6, 1.1) } }
            top = 1
        end
        if fruited then fruit(parts, 0, top) end
        return place(parts, heading(hs / 8 * TAU))
    end)
end

return M
