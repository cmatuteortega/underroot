-- The fruiting bodies, every species at every tier (see src/models.lua).

local T = require "src.tracer"
local A = T.Affine

local sin, cos, atan2, abs, floor, sqrt = math.sin, math.cos, math.atan2, math.abs, math.floor, math.sqrt
local ell, RAMP, IDX = T.ell, T.RAMP, T.IDX
local TAU = 2 * math.pi
local ramp = T.ramp
local K = require "src.models.kit"
local kept, place, join, seg, spotted, R = K.kept, K.place, K.join, K.seg, K.spotted, K.R

local M = {}

--- fruiting bodies ------------------------------------------------------------------

local function breath(idle) return sin(idle / 4 * TAU) end

-- A puffball on a little skirt, centred at (x, z), `r` across. `q` 0..1 is how
-- far it is squashed letting go: it flattens and its pore opens.
local function puffball(x, z, r, q, rmp, id, spot, stripes)
    local h = r * (0.9 - 0.25 * q)
    local w = r * (1 + 0.14 * q)
    local pore = 0.93 - 0.12 * q
    return {
        { id = id, ramp = R.crumb, at = ell(x, r * 0.25, z, r * 0.55, r * 0.35, r * 0.55) },
        { id = id + 1, ramp = rmp, at = ell(x, r * 0.35 + h, z, w, h, w),
            print = function(ux, uy, uz, lev)
                if uy > pore then return IDX.n end -- the pore it puffs from
                if uy > pore - 0.06 then return IDX.u end
                if stripes and lev >= 2 and abs((uy * 4 + 4) % 1 - 0.5) < 0.07 then return IDX.n end
                return spotted(0.975, spot or IDX.t)(ux, uy, uz, lev)
            end },
    }
end

