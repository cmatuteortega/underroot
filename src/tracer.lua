-- The tracer: Survive School's 3D method (3dmethod.md, src/solid.lua there) by
-- way of the frog prototype (sekiroclone's src/tracer.lua), turned to look at
-- the world from a corner.
--
-- The frog's camera looked straight up the page from 34 degrees. A tower
-- defense wants the whole board at once and wants to read it as a board, so
-- here the camera is isometric: turned 45 degrees about the vertical and tilted
-- 30 degrees down, which lays a square of ground down as a diamond twice as wide
-- as it is tall -- the pixel artist's 2:1. It stays orthographic, and that is
-- still what everything rests on: with no perspective a picture of a thing is
-- the same picture wherever it stands, so the board is painted once and every
-- mushroom and ant is painted once per pose and kept.
--
-- Room space: x and z along the ground (x runs down-right on screen, z down-left),
-- y up. The viewer is off towards +x +z, above.
--
-- Every pixel is traced once at its centre and its colour is *chosen* off a ramp
-- of palette keys, never blended. Then the two passes that make it read as drawn
-- rather than rendered: creases (a step down to the ramp's shadow where
-- neighbouring normals of one material disagree) and ink (round the silhouette,
-- and along any step in depth onto another part).

local ffi = require "ffi"
local Palette = require "src.palette"

local sqrt, cos, sin, max, min, floor, ceil = math.sqrt, math.cos, math.sin, math.max, math.min, math.floor, math.ceil

local T = {}

local ELEV = math.rad(30)
local CE, SE = cos(ELEV), sin(ELEV)
local C45 = sqrt(0.5)
-- Model units to a pixel. A tile of ground is 16 units: thirteen pixels along
-- an edge, a worker ant about nine pixels nose to sting.
local UNIT = 0.85
T.UNIT = UNIT

-- The camera's three axes in the room: screen right, screen up, towards you.
local RX, RY, RZ = C45, 0, -C45
local UX, UY, UZ = -C45 * SE, CE, -C45 * SE
local NX, NY, NZ = C45 * CE, SE, C45 * CE
-- Every ray of every picture goes the same way: away from you.
local DX, DY, DZ = -NX, -NY, -NZ
T.DX, T.DY, T.DZ = DX, DY, DZ

-- The lamp lives in the room, not on the models: up, to the left of the screen
-- and a little towards you, so every flat top is lit, every face towards the
-- bottom-left is in the middle of its ramp and every face to the bottom-right is
-- in shade -- the three tones an isometric block is read by.
local LX, LY, LZ
do
    local a, b, e = 0.5, 0.75, 0.45
    LX, LY, LZ = -a * RX + e * NX, b + e * NY, -a * RZ + e * NZ
    local n = sqrt(LX * LX + LY * LY + LZ * LZ)
    LX, LY, LZ = LX / n, LY / n, LZ / n
end
local HX, HY, HZ = LX + NX, LY + NY, LZ + NZ
do
    local n = sqrt(HX * HX + HY * HY + HZ * HZ)
    HX, HY, HZ = HX / n, HY / n, HZ / n
end

local CREASE = 0.55

--- palette keys as small numbers ------------------------------------------------

-- 0 is "nothing here". Buffers hold these rather than strings so they can live in
-- ffi arrays the size of the world.
T.KEYS, T.IDX, T.RGB = {}, {}, {}
for i, row in ipairs(Palette.list) do
    T.KEYS[i], T.IDX[row[1]], T.RGB[i] = row[1], i, Palette.key[row[1]]
end
local IDX = T.IDX

-- Remaps a picture is laid down through: one step darker (a starved mushroom,
-- a shadow), two (dormant), and every lit key to cream (the frame a thing is hit).
T.DARKER, T.DARKER2, T.FLASH, T.SAME = {}, {}, {}, {}
for i, k in ipairs(T.KEYS) do
    T.SAME[i] = i
    T.DARKER[i] = IDX[Palette.darker[k]]
end
for i = 1, #T.KEYS do T.DARKER2[i] = T.DARKER[T.DARKER[i]] end
for i, k in ipairs(T.KEYS) do T.FLASH[i] = (k == "o" or k == "u") and i or IDX.w end

--- projection ------------------------------------------------------------------

-- Room point to screen pixel (i right, j down) and depth (bigger is nearer).
function T.project(x, y, z)
    return (x * RX + z * RZ) / UNIT,
        -(x * UX + y * UY + z * UZ) / UNIT,
        x * NX + y * NY + z * NZ
end

-- Where the ray through screen point (i, j) starts, on the plane `back` deep.
function T.origin(i, j, back)
    local a, b = i * UNIT, -j * UNIT
    return a * RX + b * UX + back * NX, a * RY + b * UY + back * NY, a * RZ + b * UZ + back * NZ
end

--- light and ramps -------------------------------------------------------------

-- A ramp is glint, lit, middle, shadow (as key indices). The table is the
-- one in 3dmethod.md, bounce-light row included: without it the underside is one
-- dark shape and reads as a hole.
local function ramp(g, l, m, s) return { IDX[g], IDX[l], IDX[m], IDX[s] } end
T.ramp = ramp
T.RAMP = {
    soil = ramp("w", "t", "n", "u"),
    stone = ramp("w", "s", "k", "u"),
    moss = ramp("g", "m", "d", "u"),
    leaf = ramp("t", "m", "d", "u"),
    sprout = ramp("w", "g", "m", "d"),
    flesh = ramp("w", "w", "t", "n"),
    teal = ramp("w", "l", "c", "d"),
    ink = ramp("s", "k", "u", "o"),
    ant = ramp("t", "r", "n", "u"),
    bug = ramp("w", "s", "k", "o"),
    mite = ramp("w", "r", "n", "u"),
    salt = ramp("w", "w", "s", "k"),
    crumb = ramp("w", "t", "n", "u"),
}

function T.diffuse(nx, ny, nz)
    return nx * LX + ny * LY + nz * LZ
end

-- Answers key index and the ramp level it came off (1 glint .. 4 shadow).
function T.shade(r, nx, ny, nz)
    local d = nx * LX + ny * LY + nz * LZ
    local h = nx * HX + ny * HY + nz * HZ
    if h > 0 and h ^ 40 > 0.6 then return r[1], 1 end
    if d > 0.78 then return r[2], 2 end
    if d > 0.2 then return r[3], 3 end
    if ny < 0 and d > 0.02 then return r[3], 3 end
    return r[4], 4
end

--- buffers ---------------------------------------------------------------------

-- One pixel's worth of everything the two passes need. `lev` 0 marks a printed
-- pixel (a vein, a ring, a joint between slabs) that a crease must not touch.
function T.buffer(w, h)
    local n = w * h
    return {
        w = w, h = h,
        key = ffi.new("uint8_t[?]", n),
        lev = ffi.new("uint8_t[?]", n),
        shd = ffi.new("uint8_t[?]", n), -- the ramp's shadow key, for creases
        part = ffi.new("int16_t[?]", n),
        mat = ffi.new("int16_t[?]", n),
        dep = ffi.new("float[?]", n),
        dif = ffi.new("float[?]", n),
        nx = ffi.new("float[?]", n),
        ny = ffi.new("float[?]", n),
        nz = ffi.new("float[?]", n),
    }
end

-- Creases, then ink, both decided off the untouched picture.
function T.finish(b, edge)
    local w, h = b.w, b.h
    local key, lev, shd, part, mat, dep, dif = b.key, b.lev, b.shd, b.part, b.mat, b.dep, b.dif
    local nx, ny, nz = b.nx, b.ny, b.nz
    local n = w * h
    local out = ffi.new("uint8_t[?]", n)
    ffi.copy(out, key, n)

    local function crease(p, q)
        if key[q] == 0 or mat[p] ~= mat[q] then return end
        if nx[p] * nx[q] + ny[p] * ny[q] + nz[p] * nz[q] >= CREASE then return end
        local r = dif[p] < dif[q] and p or q
        if lev[r] == 2 or lev[r] == 3 then out[r] = shd[r] end
    end
    for j = 0, h - 1 do
        for i = 0, w - 1 do
            local p = j * w + i
            if key[p] ~= 0 then
                if i < w - 1 then crease(p, p + 1) end
                if j < h - 1 then crease(p, p + w) end
            end
        end
    end

    local INK = IDX.o
    local function inked(p, q)
        if key[q] == 0 then return true end
        return part[q] ~= part[p] and dep[p] - dep[q] > edge
    end
    for j = 0, h - 1 do
        for i = 0, w - 1 do
            local p = j * w + i
            if key[p] ~= 0 then
                local rim = i == 0 or i == w - 1 or j == 0 or j == h - 1
                if (rim and not b.open) or (not rim and (inked(p, p - 1) or inked(p, p + 1)
                    or inked(p, p - w) or inked(p, p + w))) then
                    out[p] = INK
                end
            end
        end
    end
    b.key = out
end

--- affine maps -----------------------------------------------------------------

-- Twelve numbers, row-major: the 3x3 and then the shift, per row.
local A = {}
T.Affine = A

function A.id() return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 } end
function A.move(x, y, z) return { 1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z } end
function A.scale(x, y, z) return { x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0 } end
function A.rotY(a)
    local c, s = cos(a), sin(a)
    return { c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0 }
