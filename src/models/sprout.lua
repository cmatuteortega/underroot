-- The sprout, as each seed grows it (see src/models.lua).

local T = require "src.tracer"
local A = T.Affine

local sin, cos, atan2, abs, floor, sqrt = math.sin, math.cos, math.atan2, math.abs, math.floor, math.sqrt
local ell, RAMP, IDX = T.ell, T.RAMP, T.IDX
local TAU = 2 * math.pi
local ramp = T.ramp
local K = require "src.models.kit"
local kept, place, seg, R = K.kept, K.place, K.seg, K.R

local M = {}

--- the sprout -------------------------------------------------------------------

-- One plant per seed (D.SEEDS), each the brightest thing there is: their
-- leaves stay on the sprout's ramp whatever the seed, and the seed is told by
-- its silhouette and one pose. `wilt` 0..1 droops the leaves and bends the
-- stem as the Heart is hurt: you see it before the number tells you. `pose`
-- is the seed's own state: a dandelion that has spent its life ("bald"), a
-- sunflower at night ("night"), a flytrap biting ("shut").
local SR = {
    acorn = ramp("w", "t", "t", "n"),
    bark = R.bark,
    disc = ramp("t", "n", "u", "o"),
    petal = ramp("w", "w", "w", "t"),
    green = ramp("w", "g", "m", "d"),
    turning = ramp("w", "t", "r", "n"),
    ripe = ramp("w", "r", "r", "u"),
    fluff = ramp("w", "w", "s", "k"),
}

local function vein(ux, uy, uz) if abs(uz) < 0.08 and uy > 0 then return IDX.m end end

-- The frame a leaf hangs from: at (x, y, z), turned `yaw` about the stem and
-- lifted `pitch` (0 flat, + up). A leaf's length runs along the frame's +x,
-- starting `at` out from it.
local function frame(x, y, z, yaw, pitch)
    return A.mul(A.move(x, y, z), A.rotY(yaw), A.rotZ(pitch))
end
local function leaf(f, len, wid, th, id, at)
    return { id = id, ramp = RAMP.sprout, print = vein,
        at = A.mul(f, A.move((at or 0) + len, 0, 0), A.scale(len, th, wid)) }
end
local function apply(m, x, y, z)
    return m[1] * x + m[2] * y + m[3] * z + m[4], m[5] * x + m[6] * y + m[7] * z + m[8],
        m[9] * x + m[10] * y + m[11] * z + m[12]
end

local SEED = {}

-- The bean: two seed leaves on a stem, and the coat it split, at its foot.
function SEED.bean(w)
    local up = 0.42 - 0.95 * w
    local parts = {
        { id = 1, ramp = RAMP.sprout, at = ell(0, 6, 0, 1.2, 6, 1.2) },
        leaf(frame(0, 12, 0, 0, up), 4.2, 2.3, 0.9, 2),
        leaf(frame(0, 12, 0, math.pi, up), 4.2, 2.3, 0.9, 3),
        { id = 4, ramp = RAMP.sprout, at = ell(0, 12.6, 0, 1.1, 1.5, 1.1) },
        { id = 5, ramp = SR.acorn, at = A.mul(A.move(2.2, 1.5, 1.2), A.rotY(0.5), A.rotZ(0.5), A.scale(2.4, 0.9, 1.6)),
            print = function(ux, uy, uz) if abs(ux + 0.55) < 0.12 and uy > 0 then return IDX.n end end },
        { id = 6, ramp = SR.acorn, at = A.mul(A.move(-2.0, 1.4, -1.4), A.rotY(2.4), A.rotZ(0.35), A.scale(2.2, 0.9, 1.5)) },
    }
    return place(parts, A.scale(1.5, 1.5, 1.5), A.rotZ(-0.25 * w), A.rotY(0.7))
end