local function puffer(b, tier, idle, fire)
    local q = fire / 2
    local br = 1 + 0.03 * breath(idle)
    local parts = {}
    if not b then
        parts[1] = { id = 1, ramp = R.crumb, at = ell(0, 1, 0, 3.6, 1.3, 3.6) }
        join(parts, puffball(0, 0, 4.8 * br, q, R.flesh, 2))
    elseif b == 1 then
        -- Toxin: the flesh goes green, it sweats, and at the second tier it is
        -- ringed with little ones and a haze hangs over it.
        parts[1] = { id = 1, ramp = R.moss, at = ell(0, 1, 0, 4, 1.3, 4) }
        local r = (tier == 1 and 5.2 or 5.8) * br
        join(parts, puffball(0, 0, r, q, R.toxic, 2, IDX.d))
        for k = 0, 2 do
            local a = k * 2.1 + 0.4
            parts[#parts + 1] = { id = 4, ramp = R.toxic, at = ell(cos(a) * r * 0.75, r * 0.7 - (idle % 2) * 0.3, sin(a) * r * 0.75, 0.45, 0.7, 0.45) }
        end
        if tier == 2 then
            for k = 0, 2 do
                local a = k * 2.1 + 1.4
                join(parts, puffball(cos(a) * 6.6, sin(a) * 6.6, 2.3, q, R.toxic, 6 + k * 2, IDX.d))
            end
        end
    else
        -- Rapid fire: a clutch of smaller puffballs that take turns.
        parts[1] = { id = 1, ramp = R.crumb, at = ell(0, 1, 0, 4.6, 1.3, 4.2) }
        local spots = tier == 1 and { { -2.4, 0.6, 3.9 }, { 2.6, -0.8, 3.5 } }
            or { { -2.6, 1.6, 3.9 }, { 2.7, 0.6, 3.6 }, { -0.2, -2.8, 3.4 } }
        for k, s in ipairs(spots) do
            local qq = (k + fire) % 2 == 0 and q or q * 0.3
            join(parts, puffball(s[1], s[2], s[3] * (1 + 0.03 * breath(idle + k)), qq, R.flesh, 2 + k * 2, IDX.t, tier == 2))
        end
    end
    return parts
end

-- The sniper: a clump of enoki, tall thin stalks with pin-head caps. Skewer
-- grows it taller and sharper; Mark lights the caps.
local ENOKI = { { 0, 0, 12 }, { 2.2, 1, 10 }, { -2, 1.4, 9.5 }, { 1.2, -2.2, 10.5 }, { -1.5, -1.8, 8.5 },
    { 2.8, -1, 8 }, { -2.6, -0.4, 11 }, { 0.6, 2.6, 9 }, { -0.4, -3, 9.6 } }
local function needle(b, tier, idle, fire)
    local n = 5
    local tall = 1
    if b == 1 then n, tall = tier == 1 and 7 or 9, tier == 1 and 1.15 or 1.3 end
    if b == 2 then n, tall = tier == 1 and 6 or 7, tier == 1 and 1.05 or 1.15 end
    local squash = 1 - 0.08 * fire
    local capRamp = b == 2 and R.glowcap or R.flesh
    local parts = { { id = 1, ramp = R.crumb, at = ell(0, 0.6, 0, 3.6 + n * 0.12, 1.2, 3.6 + n * 0.12) } }
    for k = 1, n do
        local s = ENOKI[k]
        local h = s[3] * tall * squash
        local sw = 0.05 * sin(idle / 4 * TAU + k)
        local lean = A.mul(A.rotZ(-s[1] * 0.05 + sw), A.rotX(s[2] * 0.05 + sw * 0.5))
        parts[#parts + 1] = { id = k * 2, ramp = R.flesh, at = A.mul(lean, ell(s[1], h / 2, s[2], 0.7, h / 2, 0.7)) }
        local cap
        if b == 1 and tier == 2 and k == 1 then
            -- The lance: one stalk far above the rest, with a spear for a cap.
            h = h * 1.35
            parts[#parts] = { id = k * 2, ramp = R.flesh, at = A.mul(lean, ell(s[1], h / 2, s[2], 0.85, h / 2, 0.85)) }
            cap = ell(s[1], h + 1.2, s[2], 1.2, 2.6, 1.2)
        elseif b == 1 then
            cap = ell(s[1], h + 0.4, s[2], 1.3, 1.5, 1.3)
        else
            cap = ell(s[1], h, s[2], 1.7, 0.9, 1.7)
        end
        parts[#parts + 1] = { id = k * 2 + 1, ramp = capRamp, at = A.mul(lean, cap),
            print = fire > 0 and function(ux, uy) if uy > 0.3 then return IDX.l end end or nil }
    end
    if b == 2 and tier == 2 then
        -- A halo of glowing spores turns over the clump.
        for k = 0, 5 do
            local a = k / 6 * TAU + idle * 0.26
            parts[#parts + 1] = { id = 40 + k, ramp = R.glowcap, at = ell(cos(a) * 4.5, 16 + sin(a * 2) * 0.8, sin(a) * 4.5, 0.7, 0.7, 0.7) }
        end
    end
    return parts
end

-- The healer: a shaggy white shelf on a stub, hung all round with spines.
-- Regrowth stacks more tiers; Purge tips the spines with glow and crowns it.
local function mane(b, tier, idle, fire)
    local layers = (b == 1) and (tier + 1) or 1
    local big = (b == 2 and tier == 2) and 1.15 or 1
    local glow = b == 2
    local parts = { { id = 1, ramp = R.crumb, at = ell(0, 2, 0, 1.8, 2.4 + layers, 1.8) } }
    for L = 1, layers do
        local s = big * (1 - (L - 1) * 0.2)
        local y = 7 + (L - 1) * 5.5
        local off = (L - 1) * 0.9
        parts[#parts + 1] = { id = 2 + L * 3, ramp = R.flesh, at = ell(off, y, -off * 0.5, 6 * s, 3.4 * s, 5.6 * s),
            print = function(ux, uy, uz, lev)
                if lev >= 2 and sin(atan2(uz, ux) * 13 + uy * 3) > 0.3 then
                    return uy < 0 and IDX.w or IDX.t
                end
            end }
        for k = 0, 8 do
            local a = k * 0.698 + 0.2 + L
            local sw = 0.12 * sin(idle / 4 * TAU + k * 0.9)
            local x, z = off + cos(a) * 4.4 * s, -off * 0.5 + sin(a) * 4 * s
            local top = y - 2.6 * s
            local len = (2.4 + (k % 3) * 0.4) * s
            local p = seg(x, top, z, x + sw * 3, top - len * 2, z + sw * 2, 0.8 * s, R.flesh, 3 + L * 3 + k % 2)
            if glow then
                p.print = function(ux) if ux > 0.45 then return (fire > 0 or idle % 2 == 0) and IDX.l or IDX.c end end
            end
            parts[#parts + 1] = p
        end
    end
    if b == 2 and tier == 2 then
        for k = 0, 4 do
            local a = k / 5 * TAU
            local x, z = cos(a) * 2.6, sin(a) * 2.4
            local p = seg(x, 9.5, z, x * 1.5, 13.5 + (k % 2), z * 1.5, 0.6, R.glowcap, 30 + k)
            parts[#parts + 1] = p
        end
    end
    return parts
end

-- The hub: a low teal dome whose rings run outward (`idle` is the beat).
-- Battery hangs glowing bulbs off it; Amplifier raises a stalk of discs.
local function relay(b, tier, idle, fire)
    local beat = idle
    local w = 5.4 + (tier or 0) * 0.4
    local parts = {
        { id = 1, ramp = RAMP.teal, at = ell(0, 1.6, 0, w, 3.2, w),
            print = function(ux, uy, uz)
                local r = sqrt(ux * ux + uz * uz)
                if uy > 0 and abs((r + beat * 0.08) % 0.32 - 0.16) < 0.04 then return IDX.l end
            end },
        { id = 2, ramp = ramp("w", "w", "l", "c"), at = ell(0, 4.6, 0, 1.9, 1.9, 1.9) },
    }
    if b == 1 then
        local bulbs = tier == 1 and { 0.6 } or { 0.6, 3.4 }
        for k, a in ipairs(bulbs) do
            local x, z = cos(a) * (w + 0.8), sin(a) * (w + 0.8)
            parts[#parts + 1] = seg(x * 0.6, 2.5, z * 0.6, x, 4, z, 0.5, RAMP.teal, 10 + k)
            parts[#parts + 1] = { id = 12 + k, ramp = R.glowcap, at = ell(x, 5.8, z, 2, 2.4, 2),
                print = function(ux, uy) if uy < -0.2 + (beat % 4) * 0.25 then return IDX.l end end }
        end
    elseif b == 2 then
        local discs = tier == 1 and 1 or 2
        local top = 7 + discs * 4
        parts[#parts + 1] = seg(0, 5, 0, 0, top, 0, 0.8, RAMP.teal, 20)
        for k = 1, discs do
            local y = 6 + k * 4
            local s = 1 + 0.15 * ((beat + k) % 2)
            parts[#parts + 1] = { id = 20 + k, ramp = R.glowcap, at = ell(0, y, 0, 3.4 * s, 0.6, 3.4 * s),
                print = function(ux, uy, uz) if abs(sqrt(ux * ux + uz * uz) - 0.6) < 0.1 then return IDX.w end end }
        end
        parts[#parts + 1] = { id = 30, ramp = ramp("w", "w", "l", "c"), at = ell(0, top + 1, 0, 1.4, 1.4, 1.4) }
    end
    return parts
end

-- Laid on the trail rather than grown on a pocket: a flat glistening mat. Glue
-- goes thick and pale, then amber; Digest bubbles rust.
local function mat(b, tier, idle)
    local rmp = ramp("w", "l", "c", "d")
    local h = 1.5
    if b == 1 then rmp, h = tier == 1 and R.glue or R.amber, tier == 1 and 2.1 or 2.6 end
    local parts = {
        { id = 1, ramp = rmp, at = ell(0, 0, 0, 7.2, h, 7.2), print = spotted(0.985, IDX.w) },
        { id = 2, ramp = rmp, at = ell(2.5, 0.2, -2, 3.6, h * 0.95, 3.2) },
        { id = 2, ramp = rmp, at = ell(-2.6, 0.1, 2.2, 3.2, h * 0.95, 3.6) },
    }
    if b == 2 then
        local n = tier == 1 and 4 or 7
        for k = 1, n do
            local a = k * 2.39 + idle * 0.2
            local r = 1.5 + (k * 1.7) % 4.5
            local s = 0.9 + 0.5 * ((k + idle) % 3) / 2
            parts[#parts + 1] = { id = 4 + k, ramp = R.bubble, at = ell(cos(a) * r, h * 0.8, sin(a) * r, s, s, s) }
        end
    end
    return parts
end

-- Inky Cap: a tall bell that melts into ink from the rim up. Reach adds caps;
-- Big Ink melts it further and drips harder.
local function inky(b, tier, idle, fire)
    local caps = { { 0, 0, 1 } }
    if b == 1 then
        caps = tier == 1 and { { 0, 0, 1 }, { 3.6, 1.8, 0.75 } } or { { 0, 0, 1.1 }, { 3.8, 2, 0.8 }, { -3.2, 2.6, 0.7 } }
    end
    local melt = b == 2 and (tier == 1 and 0.25 or 0.5) or 0
    local parts = { { id = 1, ramp = R.crumb, at = ell(0, 0.8, 0, 3.4, 1.2, 3.4) } }
    for k, c in ipairs(caps) do
        local s = c[3] * 1.3 * (1 - 0.05 * fire)
        local x, z = c[1], c[2]
        local stalk = 6 * s
        parts[#parts + 1] = seg(x, 0, z, x, stalk, z, 0.8 * s, R.flesh, k * 4)
        local cy = stalk + 3.4 * s
        -- The rim, already gone to ink: a flared black skirt under the bell.
        local flare = 3.3 + melt * 2
        parts[#parts + 1] = { id = k * 4 + 3, ramp = R.ink, at = ell(x, cy - 2.6 * s, z, flare * s, (1.6 + melt * 1.5) * s, flare * s),
            print = function(ux, uy, uz) if abs(sin(atan2(uz, ux) * 11)) < 0.25 then return IDX.o end end }
        parts[#parts + 1] = { id = k * 4 + 1, ramp = R.inky, at = ell(x, cy, z, 2.8 * s, 4.6 * s * (1 + 0.02 * breath(idle)), 2.8 * s),
            print = function(ux, uy, uz, lev)
                if uy < -0.6 + melt then return IDX.o end
                if uy < -0.25 + melt then return (sin(atan2(uz, ux) * 9) > 0) and IDX.o or IDX.k end
                if uy > 0.2 and lev >= 2 and spotted(0.985, IDX.t)(ux, uy, uz, lev) then return IDX.t end
            end }
        -- Drips falling off the rim, a different one each beat.
        local drips = 2 + (b == 2 and tier * 2 or 0)
        for d = 1, drips do
            local a = d * 2.4 + k
            local fall = ((idle + d) % 4) / 4
            local dx, dz = x + cos(a) * 2.4 * s, z + sin(a) * 2.4 * s
            parts[#parts + 1] = { id = k * 4 + 2, ramp = R.ink, at = ell(dx, cy - 4.4 * s - fall * (stalk - 1), dz, 0.45, 0.7, 0.45) }
        end
    end
    if b == 2 then
        parts[#parts + 1] = { id = 30, ramp = R.ink, at = ell(0.5, 0.1, 0.5, 5 + tier * 1.6, 0.4, 4.5 + tier * 1.6) }
    end
    return parts
end

-- Shelf Fungus: brackets stacked up a stump, banded like a tree's rings.
-- Armor adds wood; Thorny bristles.
local function shelf(b, tier)
    local n = 3
    local big = 1
    if b == 1 then n, big = tier == 1 and 4 or 5, tier == 1 and 1.1 or 1.22 end
    local parts = { { id = 1, ramp = R.bark, at = ell(0, 5 * big, 0, 3.2 * big, 6 * big, 3 * big),
        print = function(ux, uy, uz) if abs(sin(atan2(uz, ux) * 7 + uy * 2)) < 0.12 then return IDX.o end end } }
    for k = 1, n do
        local a = k * 2.2
        local y = (2.2 + k * 2.3) * big
        local s = (1.15 - k * 0.1) * big
        local x, z = cos(a) * 3 * big, sin(a) * 3 * big
        local p = { id = 2 + k, ramp = R.shelf, at = A.mul(A.move(x, y, z), A.rotY(-a), A.scale(5.6 * s, 1.2 * s, 4.6 * s)),
            print = function(ux, uy, uz, lev)
                if uy > 0.2 then
                    local r = sqrt(ux * ux + uz * uz)
                    if abs((r * 4) % 1 - 0.5) < 0.12 then return IDX.n end
                    if r > 0.88 then return IDX.w end
                end
            end }
        parts[#parts + 1] = p
        if b == 2 then
            local spikes = tier == 1 and 4 or 7
            for sp = 1, spikes do
                local t = (sp / (spikes + 1) - 0.5) * 2.4
                local ex, ez = x + cos(a + t) * 5 * s, z + sin(a + t) * 4.2 * s
                parts[#parts + 1] = seg(ex, y, ez, ex + cos(a + t) * 2.2, y + 0.8, ez + sin(a + t) * 2.2, 0.35, R.ink, 20)
            end
        end
    end
    return parts
end

-- Puffball Mortar: a great scaly earthball on a squat foot. Cluster ring it
-- with bomblets; Smoke turns it sooty.
local function mortar(b, tier, idle, fire)
    local q = fire / 2
    local rmp = b == 2 and R.smoke or R.earth
    local r = 6.4 + (tier or 0) * 0.4
    local h = r * (0.88 - 0.22 * q) * (1 + 0.02 * breath(idle))
    local w = r * (1 + 0.15 * q)
    local parts = {
        { id = 1, ramp = R.crumb, at = ell(0, 1.2, 0, 5, 1.8, 5) },
        { id = 2, ramp = rmp, at = ell(0, 2 + h, 0, w, h, w),
            print = function(ux, uy, uz, lev)
                if uy > 0.9 - 0.15 * q then return IDX.o end
                if uy > 0.84 - 0.15 * q then return IDX.u end
                local a = atan2(uz, ux) * 5 / math.pi
                local e = uy * 4
                local fa, fe = a - floor(a + (floor(e) % 2) * 0.5), e - floor(e)
                if lev >= 2 and (abs(fa - 0.5) > 0.42 or fe < 0.1) then return IDX.u end
                if b == 2 and tier == 2 and uy > 0.5 and abs(sin(a * 7)) < 0.15 then return IDX.w end
            end },
    }
    if b == 1 then
        local n = tier == 1 and 3 or 5
        for k = 1, n do
            local a = k / n * TAU + 0.3
            join(parts, puffball(cos(a) * (r + 2.4), sin(a) * (r + 2.4), 2.1, q, R.earth, 4 + k * 2, IDX.n))
        end
    elseif b == 2 then
        for k = 0, tier + 1 do
            local a = k * 1.9 + idle * 0.3
            parts[#parts + 1] = { id = 20 + k, ramp = R.smoke, at = ell(cos(a) * 2, 2 + 2 * h + 2 + k * 2.2 + (idle % 2) * 0.5, sin(a) * 2,
                2.6 - k * 0.3, 1.8, 2.6 - k * 0.3) }
        end
    end
    return parts
end

-- Cordyceps: orange clubs twisting up out of moss. Control lengthens them;
-- Spread swells their heads into spore balls.
local CLUBS = { { 0, 0, 9 }, { 2.2, 1.2, 7 }, { -2, 1.5, 7.5 }, { 1.4, -2.1, 8 }, { -1.6, -1.8, 6.5 }, { 3, -0.6, 6 }, { -3, -0.2, 6.8 } }
local function cordyceps(b, tier, idle, fire)
    local n, tall, head = 5, 1, 1
    if b == 1 then n, tall = tier == 1 and 6 or 7, tier == 1 and 1.2 or 1.4 end
    if b == 2 then n, head = tier == 1 and 5 or 6, tier == 1 and 1.5 or 1.9 end
    local parts = { { id = 1, ramp = R.moss, at = ell(0, 0.8, 0, 4.2, 1.4, 4.2), print = spotted(0.97, IDX.d) } }
    for k = 1, n do
        local c = CLUBS[k]
        local h = c[3] * tall * (1 - 0.1 * fire)
        local tw = 0.18 * sin(idle / 4 * TAU + k * 1.3)
        local tx, tz = c[1] * 1.5 + cos(k + tw * 4) * 1.2, c[2] * 1.5 + sin(k + tw * 4) * 1.2
        local mx, mz = (c[1] + tx) / 2 + tw * 2, (c[2] + tz) / 2 - tw * 2
        parts[#parts + 1] = seg(c[1], 0.5, c[2], mx, h * 0.55, mz, 0.95, R.cord, 2 + k)
        parts[#parts + 1] = seg(mx, h * 0.55, mz, tx, h, tz, 0.8, R.cord, 2 + k)
        if b == 2 then
            parts[#parts + 1] = { id = 20 + k, ramp = R.cord, at = ell(tx, h + 1.2 * head, tz, 1.1 * head, 1.2 * head, 1.1 * head),
                print = spotted(0.95, IDX.w) }
        else
            parts[#parts + 1] = seg(tx, h - 0.5, tz, tx + (tx - mx) * 0.2, h + 2.6, tz + (tz - mz) * 0.2, 1.3, R.cord, 20 + k)
            parts[#parts].print = function(ux, uy, uz) if ux > -0.6 and abs((ux * 5 + uz * 3) % 1) < 0.2 then return IDX.n end end
        end
    end
    return parts
end

-- Stinkhorn: a spongy white stalk out of an egg, its tip a slimy olive cap
-- the flies come to. Wider Stench raises more of them, dripping; Panic turns
-- it into a basket stinkhorn -- a red lattice ball -- and at Terror the
-- lattice splits into arms.
local function stinkhorn(b, tier, idle, fire)
    local sway = 0.06 * breath(idle)
    local q = fire / 2
    local parts = {}
    local function egg(x, z, s, id)
        parts[#parts + 1] = { id = id, ramp = R.flesh, at = ell(x, 1.3 * s, z, 3.8 * s, 2 * s, 3.8 * s),
            print = function(ux, uy, uz) if uy > 0.55 and abs(sin(atan2(uz, ux) * 5)) < 0.2 then return IDX.t end end }
    end
    if b == 2 then
        -- The basket: a ball of red lattice, its holes dark.
        local r = (tier == 1 and 5 or 5.6) * (1 + 0.04 * breath(idle) - 0.08 * q)
        egg(0, 0, 1.15, 1)
        parts[#parts + 1] = { id = 2, ramp = R.cord, at = ell(0, 2 + r * 0.9, 0, r, r * 0.9, r),
            print = function(ux, uy, uz)
                local a = (atan2(uz, ux) / TAU * 9 + uy * 0.8) % 1
                local e = (uy * 2.4 + 3) % 1
                if a > 0.2 and a < 0.8 and e > 0.22 and e < 0.78 then return IDX.o end
            end }
        if tier == 2 then
            for k = 0, 4 do
                local a = k / 5 * TAU + 0.3
                local x, z = cos(a) * r * 0.8, sin(a) * r * 0.8
                local curl = 0.8 * sin(idle / 4 * TAU + k)
                parts[#parts + 1] = seg(x * 0.9, 2 + r * 0.6, z * 0.9, x * 1.8, 2.6, z * 1.8, 1.5, R.cord, 10 + k)
                parts[#parts + 1] = seg(x * 1.8, 2.6, z * 1.8, x * 2.1, 6 + curl, z * 2.1, 1.1, R.cord, 10 + k)
            end
        end
        return parts
    end
    local stalks = { { 0, 0, 13 } }
    if b == 1 then
        stalks = tier == 1 and { { 0, 0, 14 }, { 4.2, 1.8, 10 } } or { { 0, 0, 15 }, { 4.4, 2, 11 }, { -3.8, 2.6, 9.5 } }
    end
    for k, st in ipairs(stalks) do
        local x, z, h = st[1], st[2], st[3] * (1 - 0.08 * q)
        egg(x, z, 1 - (k - 1) * 0.15, k * 4)
        local lean = A.mul(A.move(x, 0, z), A.rotZ(sway * (k % 2 == 0 and -1 or 1)), A.move(-x, 0, -z))
        local stalk = seg(x, 1.5, z, x, h, z, 2.1, R.flesh, k * 4 + 1)
        stalk.print = function(ux, uy, uz) if abs(sin(ux * 17) * sin(atan2(uz, uy) * 6)) > 0.75 then return IDX.t end end
        stalk.at = A.mul(lean, stalk.at)
        parts[#parts + 1] = stalk
        parts[#parts + 1] = { id = k * 4 + 2, ramp = R.gleba, at = A.mul(lean, ell(x, h + 2, z, 2.7, 3.8, 2.7)),
            print = function(ux, uy, uz)
                if uy > 0.9 then return IDX.w end -- the pale tip
                if abs(sin(atan2(uz, ux) * 6)) < 0.18 or abs(sin(uy * 9)) < 0.15 then return IDX.o end
            end }
        if b == 1 and tier == 2 then
            -- Slime running off the cap.
            local fall = ((idle + k) % 4) / 4
            parts[#parts + 1] = { id = k * 4 + 3, ramp = R.gleba, at = A.mul(lean, ell(x + 2.4, h - 1 - fall * 6, z + 0.8, 0.6, 1, 0.6)) }
        end
    end
    return parts
end

-- Ghost Lamp: the ghost fungus, fans of glowing caps on a stub. The glow
-- breathes (`idle`). Longer Glow fans out more caps; Flare swells glowing
-- sacs among them, about to burst.
local function lamp(b, tier, idle, fire)
    local caps = { { 0.4, 0.2, 0, 1 }, { 2.4, -1.6, 2.2, 0.8 }, { -2.2, 1.4, 4.2, 0.85 } }
    if b == 1 then
        caps[#caps + 1] = { 1.6, 2.6, 1.2, 0.75 }
        if tier == 2 then caps[#caps + 1] = { -2.4, -2, 5.4, 0.9 }; caps[#caps + 1] = { 0.2, -3, 3.1, 0.7 } end
    end
    local pulse = idle % 2 == 0
    local parts = { { id = 1, ramp = R.crumb, at = ell(0, 1.2, 0, 3.4, 1.6, 3.4) } }
    for k, c in ipairs(caps) do
        local x, z, a, s = c[1] * 1.2, c[2] * 1.2, c[3], c[4] * (b == 1 and 1.45 or 1.3)
        local h = 4.6 + k % 3 * 2
        parts[#parts + 1] = seg(x * 0.4, 1, z * 0.4, x, h, z, 0.7, R.flesh, 2)
        -- A fan, tilted out from the middle, gills glowing underneath.
        parts[#parts + 1] = { id = 4 + k, ramp = R.glowcap,
            at = A.mul(A.move(x, h + 0.6, z), A.rotY(-a), A.rotZ(0.35), A.scale(4 * s, 1.2 * s, 3.4 * s)),
            print = function(ux, uy, uz, lev)
                if uy < -0.1 then return abs(sin(atan2(uz, ux) * 9)) < 0.3 and IDX.c or IDX.l end
                if uy > 0.4 and (pulse or fire > 0) and ux * ux + uz * uz < 0.25 then return IDX.w end
            end }
    end
    if b == 2 then
        local n = tier == 1 and 2 or 4
        for k = 1, n do
            local a = k * 2.3 + 0.5
            local r = (1.5 + 0.2 * (idle % 2)) * (tier == 2 and 1.2 or 1)
            parts[#parts + 1] = { id = 20 + k, ramp = R.glowcap, at = ell(cos(a) * 3, 2 + r + (k % 2) * 3, sin(a) * 3, r, r, r),
                print = function(ux, uy) if uy > 0.4 then return IDX.w end end }
        end
    end
    return parts
end

-- The Humongous Fungus: honey mushrooms, a crowd of scaly caps on ringed
-- stems over a tangle of black bootlace cords running out into the soil.
-- Spreading raises more of them; Honey drips amber off every cap.
local HONEY = { { 0, 0, 15, 5 }, { 4.6, 2, 11, 4 }, { -4.2, 2.6, 12, 4.2 }, { 2.4, -4.4, 10, 3.6 },
    { -3, -4, 9, 3.4 }, { 6.4, -2.4, 7.5, 3 }, { -6.6, -1, 8, 3.2 }, { 1.2, 5.6, 8.5, 3.2 },
    { -1.6, 7, 6.5, 2.8 }, { 7, 4.4, 6, 2.6 }, { -7.4, 4.2, 6.4, 2.6 }, { 4, -7.2, 6.2, 2.6 }, { -5.6, -6.6, 5.5, 2.4 } }
local function giant(b, tier, idle, fire)
    local n = 7
    if b == 1 then n = tier == 1 and 10 or 13 end
    if b == 2 then n = tier == 1 and 8 or 9 end
    local q = fire / 2
    local parts = { { id = 1, ramp = R.dung, at = ell(0, 0.3, 0, 9.5, 1.3, 9),
        print = function(ux, uy, uz) if abs(sin(atan2(uz, ux) * 9 + sqrt(ux * ux + uz * uz) * 6)) < 0.25 then return IDX.o end end } }
    -- Bootlaces: the rhizomorphs it really is, mostly underground.
    for k = 0, 7 do
        local a = k / 8 * TAU + 0.2
        local r = 12 + (k % 3) * 2.5 + (b == 1 and tier * 2 or 0)
        parts[#parts + 1] = seg(cos(a) * 7, 0.6, sin(a) * 7, cos(a + 0.25) * r, 0.2, sin(a + 0.25) * r, 0.55, R.ink, 2)
    end
    for k = 1, n do
        local c = HONEY[k]
        local x, z, h, r = c[1] * 1.15, c[2] * 1.15, c[3] * 1.2 * (1 - 0.06 * q), c[4] * (b == 2 and 1.08 or 1)
        local sw = 0.04 * sin(idle / 4 * TAU + k)
        local lean = A.mul(A.rotZ(-x * 0.012 + sw), A.rotX(z * 0.012))
        local stem = seg(x * 0.6, 0.5, z * 0.6, x, h, z, 0.9 + r * 0.12, R.flesh, 3)
        stem.at = A.mul(lean, stem.at)
        parts[#parts + 1] = stem
        parts[#parts + 1] = { id = 4, ramp = R.flesh, at = A.mul(lean, ell(x, h * 0.72, z, 1.5 + r * 0.12, 0.45, 1.5 + r * 0.12)) } -- the ring
        parts[#parts + 1] = { id = 10 + k, ramp = R.honey, at = A.mul(lean, ell(x, h + r * 0.25, z, r * 1.1, r * 0.32, r * 1.1)),
            print = function(ux, uy, uz, lev)
                if uy > 0.85 then return IDX.n end -- the dark boss in the middle
                if lev >= 2 and spotted(0.96, IDX.u)(ux, uy, uz, lev) then return IDX.u end
                if uy < -0.2 then return IDX.w end
            end }
        if b == 2 then
            local fall = ((idle + k) % 4) / 4
            parts[#parts + 1] = { id = 40 + k, ramp = R.amber, at = A.mul(lean, ell(x + r * 0.7, h - fall * h * 0.6, z, 0.6, 0.9, 0.6)) }
        end
    end
    return parts
end

--- the six proposed in DESIGN.md, modelled ahead of their rules ----------------------

-- Fly Agaric: the classic toadstool, a red dome of white warts on a ringed
-- white stalk with a bulb at its foot. The cap sways; firing, it tips up at the
-- flier and flicks a wart off. Fly Bane flattens it wider and darker, Muscaria
-- raises a little one beside it in a haze; Muscimol turns it gold with glowing
-- warts, Ibotenic curls the rim up into a cup.
local function toadstool(parts, x, z, s, tip, capRamp, wart, cup, id)
    parts[#parts + 1] = { id = id, ramp = R.flesh, at = ell(x, 1.5 * s, z, 2.4 * s, 1.8 * s, 2.4 * s) }
    parts[#parts + 1] = seg(x, 1.5 * s, z, x, 9 * s, z, 1.3 * s, R.flesh, id)
    parts[#parts + 1] = { id = id + 1, ramp = R.flesh, at = ell(x, 7 * s, z, 2.3 * s, 0.5 * s, 2.3 * s) }
    local flat = cup and 0.45 or 1
    local lean = A.mul(A.move(x, 0, z), A.rotZ(tip), A.move(-x, 0, -z))
    parts[#parts + 1] = { id = id + 2, ramp = capRamp, at = A.mul(lean, ell(x, 10 * s, z, 5.2 * s, 3 * s * flat, 5.2 * s)),
        print = function(ux, uy, uz, lev)
            if uy < -0.35 then return abs(sin(atan2(uz, ux) * 14)) < 0.4 and IDX.t or IDX.w end -- the gills
            if uy > -0.1 and spotted(0.975, wart)(ux, uy, uz, lev) then return wart end
        end }
    if cup then
        -- The rim turned up: a ring of lobes standing round the cap's edge.
        for k = 0, 9 do
            local a = k / 10 * TAU
            parts[#parts + 1] = { id = id + 3, ramp = capRamp,
                at = A.mul(lean, ell(x + cos(a) * 4.6 * s, 11.4 * s, z + sin(a) * 4.6 * s, 1.4 * s, 1.5 * s, 1.4 * s)) }
        end
    end
end

local function agaric(b, tier, idle, fire)
    local sway = 0.05 * breath(idle) - 0.12 * fire
    local capRamp, wart, big = ramp("w", "r", "r", "u"), IDX.w, 1
    if b == 1 then capRamp, big = ramp("r", "r", "n", "u"), tier == 1 and 1.12 or 1.05 end
    if b == 2 then capRamp, wart = ramp("w", "t", "t", "r"), (fire > 0 or idle % 2 == 0) and IDX.l or IDX.c end
    local parts = { { id = 1, ramp = R.crumb, at = ell(0, 0.8, 0, 3.6, 1.2, 3.6) } }
    toadstool(parts, 0, 0, big, sway, capRamp, wart, b == 2 and tier == 2, 2)
    if b == 1 then
        -- Fly Bane: the cap pressed out flat and wide.
        parts[5].at = A.mul(parts[5].at, A.scale(1.2, 0.7, 1.2))
    end
    if b == 1 and tier == 2 then
        toadstool(parts, 4.6, 2.4, 0.55, -sway, capRamp, wart, false, 10)
        for k = 0, 3 do
            local a = k * 1.7 + idle * 0.4
            parts[#parts + 1] = { id = 20 + k, ramp = ramp("w", "s", "s", "k"),
                at = ell(cos(a) * 5, 13 + (k % 2) * 2, sin(a) * 5, 1.4, 0.9, 1.4) }
        end
    end
    if fire > 0 then
        parts[#parts + 1] = { id = 30, ramp = R.flesh, at = ell(3 + fire * 2, 14 + fire * 2, -1, 0.9, 0.7, 0.9) }
    end
    return parts
end

-- Earthstar: a brown papery ball with a mouth on top, sat on a star of split
-- arms. The arms feel the ground; firing, they press flat, the ball drops and
-- puffs, and a ring of dust runs out. Deep Listener grows more, longer arms
-- curled into the soil and, at Seismic, cracks out from their tips; Puff Quake
-- is heavier, and Cave-in stands up on its arm tips, the arched earthstar.
local function earthstar(b, tier, idle, fire)
    local arms, reach, ball, thick = 7, 6.5, 3, 1
    if b == 1 then arms, reach = tier == 1 and 9 or 10, tier == 1 and 8 or 8.6 end
    if b == 2 then ball, thick = 3.7, 1.3 end
    local arched = b == 2 and tier == 2
    local press = fire / 2
    local flex = 0.5 * breath(idle) * (1 - press)
    local by = (arched and 7.5 or 3.2) - press * 1.2
    local parts = {}
    for k = 0, arms - 1 do
        local a = k / arms * TAU + 0.2
        local c, s = cos(a), sin(a)
        local p
        if arched then
            p = seg(c * 2, by - 2, s * 2, c * (reach - 1), 1 + flex, s * (reach - 1), 0.5 * thick, R.shelf, 2, 1.3 * thick)
            parts[#parts + 1] = seg(c * (reach - 1), 1 + flex, s * (reach - 1), c * reach, 0.1, s * reach, 0.5, R.shelf, 2, 0.9)
        else
            local tip = (b == 1 and -0.3 or 0.9) + flex
            p = seg(c * 1.6, 1.2, s * 1.6, c * reach, tip, s * reach, 0.5 * thick, R.shelf, 2, 1.4 * thick)
        end
        p.print = function(ux, uy) if uy > 0.2 then return ux > 0.7 and IDX.n or IDX.w end end
        parts[#parts + 1] = p
        if b == 1 and tier == 2 then
            parts[#parts + 1] = seg(c * reach, 0.05, s * reach, c * (reach + 3.5), 0.05, s * (reach + 3.5) + (k % 2), 0.2, R.ink, 3, 0.3)
        end
    end
    parts[#parts + 1] = { id = 4, ramp = R.earth, at = ell(0, by + ball * 0.6, 0, ball, ball * 0.85 * (1 - 0.15 * press), ball),
        print = function(ux, uy)
            if uy > 0.88 then return IDX.o end -- the mouth
            if uy > 0.74 then return IDX.u end
            if abs(sin(ux * 9) * sin(uy * 7)) > 0.85 then return IDX.n end -- papery creases
        end }
    if fire > 0 then
        for k = 0, fire do
            parts[#parts + 1] = { id = 5, ramp = R.smoke, at = ell(0, by + ball * 1.7 + k * 1.8, 0, 1.3 + k * 0.4, 1, 1.3 + k * 0.4) }
        end
        for k = 0, 7 do
            local a = k / 8 * TAU
            parts[#parts + 1] = { id = 6, ramp = R.crumb, at = ell(cos(a) * (reach + fire * 2), 0.5, sin(a) * (reach + fire * 2), 1, 0.6, 1) }
        end
    end
    return parts
end

-- Oyster Mushroom: grey-blue fans growing sideways off a stump, gills under.
-- Their edges ripple; firing, a fan flicks and a sticky drop leaves the gills.
-- Nematode Trap hangs beaded threads off them, Lasso long loops to the ground;
-- Corrode turns them gold and dripping, Dissolve stains the ground under it.
local OYSTER = { { 0.3, 9, 1 }, { 2.5, 6.5, 0.9 }, { 4.6, 10.5, 0.8 }, { -1.6, 5, 0.75 } }
local function oyster(b, tier, idle, fire)
    local fan = b == 2 and R.amber or ramp("w", "s", "k", "u")
    local parts = { { id = 1, ramp = R.bark, at = ell(0, 4, 0, 2.6, 4.6, 2.4),
        print = function(ux, uy, uz) if abs(sin(atan2(uz, ux) * 6 + uy * 2)) < 0.12 then return IDX.o end end } }
    for k, f in ipairs(OYSTER) do
        local a, y, s = f[1], f[2], f[3] * (1 + 0.04 * sin(idle / 4 * TAU + k))
        local flick = (fire > 0 and k == 1) and 0.35 or 0
        local x, z = cos(a) * 3.4, sin(a) * 3.4
        parts[#parts + 1] = { id = 2 + k, ramp = fan,
            at = A.mul(A.move(x, y, z), A.rotY(-a), A.rotZ(-0.25 + flick), A.scale(4.6 * s, 1.2 * s, 3.8 * s)),
            print = function(ux, uy, uz)
                if uy < -0.15 then return abs(sin(atan2(uz, ux + 1) * 22)) < 0.35 and IDX.k or IDX.s end -- the gills
                if ux * ux + uz * uz > 0.82 and uy > 0 then return IDX.w end
            end }
        local ex, ez = x + cos(a) * 3.4 * s, z + sin(a) * 3.4 * s
        if b == 1 then
            -- Nematode Trap: beaded threads under the fan; Lasso drops them to the ground in loops.
            for t = -1, 1 do
                local tx, tz = ex - sin(a) * t * 1.6, ez + cos(a) * t * 1.6
                local low = tier == 1 and y - 3.5 or 0.4
                parts[#parts + 1] = seg(tx, y - 0.6, tz, tx, low, tz, 0.18, R.glue, 10, 0.18)
                parts[#parts + 1] = { id = 11, ramp = R.glue, at = ell(tx, low, tz, 0.5, 0.5, 0.5) }
                if tier == 2 then
                    parts[#parts + 1] = seg(tx, low, tz, (tx + x) / 2, low + 0.2, (tz + z) / 2, 0.18, R.glue, 10, 0.18)
                end
            end
        elseif b == 2 then
            local fall = ((idle + k) % 4) / 4
            parts[#parts + 1] = { id = 12, ramp = R.amber, at = ell(ex, y - 1 - fall * (y - 1.5), ez, 0.45, 0.75, 0.45) }
        end
    end
    if b == 2 and tier == 2 then
        parts[#parts + 1] = { id = 13, ramp = ramp("t", "t", "t", "n"), at = ell(2.5, 0.05, 1.5, 5.5, 0.2, 4.5) }
    end
    if fire > 0 then
        parts[#parts + 1] = { id = 14, ramp = R.glue, at = ell(7.5, 7, 0.5, 0.8, 0.8, 0.8) }
    end
    return parts
end

-- Bleeding Tooth: a lumpy white cap beaded with blood-red drops, a fringe of
-- short teeth under it. The drops swell and shrink; firing, one bursts and runs.
-- Clotting darkens them into knobs and, at Scab, crusts half the cap over;
-- Hemotoxin pushes the teeth out past the rim, Thorn Sap keeps the drops running.
local DROPS = { { 0.3, 0.55 }, { 2.1, 0.7 }, { 3.6, 0.45 }, { 4.6, 0.75 }, { 5.6, 0.5 }, { 1.2, 0.25 } }
local function tooth(b, tier, idle, fire)
    local drop = ramp("w", "r", "r", "u")
    if b == 1 then drop = R.dung end
    if b == 2 and tier == 2 then drop = ramp("w", "w", "r", "r") end
    local swell = 1 + 0.15 * breath(idle)
    local teeth = (b == 2) and (tier == 1 and 2.2 or 3) or 1.4
    local parts = { { id = 1, ramp = R.crumb, at = ell(0, 1, 0, 3, 1.4, 3) },
        seg(0, 1, 0, 0, 4, 0, 1.6, R.flesh, 2) }
    parts[#parts + 1] = { id = 3, ramp = R.flesh, at = ell(0, 5.2, 0, 5.6, 2.4, 5.2),
        print = function(ux, uy, uz)
            if b == 1 and tier == 2 and ux > 0.05 and uy > -0.2 then
                return abs(sin(ux * 13) * sin(uz * 11)) > 0.5 and IDX.u or IDX.n -- the scab
            end
            if uy > 0.1 and abs(sin(ux * 7 + uz * 5) * sin(uz * 6 - ux * 3)) > 0.8 then return IDX.t end -- lumps
        end }
    for k = 0, 15 do
        local a = k / 16 * TAU
        local x, z = cos(a) * 4.4, sin(a) * 4
        parts[#parts + 1] = seg(x, 4.4, z, x * (1 + 0.04 * teeth), 4.4 - teeth, z * (1 + 0.04 * teeth), 0.45, R.flesh, 4)
    end
    for k, d in ipairs(DROPS) do
        if not (fire > 0 and k == 1) and not (b == 1 and tier == 2 and cos(d[1]) > 0) then
            local a, r = d[1], d[2]
            local x, z = cos(a) * r * 5, sin(a) * r * 4.6
            local y = 5.2 + 2.4 * sqrt(math.max(0, 1 - r * r)) + 0.3
            local s = (b == 1 and 1.1 or 0.9 + (k % 2) * 0.3) * (b == 1 and 1 or swell)
            parts[#parts + 1] = { id = 10 + k, ramp = drop, at = ell(x, y, z, s, s * 0.8, s) }
        end
    end
    if fire > 0 or (b == 2 and tier == 2) then
        -- A drop run down the side.
        local a = fire > 0 and 0.3 or 2.1 + idle
        local x, z = cos(a) * 5.3, sin(a) * 4.9
        parts[#parts + 1] = seg(x * 0.8, 7, z * 0.8, x, 4.2 - fire * 0.5, z, 0.35, drop, 20)
    end
    return parts
end

-- Truffle: mostly hidden, a low mound of soil cracked across, the top of a dark
-- knobbly truffle showing through, and the ridges of its buried links running
-- off. At a wave's end the crack opens on a gold glint. Aged heaps the mound up
-- and Black Diamond puts a sheen on the knobs; Root Run breaks pale rootlets
-- out along the ridges and Taproot swells them, flow pulsing through.
local function truffle(b, tier, idle, fire)
    local big = (b == 1) and (tier == 1 and 1.2 or 1.3) or 1
    local rise = 1 + 0.04 * breath(idle)
    local knob = ramp("n", "u", "u", "o")
    local parts = {}
    local ridge = (b == 2 and tier == 2) and 1.5 or 1
    for k = 0, 2 do
        local a = k * 2.3 + 0.6
        local c, s = cos(a), sin(a)
        local p = seg(c * 4, 0, s * 4, c * 11, 0, s * 11, 0.7 * ridge, RAMP.soil, 2, 1.8 * ridge)
        if b == 2 and tier == 2 then
            p.print = function(ux, uy) if uy > 0.3 and abs((ux * 2 + idle * 0.5) % 1 - 0.5) < 0.15 then return IDX.c end end
        end
        parts[#parts + 1] = p
        if b == 2 then
            for r = 0, 2 do
                local t = 6 + r * 2
                local x, z = c * t, s * t
                parts[#parts + 1] = seg(x, 0.6, z, x - s * 1.4, 1.5, z + c * 1.4, 0.25, R.flesh, 3)
            end
        end
    end
    local open = fire / 1
    parts[#parts + 1] = { id = 4, ramp = RAMP.soil, at = ell(0, 0.4, 0, 6.2 * big, 2.6 * big * rise, 5.6 * big),
        print = function(ux, uy, uz)
            local d = abs(ux * 0.4 - uz * 0.9)
            if uy > 0.3 and d < 0.12 + open * 0.15 then return IDX.o end -- the crack
            if abs(sin(ux * 11 + uz * 7)) > 0.94 then return IDX.n end -- grit
        end }
    parts[#parts + 1] = { id = 5, ramp = knob, at = ell(0.4, 2.4 * big + open * 0.8, 0.3, 3.2 * big, 1.9 * big, 2.8 * big),
        print = function(ux, uy, uz)
            for _, d in ipairs({ { 0.5, 0.8, 0.2 }, { -0.4, 0.8, 0.4 }, { 0, 0.9, -0.5 }, { 0.7, 0.4, -0.5 }, { -0.7, 0.5, -0.3 } }) do
                if ux * d[1] + uy * d[2] + uz * d[3] > 0.82 then
                    return (b == 1 and tier == 2) and IDX.w or IDX.n -- a knob, sheened
                end
            end
        end }
    if fire > 0 then
        parts[#parts + 1] = { id = 6, ramp = ramp("w", "w", "t", "t"), at = ell(0.4, 5.5 * big, 0.3, 1, 1.2, 1) }
    end
    return parts
end

-- Turkey Tail: thin flat brackets stacked up a stub, banded brown, cream and
-- rust like a fanned tail. The bands roll out from the base in a slow beat.
-- Mycelial Pump thickens them and rings them teal like the Relay, Capillary
-- runs teal threads down into the soil; Versicolor stacks more and wider, and
-- Rainbow colours the bands right through.
local BANDS = { IDX.n, IDX.w, IDX.r }
local RAINBOW = { IDX.r, IDX.t, IDX.g, IDX.c, IDX.m }
local function turkey(b, tier, idle)
    local n, big, th = 5, 1, 0.7
    if b == 1 then th = 1.1 end
    if b == 2 then n, big = tier == 1 and 6 or 7, tier == 1 and 1.12 or 1.2 end
    local bands = (b == 2 and tier == 2) and RAINBOW or BANDS
    local teal = b == 1
    local parts = { { id = 1, ramp = R.bark, at = ell(0, 4, 0, 1.8, 5, 1.8) } }
    for k = 1, n do
        local a = k * 2.4
        local y = 1.6 + k * 1.7
        local s = (1.1 - k * 0.06) * big
        local x, z = cos(a) * 1.8, sin(a) * 1.8
        parts[#parts + 1] = { id = 2 + k, ramp = R.shelf,
            at = A.mul(A.move(x, y, z), A.rotY(-a), A.rotZ(-0.12), A.move(2.4 * s, 0, 0), A.scale(5 * s, th * s, 4.4 * s)),
            print = function(ux, uy, uz)
                if uy < 0.1 then return end
                local r = sqrt((ux + 0.5) ^ 2 + uz * uz)
                if r > 1.35 then return IDX.w end
                local band = floor(r * 6 - idle * 0.5) % #bands + 1
                if teal and band == 1 then return IDX.c end
                return bands[band]
            end }
        if b == 1 and tier == 2 and k % 2 == 1 then
            parts[#parts + 1] = seg(x + cos(a) * 4 * s, y, z + sin(a) * 4 * s, x + cos(a) * 5 * s, 0.1, z + sin(a) * 5 * s, 0.25, RAMP.teal, 20)
        end
    end
    return parts
end

local TOWER = { puffer = puffer, needle = needle, mane = mane, relay = relay, mat = mat, inky = inky,
    shelf = shelf, mortar = mortar, cordyceps = cordyceps, stink = stinkhorn, lamp = lamp, giant = giant,
    agaric = agaric, earthstar = earthstar, oyster = oyster, tooth = tooth, truffle = truffle, turkey = turkey }

-- How many steps each animation number has, per species: some keep still.
local STEPS = {
    puffer = { idle = 4, fire = 3 }, needle = { idle = 4, fire = 3 }, mane = { idle = 4, fire = 2 },
    relay = { idle = 4, fire = 1 }, mat = { idle = 3, fire = 1 }, inky = { idle = 4, fire = 2 },
    shelf = { idle = 1, fire = 1 }, mortar = { idle = 4, fire = 3 }, cordyceps = { idle = 4, fire = 3 },
    stink = { idle = 4, fire = 3 }, lamp = { idle = 4, fire = 2 }, giant = { idle = 4, fire = 3 },
    agaric = { idle = 4, fire = 3 }, earthstar = { idle = 4, fire = 3 }, oyster = { idle = 4, fire = 2 },
    tooth = { idle = 4, fire = 2 }, truffle = { idle = 4, fire = 2 }, turkey = { idle = 4, fire = 1 },
}

-- A fruiting body by look. `idle`, `fire` and `grow` are 0..1; each is cut to
-- the species' few steps before the picture is looked up.
function M.tower(kind, branch, tier, idle, fire, grow)
    local st = STEPS[kind]
    local i = floor((idle or 0) * st.idle) % st.idle
    local f = floor((fire or 0) * (st.fire - 1) + 0.5)
    local g = grow and floor(grow * 3) or 3
    if g < 3 then i, f = 0, 0 end
    tier = branch and tier or 0
    local key = kind .. (branch or 0) .. tier .. ":" .. i .. f .. g
    return kept(key, function()
        local parts = TOWER[kind](branch, tier, i, f)
        if g < 3 then
            -- Coming up out of the ground: small and a little squat at first.
            local s = 0.4 + g * 0.2
            place(parts, A.scale(s * 1.1, s * 0.9, s * 1.1))
        end
        return parts
    end)
end

-- Every look of every species, for the model sheet (love . --sheet).
function M.sheetRows()
    local rows = {}
    for _, kind in ipairs({ "puffer", "needle", "mat", "mane", "relay", "inky", "shelf", "mortar", "cordyceps",
        "stink", "lamp", "giant", "agaric", "earthstar", "oyster", "tooth", "truffle", "turkey" }) do
        local row = { kind }
        row[#row + 1] = M.tower(kind)
        for b = 1, 2 do
            for t = 1, 2 do row[#row + 1] = M.tower(kind, b, t) end
        end
        row[#row + 1] = M.tower(kind, nil, 0, 0, 1)
        row[#row + 1] = M.tower(kind, nil, 0, 0, 0, 0.4)
        rows[#rows + 1] = row
    end
    return rows
end

return M