end
function A.rotZ(a)
    local c, s = cos(a), sin(a)
    return { c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0 }
end
function A.rotX(a)
    local c, s = cos(a), sin(a)
    return { 1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0 }
end

function A.mul(a, b, ...)
    local r = {}
    for row = 0, 2 do
        local a1, a2, a3, a4 = a[row * 4 + 1], a[row * 4 + 2], a[row * 4 + 3], a[row * 4 + 4]
        for col = 1, 4 do
            r[row * 4 + col] = a1 * b[col] + a2 * b[4 + col] + a3 * b[8 + col]
        end
        r[row * 4 + 4] = r[row * 4 + 4] + a4
    end
    if ... then return A.mul(r, ...) end
    return r
end

function A.inv(m)
    local a, b, c, d, e, f, g, h, i = m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11]
    local A1, B1, C1 = e * i - f * h, -(d * i - f * g), d * h - e * g
    local det = a * A1 + b * B1 + c * C1
    local r = {
        A1 / det, -(b * i - c * h) / det, (b * f - c * e) / det, 0,
        B1 / det, (a * i - c * g) / det, -(a * f - c * d) / det, 0,
        C1 / det, -(a * h - b * g) / det, (a * e - b * d) / det, 0,
    }
    for row = 0, 2 do
        r[row * 4 + 4] = -(r[row * 4 + 1] * m[4] + r[row * 4 + 2] * m[8] + r[row * 4 + 3] * m[12])
    end
    return r