-- The oak: a thick woody stem out of a half-sunk acorn, and lobed leaves that
-- droop less than anyone's. Its bulk is its HP.
local function oakleaf(parts, f, s, id)
    parts[#parts + 1] = leaf(f, 3.0 * s, 1.3 * s, 0.6, id)
    -- Lobes down each side, under the leaf's own id: one silhouette.
    for k, t in ipairs({ 0.35, 0.75, 1.15 }) do
        local d = (1.25 - 0.18 * k) * s
        for side = -1, 1, 2 do
            parts[#parts + 1] = { id = id, ramp = RAMP.sprout,
                at = A.mul(f, A.move((0.6 + t * 2.0) * s, 0, side * 0.9 * s), A.scale(0.9 * s, 0.55, d * 0.8)) }
        end
    end
end
function SEED.oak(w)
    local droop = 0.55 - 0.5 * w
    local parts = {
        { id = 1, ramp = SR.acorn, at = ell(1.6, 1.4, 1.4, 2.2, 2.0, 2.2) },
        { id = 2, ramp = SR.bark, at = ell(1.6, 2.9, 1.4, 2.5, 1.2, 2.5),
            print = function(ux, uy, uz, lev)
                if lev > 1 and uy > 0.2 and (floor(ux * 4 + 4) + floor(uz * 4 + 4)) % 2 == 0 then return IDX.u end
            end },
        seg(0.9, 2.5, 0.9, 0, 8, 0, 1.3, SR.bark, 3),
        seg(0, 8, 0, 0, 12, 0, 1.0, SR.bark, 3),
        { id = 4, ramp = RAMP.sprout, at = ell(0, 12.8, 0, 1.1, 1.5, 1.1) },
    }
    oakleaf(parts, frame(0, 12, 0, 0.3, droop), 1.45, 5)
    oakleaf(parts, frame(0, 12, 0, math.pi + 0.3, droop), 1.45, 6)
    oakleaf(parts, frame(0, 11.5, 0, math.pi * 0.5 + 0.4, droop - 0.25), 1.0, 7)
    return place(parts, A.scale(1.4, 1.4, 1.4), A.rotZ(-0.1 * w), A.rotY(0.4))
end

-- The tomato: soft and leggy, and one fruit on a truss that ripens as the
-- Heart runs down -- green, turning, then rust, about to burst.
local function leaflets(parts, f, s, id)
    parts[#parts + 1] = leaf(f, 1.4 * s, 0.75 * s, 0.4, id, 2.4 * s)
    for _, t in ipairs({ 0.6, 1.7 }) do
        for side = -1, 1, 2 do
            parts[#parts + 1] = { id = id, ramp = RAMP.sprout, print = vein,
                at = A.mul(f, A.move(t * s, 0, side * 0.9 * s), A.rotY(-side * 0.6), A.scale(0.95 * s, 0.4, 0.5 * s)) }
        end
    end
    parts[#parts + 1] = { id = id, ramp = RAMP.sprout, at = A.mul(f, A.move(1.6 * s, 0, 0), A.scale(1.8 * s, 0.25, 0.2)) }
end
function SEED.tomato(w)
    local up = 0.5 - 1.0 * w
    local parts = {
        seg(0, 0, 0, 0.3, 10, 0, 0.75, RAMP.sprout, 1),
        seg(0.3, 10, 0, 0, 17, 0, 0.6, RAMP.sprout, 1),
        { id = 2, ramp = RAMP.sprout, at = ell(0, 17.4, 0, 0.9, 1.2, 0.9) },
        leaf(frame(0.2, 8, 0, 0.2, up - 0.1), 3.2, 1.0, 0.5, 3),
        leaf(frame(0.2, 8, 0, math.pi + 0.2, up - 0.1), 3.2, 1.0, 0.5, 4),
    }
    leaflets(parts, frame(0, 15, 0, math.pi * 0.5 + 0.5, up + 0.1), 1.5, 5)
    leaflets(parts, frame(0, 13.5, 0, math.pi * 1.5 + 0.3, up), 1.4, 6)
    local fruit = w < 0.3 and SR.green or (w < 0.7 and SR.turning or SR.ripe)
    local fx, fy, fz = 3.4, 6.5 - 1.5 * w, 1.6
    parts[#parts + 1] = seg(0.25, 11, 0.1, fx, fy + 3.2, fz, 0.3, RAMP.sprout, 7)
    parts[#parts + 1] = { id = 8, ramp = fruit, at = ell(fx, fy, fz, 2.6, 2.3, 2.6) }
    for k = 0, 4 do
        parts[#parts + 1] = { id = 9, ramp = RAMP.sprout,
            at = A.mul(A.move(fx, fy + 2.2, fz), A.rotY(k * TAU / 5), A.rotZ(-0.35), A.move(1.0, 0, 0), A.scale(1.1, 0.25, 0.35)) }
    end
    return place(parts, A.scale(1.4, 1.4, 1.4), A.rotZ(-0.3 * w), A.rotY(0.6))
end

-- The dandelion: a flat rosette of toothed leaves and a seed clock on a hollow
-- stalk (there is no yellow; the clock is its flower). Bald, half the clock
-- has blown and two seeds are on the wind: the life it had is spent.
local CLOCK = {}
for n = 0, 40 do
    local a, e = n * 2.39996, math.asin(-0.85 + (n / 40) * 1.85)
    CLOCK[#CLOCK + 1] = { cos(a) * cos(e), sin(e), sin(a) * cos(e) }
end
function SEED.dandelion(w, pose)
    local bald = pose == "bald" and 0.55 or 0
    local parts = {}
    for k = 0, 5 do
        local f = frame(0, 0.8, 0, k * TAU / 6 + 0.3, 0.12 - 0.1 * w)
        local len = k % 2 == 0 and 5.5 or 4.6
        parts[#parts + 1] = leaf(f, len, 1.0, 0.45, 1 + k)
        -- the lion's teeth, swept back
        for _, t in ipairs({ 0.35, 0.65, 0.9 }) do
            for side = -1, 1, 2 do
                parts[#parts + 1] = { id = 1 + k, ramp = RAMP.sprout,
                    at = A.mul(f, A.move(t * 2 * len, 0, side * 0.9), A.rotY(side * 0.7), A.scale(0.9, 0.4, 0.45)) }
            end
        end
    end
    local bend = 0.35 * w
    local hx, hy = 13 * sin(bend), 14 * cos(bend) + 1
    parts[#parts + 1] = seg(0, 0.5, 0, hx * 0.5, hy * 0.55, 0, 0.55, RAMP.sprout, 10)
    parts[#parts + 1] = seg(hx * 0.5, hy * 0.55, 0, hx, hy, 0, 0.5, RAMP.sprout, 10)
    parts[#parts + 1] = { id = 11, ramp = RAMP.sprout, at = ell(hx, hy, 0, 0.9, 0.7, 0.9) }
    local rad = 4.4 * (1 - 0.15 * w)
    local clock = { id = 12, ramp = SR.fluff, at = ell(hx, hy + 0.6, 0, rad, rad, rad),
        print = function(ux, uy, uz)
            for n, d in ipairs(CLOCK) do
                if n / #CLOCK < bald and d[1] * ux + d[2] * uy + d[3] * uz > 0.6 then return IDX.k end
                if d[1] * ux + d[2] * uy + d[3] * uz > 0.985 then return IDX.s end
            end
        end }
    -- The blown side is a bare knob, shrunk in.
    if bald > 0 then clock.at = A.mul(clock.at, A.move(0.25, 0.1, 0.25), A.scale(0.8, 0.8, 0.8)) end
    parts[#parts + 1] = clock
    for n, d in ipairs(CLOCK) do
        if n % 3 == 0 and n / #CLOCK >= bald then
            parts[#parts + 1] = { id = 12, ramp = SR.fluff,
                at = ell(hx + d[1] * rad * 1.02, hy + 0.6 + d[2] * rad * 1.02, d[3] * rad * 1.02, 0.9, 0.9, 0.9) }
        end
    end
    if bald > 0 then
        for k, s in ipairs({ { 6, 6, -3 }, { 9, 10, -5 } }) do
            parts[#parts + 1] = seg(hx + s[1], hy + s[2] - 2, s[3], hx + s[1], hy + s[2], s[3], 0.18, SR.fluff, 20 + k)
            parts[#parts + 1] = { id = 22 + k, ramp = SR.fluff, at = ell(hx + s[1], hy + s[2] + 0.4, s[3], 1.1, 0.5, 1.1) }
        end
    end
    return place(parts, A.scale(1.35, 1.35, 1.35), A.rotY(0.9))
end

-- The sunflower: the tallest, a seed disc ringed with petals tipped up at the
-- lamp. At night its head bows and the petals fold: its sun is out.
function SEED.sunflower(w, pose)
    local night = pose == "night"
    local parts = {
        seg(0, 0, 0, 0.3, 11, 0, 0.95, RAMP.sprout, 1),
        seg(0.3, 11, 0, 0, 20, 0, 0.8, RAMP.sprout, 1),
        leaf(frame(0.2, 8, 0, 0.5, 0.35 - 0.8 * w), 3.4, 2.6, 0.5, 2),
        leaf(frame(0.2, 12.5, 0, math.pi + 0.9, 0.3 - 0.8 * w), 3.0, 2.3, 0.5, 3),
    }
    -- In H the face looks along +x.
    local H = A.mul(A.move(0.4, 21, 0), A.rotY(night and 0.4 or -0.35), A.rotZ(night and -1.25 or 0.55 - 0.5 * w),
        A.move(1.2, 0, 0))
    local r = 3.0
    parts[#parts + 1] = { id = 4, ramp = SR.disc, at = A.mul(H, A.scale(0.9, r, r)),
        print = function(ux, uy, uz)
            if ux < 0 then return end
            local d = sqrt(uy * uy + uz * uz)
            if (atan2(uz, uy) * 3 + d * 9) % 2 < 0.7 then return IDX.u end
            if d < 0.25 then return IDX.n end
        end }
    parts[#parts + 1] = { id = 5, ramp = RAMP.sprout, at = A.mul(H, A.move(-0.8, 0, 0), A.scale(0.9, r * 1.05, r * 1.05)) }
    local fold = night and 0.9 or 0.15
    for k = 0, 11 do
        parts[#parts + 1] = { id = 6 + k % 2, ramp = SR.petal,
            at = A.mul(H, A.rotX(k * TAU / 12), A.move(-0.1, r, 0), A.rotZ(fold), A.move(0, 1.7, 0), A.scale(0.35, 2.0, 0.8)) }
    end
    return place(parts, A.scale(1.3, 1.3, 1.3), A.rotY(0.5))
end

-- The flytrap: low and wide, a rosette of hinged jaws on winged stalks, rust
-- inside and toothed at the rim -- the one seed in the enemy's colour, the one
-- that bites. Shut, the jaws clamp and the red is gone.
local function trap(parts, yaw, len, s, open, id)
    local f = A.rotY(yaw)
    parts[#parts + 1] = { id = id, ramp = RAMP.sprout, print = vein,
        at = A.mul(f, A.rotZ(0.25), A.move(len * 0.5, 0.6, 0), A.scale(len * 0.5, 0.35, 0.9 * s)) }
    local hx, hy, hz = apply(f, len, 0.6 + len * 0.25, 0)
    local base = A.mul(A.move(hx, hy, hz), A.rotY(yaw), A.rotZ(0.55), A.move(2.0 * s, 0, 0))
    for side = -1, 1, 2 do
        local L = A.mul(base, A.rotX(-side * (math.pi / 2 - open)), A.move(0, 0, side * 1.5 * s), A.scale(2.0 * s, 0.4, 1.5 * s))
        parts[#parts + 1] = { id = id + (side == 1 and 1 or 2), ramp = RAMP.sprout, at = L,
            print = function(ux, uy) if uy > 0.15 then return IDX.r end end }
        for k = 1, 6 do
            local t = 0.12 * math.pi + (k - 1) * 0.76 * math.pi / 5
            local ex, ez = cos(t), side * sin(t)
            local x0, y0, z0 = apply(L, ex * 0.95, 0, ez * 0.95)
            local x1, y1, z1 = apply(L, ex * 1.45, 0, ez * 1.55)
            parts[#parts + 1] = seg(x0, y0, z0, x1, y1, z1, 0.22, R.flesh, id + 3)
        end
    end
end
function SEED.flytrap(w, pose)
    local open = (pose == "shut" and 0.05 or 0.6) * (1 - 0.5 * w)
    local parts = { { id = 1, ramp = RAMP.sprout, at = ell(0, 0.6, 0, 1.4, 0.8, 1.4) } }
    trap(parts, 2.5, 3.5, 1.0, open, 10)
    trap(parts, -2.3, 3.5, 1.0, open, 20)
    trap(parts, 0.75, 2.6, 1.35, open, 30)
    return place(parts, A.scale(1.6, 1.6, 1.6))
end

-- `seed` a D.SEEDS id, the bean if not given.
function M.sprout(wilt, seed, pose)
    local ws = floor(wilt * 4 + 0.5)
    seed = SEED[seed] and seed or "bean"
    return kept("sprout" .. seed .. ws .. (pose or ""), function()
        return SEED[seed](ws / 4, pose)
    end)
end

return M
