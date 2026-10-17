-- What every model is built with (see src/models.lua): the cache of painted
-- pictures, laying parts out, legs and stalks between two points, spots, and
-- the ramps the new species and bugs are painted in.

local T = require "src.tracer"
local A = T.Affine

local sin, cos, abs, floor, sqrt = math.sin, math.cos, math.abs, math.floor, math.sqrt
local RAMP = T.RAMP
local TAU = 2 * math.pi
local ramp = T.ramp

local M = {}

local cache = {}
-- How much bigger than on the board the pictures asked for now are painted:
-- 1 but inside M.scaled, which the encyclopedia paints its big models with.
-- Traced again at the size, not blown up, so they stay one pixel a pixel.
local big = 1
local function kept(key, build)
    if big ~= 1 then key = key .. "@" .. big end
    local p = cache[key]
    if not p then
        local parts = build()
        if big ~= 1 then
            local m = A.scale(big, big, big)
            for _, part in ipairs(parts) do part.at = A.mul(m, part.at) end
        end
        p = T.paint(parts, 2)
        cache[key] = p
    end
    return p
end

-- `f(...)`'s picture painted `s` times the size.
function M.scaled(s, f, ...)
    local was = big
    big = s
    local p = f(...)
    big = was
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

M.kept, M.place, M.heading, M.step, M.join, M.seg, M.limb, M.spotted = kept, place, heading, step, join, seg, limb, spotted

return M