end

-- A unit ball scaled, then turned by whatever rotations follow, then moved.
function T.ell(cx, cy, cz, rx, ry, rz, ...)
    local m = A.scale(rx, ry, rz)
    for _, r in ipairs({ ... }) do m = A.mul(r, m) end
    return A.mul(A.move(cx, cy, cz), m)
end

--- pictures of bodies made of ellipsoids ---------------------------------------

-- A body is a list of parts, each an ellipsoid: a unit ball put through `at`, a
-- map into the room relative to the body's pivot (the ground under it). A part
-- answers its `ramp`, an optional `print` (a function of the point on its own
-- unit ball and the ramp level, answering a key index to paint, a ramp to use
-- instead, or nothing) and its `id` (what the ink pass tells parts apart by).
--
-- The ray is taken back through each part's inverse into the ball's own space,
-- where the question is a quadratic; the normal comes back out through the
-- transpose of the same inverse. Each part only asks the pixels inside the
-- circle its bounding sphere lands in.
local BACK = 80

function T.paint(parts, edge)
    local i0, j0, i1, j1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(parts) do
        local m = p.at
        p.inv = A.inv(m)
        local r = 0
        for col = 1, 3 do
            r = max(r, sqrt(m[col] ^ 2 + m[4 + col] ^ 2 + m[8 + col] ^ 2))
        end
        local ci, cj = T.project(m[4], m[8], m[12])
        p.ci, p.cj, p.cr = ci, cj, r / UNIT + 1
        i0, i1 = min(i0, ci - p.cr), max(i1, ci + p.cr)
        j0, j1 = min(j0, cj - p.cr), max(j1, cj + p.cr)
    end
    i0, j0 = floor(i0) - 1, floor(j0) - 1
    i1, j1 = ceil(i1) + 1, ceil(j1) + 1
    local w, h = i1 - i0 + 1, j1 - j0 + 1
    local b = T.buffer(w, h)
    local best = ffi.new("float[?]", w * h)
    for n = 0, w * h - 1 do best[n] = 1e9 end

    for _, p in ipairs(parts) do
        local v = p.inv
        -- The ray's way, in the ball's space; the same for every pixel.
        local bx = v[1] * DX + v[2] * DY + v[3] * DZ
        local by = v[5] * DX + v[6] * DY + v[7] * DZ
        local bz = v[9] * DX + v[10] * DY + v[11] * DZ
        local qa = bx * bx + by * by + bz * bz
        local pi0, pi1 = floor(p.ci - p.cr) - i0, ceil(p.ci + p.cr) - i0
        local pj0, pj1 = floor(p.cj - p.cr) - j0, ceil(p.cj + p.cr) - j0
        local rr = p.cr * p.cr
        for pj = max(0, pj0), min(h - 1, pj1) do
            for pi = max(0, pi0), min(w - 1, pi1) do
                local si, sj = i0 + pi + 0.5, j0 + pj + 0.5
                if (si - p.ci) ^ 2 + (sj - p.cj) ^ 2 <= rr then
                    local ox, oy, oz = T.origin(si, sj, BACK)
                    local ax = v[1] * ox + v[2] * oy + v[3] * oz + v[4]
                    local ay = v[5] * ox + v[6] * oy + v[7] * oz + v[8]
                    local az = v[9] * ox + v[10] * oy + v[11] * oz + v[12]
                    local qb = ax * bx + ay * by + az * bz
                    local qc = ax * ax + ay * ay + az * az - 1
                    local disc = qb * qb - qa * qc
                    if disc >= 0 then
                        local t = (-qb - sqrt(disc)) / qa
                        local n = pj * w + pi
                        if t < best[n] then
                            best[n] = t
                            local ux, uy, uz = ax + t * bx, ay + t * by, az + t * bz
                            -- Normal: transpose of the inverse's linear part.
                            local nx = v[1] * ux + v[5] * uy + v[9] * uz
                            local ny = v[2] * ux + v[6] * uy + v[10] * uz
                            local nz = v[3] * ux + v[7] * uy + v[11] * uz
                            local l = sqrt(nx * nx + ny * ny + nz * nz)
                            nx, ny, nz = nx / l, ny / l, nz / l
                            local r = p.ramp
                            local k, lev = T.shade(r, nx, ny, nz)
                            local printed = p.print and p.print(ux, uy, uz, lev)
                            if type(printed) == "table" then
                                r = printed
                                k, lev = T.shade(r, nx, ny, nz)
                            elseif printed then
                                k, lev = printed, 0
                            end
                            b.key[n], b.lev[n], b.shd[n] = k, lev, r[4]
                            b.part[n], b.mat[n] = p.id, p.matId or p.id
                            b.dep[n] = BACK - t
                            b.dif[n] = T.diffuse(nx, ny, nz)
                            b.nx[n], b.ny[n], b.nz[n] = nx, ny, nz
                        end
                    end
                end
            end
        end
    end
    T.finish(b, edge or 2)
    -- `oi, oj`: the pixel of the picture the pivot falls on.
    return { w = w, h = h, oi = -i0, oj = -j0, key = b.key, dep = b.dep }
end

return T
