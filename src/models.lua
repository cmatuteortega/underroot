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
--
-- Fruiting bodies are one function per species from a *look* -- branch, tier,
-- and three small animation numbers: `idle` (0..3, a slow breath or sway),
-- `fire` (0..2, the kick of a shot) and `grow` (0..3, coming up out of the
-- ground when it is grown or upgraded). Each tier adds parts you can see:
-- a toxic puffball goes green and grows satellites, an enoki clump gets taller
-- and sharper, a shelf grows thorns.
--
-- The bosses are the big bugs, built the same way at three times the size, so
-- the method's creases and ink pick out their plates and joints. Their legs are
-- jointed: `seg` lays an ellipsoid between two points, so a leg is a hip, a
-- knee and a foot, and a walk cycle is where the feet are.

local T = require "src.tracer"
local A = T.Affine

local sin, cos, atan2, abs, floor, sqrt = math.sin, math.cos, math.atan2, math.abs, math.floor, math.sqrt
local ell, RAMP, IDX = T.ell, T.RAMP, T.IDX
local TAU = 2 * math.pi
local ramp = T.ramp

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

local function join(into, list)
    for _, p in ipairs(list) do into[#into + 1] = p end
    return into
end

-- An ellipsoid laid between two points, `r` thick: a leg, a stalk, a jaw.
-- Its unit ball's x runs along it, so a print can tell the root from the tip.
local function seg(x0, y0, z0, x1, y1, z1, r, rmp, id, r2)
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local l = sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / l, dy / l, dz / l
    local ux, uy, uz = 0, 1, 0
    if abs(dy) > 0.9 then ux, uy, uz = 1, 0, 0 end
    local px, py, pz = dy * uz - dz * uy, dz * ux - dx * uz, dx * uy - dy * ux
    local pl = sqrt(px * px + py * py + pz * pz)
    px, py, pz = px / pl, py / pl, pz / pl
    local qx, qy, qz = py * dz - pz * dy, pz * dx - px * dz, px * dy - py * dx
    local h, s = l / 2, r2 or r
    return { id = id, ramp = rmp, at = {
        dx * h, qx * r, px * s, (x0 + x1) / 2,
        dy * h, qy * r, py * s, (y0 + y1) / 2,
        dz * h, qz * r, pz * s, (z0 + z1) / 2,
    } }
end

-- A jointed leg from a hip to a foot on the ground, the knee lifted `up` and
-- pushed `out` sideways.
local function limb(parts, hx, hy, hz, fx, fz, up, r, rmp, id)
    local kx, kz = (hx + fx) / 2, (hz + fz) / 2
    local ky = hy + up
    parts[#parts + 1] = seg(hx, hy, hz, kx, ky, kz, r * 1.2, rmp, id)
    parts[#parts + 1] = seg(kx, ky, kz, fx, 0.2, fz, r, rmp, id)
end

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

-- Ramps for the new species and the new bugs.
local R = {
    flesh = RAMP.flesh,
    crumb = RAMP.crumb,
    toxic = ramp("w", "m", "d", "u"),
    glowcap = ramp("w", "l", "c", "d"),
    amber = ramp("w", "t", "t", "n"),
    glue = ramp("w", "w", "t", "n"),
    cord = ramp("w", "t", "r", "u"),
    bark = ramp("t", "n", "u", "o"),
    shelf = ramp("w", "t", "n", "u"),
    inky = ramp("w", "w", "s", "k"),
    earth = ramp("t", "t", "n", "u"),
    smoke = ramp("s", "k", "u", "o"),
    moss = RAMP.moss,
    teal = RAMP.teal,
    ink = RAMP.ink,
    bubble = ramp("w", "r", "r", "u"),
    wing = ramp("w", "w", "s", "k"),
    shell = ramp("w", "n", "u", "o"),
    jaw = ramp("t", "n", "u", "o"),
    mandible = ramp("w", "r", "n", "o"),
    black = ramp("w", "k", "u", "o"),
    spider = ramp("t", "n", "u", "o"),
    slug = ramp("w", "t", "n", "u"),
    dung = ramp("t", "n", "u", "o"),
    gleba = ramp("m", "d", "u", "o"),
    honey = ramp("w", "t", "n", "u"),
    centi = ramp("t", "r", "n", "u"),
    wingtan = ramp("w", "t", "n", "u"),
    bombard = ramp("w", "t", "r", "u"),
    springtail = ramp("w", "s", "k", "u"),
    click = ramp("t", "n", "u", "o"),
    mole = ramp("t", "n", "n", "u"),
}
M.R = R

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

local TOWER = { puffer = puffer, needle = needle, mane = mane, relay = relay, mat = mat, inky = inky,
    shelf = shelf, mortar = mortar, cordyceps = cordyceps, stink = stinkhorn, lamp = lamp, giant = giant }

-- How many steps each animation number has, per species: some keep still.
local STEPS = {
    puffer = { idle = 4, fire = 3 }, needle = { idle = 4, fire = 3 }, mane = { idle = 4, fire = 2 },
    relay = { idle = 4, fire = 1 }, mat = { idle = 3, fire = 1 }, inky = { idle = 4, fire = 2 },
    shelf = { idle = 1, fire = 1 }, mortar = { idle = 4, fire = 3 }, cordyceps = { idle = 4, fire = 3 },
    stink = { idle = 4, fire = 3 }, lamp = { idle = 4, fire = 2 }, giant = { idle = 4, fire = 3 },
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
        local parts, top = nil, 3
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

-- Every look of every species, for the model sheet (love . --sheet).
function M.sheetRows()
    local rows = {}
    for _, kind in ipairs({ "puffer", "needle", "mat", "mane", "relay", "inky", "shelf", "mortar", "cordyceps",
        "stink", "lamp", "giant" }) do
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
