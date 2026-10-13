-- The board: everything that does not move, painted once.
--
-- The camera never turns and has no perspective, so a picture of the board is
-- the same picture whatever happens on it. It is traced once at load, a pixel at
-- a time, into one image -- and into a depth buffer the same size, which is what
-- lets an ant go behind a slab of the patio or a mushroom stand in front of one
-- without anything being traced again. The buffer also keeps where in the room
-- each pixel is, which is how a click lands on the ground and how a shadow is
-- laid on whatever is under the thing casting it.
--
-- The board is a diorama: a block of soil cut out of the patio, so its two near
-- sides show the strata. It is written as an ASCII map, one character per
-- 16-unit tile, in the spirit of Survive School's sprites: the map is the art.

local ffi = require "ffi"
local T = require "src.tracer"

local sqrt, max, min, abs, floor, ceil = math.sqrt, math.max, math.min, math.abs, math.floor, math.ceil
local UNIT = T.UNIT
local IDX, RAMP = T.IDX, T.RAMP
local DX, DY, DZ = T.DX, T.DY, T.DZ
local A = T.Affine

local World = {}
World.__index = World

local TILE = 16
local BACK = 2000
local SLAB = 3 -- how far the patio stands above the soil in the crack
World.TILE = TILE

--   #  patio slab (raised)          .  soil, moss in it
--   =  the trail the enemies walk   E  where they come in
--   H  the sprout: the network's Heart
--   pockets, where fruiting bodies grow:
--   p  a pebble (poor)   L  a fallen leaf, C  a crumb (normal)   B  a dead beetle (rich)
local MAP = {
    "################",
    "E=====#.L###p###",
    "#..C.=##..######",
    "#B...=====..C.##",
    "##.p.#...=.#..##",
    "#L..##.B.====H.#",
    "##..#....=C.L..#",
    "#p..#.C..=.#...#",
    "E=========.p#..#",
    "#B..##..L...C..#",
    "################",
}

local POCKET = {
    p = { kind = "pebble", quality = "poor" },
    L = { kind = "leaf", quality = "normal" },
    C = { kind = "crumb", quality = "normal" },
    B = { kind = "beetle", quality = "rich" },
}
World.QUALITY = {
    poor = { power = 0.75, income = 0 },
    normal = { power = 1, income = 0 },
    rich = { power = 1.3, income = 0.35 },
}

--- solids ----------------------------------------------------------------------

-- Each answers the nearest t along the ray from (ox, oy, oz) and the normal
-- there, or nothing. Every ray goes the same way (T.DX, DY, DZ), and every
-- component of it is negative, so of a box only the top, the +x face and the +z
-- face are ever seen.

local function hitBox(s, ox, oy, oz)
    local tx, tx1 = (s.x1 - ox) / DX, (s.x0 - ox) / DX
    local ty, ty1 = (s.y1 - oy) / DY, (s.y0 - oy) / DY
    local tz, tz1 = (s.z1 - oz) / DZ, (s.z0 - oz) / DZ
    local tin, tout = max(tx, ty, tz), min(tx1, ty1, tz1)
    if tin > tout then return end
    if tin == ty then return tin, 0, 1, 0 end
    if tin == tx then return tin, 1, 0, 0 end
    return tin, 0, 0, 1
end

-- An upright cylinder.
local CA = DX * DX + DZ * DZ
local function hitCyl(s, ox, oy, oz)
    local px, pz = ox - s.cx, oz - s.cz
    local qb = px * DX + pz * DZ
    local qc = px * px + pz * pz - s.r * s.r
    local disc = qb * qb - CA * qc
    if disc < 0 then return end
    disc = sqrt(disc)
    local ts, ts1 = (-qb - disc) / CA, (-qb + disc) / CA
    local ty, ty1 = (s.y1 - oy) / DY, (s.y0 - oy) / DY
    local tin, tout = max(ts, ty), min(ts1, ty1)
    if tin > tout then return end
    if ty >= ts then return tin, 0, 1, 0 end
    return tin, (px + ts * DX) / s.r, 0, (pz + ts * DZ) / s.r
end

-- An ellipsoid: a unit ball put through `at`, so it can lie at any angle.
local function hitEll(s, ox, oy, oz)
    local v = s.inv
    local ax = v[1] * ox + v[2] * oy + v[3] * oz + v[4]
    local ay = v[5] * ox + v[6] * oy + v[7] * oz + v[8]
    local az = v[9] * ox + v[10] * oy + v[11] * oz + v[12]
    local bx, by, bz = s.bx, s.by, s.bz
    local qb = ax * bx + ay * by + az * bz
    local qc = ax * ax + ay * ay + az * az - 1
    local d = qb * qb - s.qa * qc
    if d < 0 then return end
    local t = (-qb - sqrt(d)) / s.qa
    local ux, uy, uz = ax + t * bx, ay + t * by, az + t * bz
    local nx = v[1] * ux + v[5] * uy + v[9] * uz
    local ny = v[2] * ux + v[6] * uy + v[10] * uz
    local nz = v[3] * ux + v[7] * uy + v[11] * uz
    local l = sqrt(nx * nx + ny * ny + nz * nz)
    s.ux, s.uy, s.uz = ux, uy, uz
    return t, nx / l, ny / l, nz / l
end

local HIT = { box = hitBox, cyl = hitCyl, ell = hitEll }

--- what things are made of -------------------------------------------------------

-- A cheap hash for grain: the same speck lands in the same place every time.
local function grain(x, z, k)
    local n = math.sin(floor(x) * 12.9898 + floor(z) * 78.233 + (k or 0) * 37.719) * 43758.5453
    return n - floor(n)
end

-- `print` answers a key index for a pixel that is printed rather than lit (a
-- joint between slabs, a vein, a speck of grit), or nothing to take the ramp's.
local MAT = {}
local cellAt -- set by World.new: the map character under (x, z)

MAT.soil = { id = 2, ramp = RAMP.soil, print = function(s, x, y, z, nx, ny, nz, lev)
    if ny > 0.9 then
        local ch = cellAt(x, z)
        local g = grain(x, z)
        if ch == "=" or ch == "E" then
            -- The trail: trodden flat and pale, with grit.
            if g > 0.93 then return IDX.n end
            if g < 0.04 then return IDX.w end
            return IDX.t
        end
        -- Open soil: brown, with moss creeping in from the slabs' feet.
        local m = grain(floor(x / 3), floor(z / 3), 1)
        if m > 0.9 then return g > 0.4 and IDX.m or IDX.d end
        if g > 0.95 then return IDX.u end
        if g < 0.03 then return IDX.t end
        return IDX.n
    end
    -- The cut sides of the diorama: strata.
    local band = floor((-y + 0.5 * math.sin((x + z) * 0.15)) / 2.2)
    if band % 3 == 2 then return lev <= 2 and IDX.n or IDX.u end
    if grain(x + z, y * 3, 2) > 0.9 then return IDX.t end
end }

MAT.slab = { id = 3, ramp = RAMP.stone, print = function(s, x, y, z, nx, ny, nz, lev)
    if ny > 0.9 then
        -- Big flags, two tiles to a side, with a hairline joint and a crack or two.
        local jx, jz = x % 32, z % 32
        if jx < 0.9 or jz < 0.9 then return IDX.k end
        local g = grain(x, z, 3)
        if g > 0.985 then return IDX.k end
        if g < 0.008 then return IDX.w end
        local c = math.sin(x * 0.11 + z * 0.07) + math.sin(z * 0.13 - x * 0.05)
        if abs(c - 1.2) < 0.03 then return IDX.k end
    end
end }

MAT.leaf = { id = 4, ramp = RAMP.leaf, print = function(s, x, y, z, nx, ny, nz, lev)
    local ux, uz = s.ux, s.uz
    if abs(uz) < 0.07 then return IDX.d end                         -- the midrib
    if abs((abs(uz) - ux * 0.6) % 0.32) < 0.05 and lev <= 3 then return IDX.d end -- veins
    if grain(ux * 9, uz * 9, 5) > 0.85 then return IDX.t end        -- it is dying
end }
MAT.crumb = { id = 5, ramp = RAMP.crumb, print = function(s, x, y, z, nx, ny, nz, lev)
    if grain(x * 1.5, z * 1.5 + y, 6) > 0.8 then return IDX.n end
end }
MAT.beetle = { id = 6, ramp = RAMP.ink, print = function(s, x, y, z, nx, ny, nz, lev)
    if abs(s.uz or 1) < 0.05 and s.uy > 0.3 then return IDX.o end -- where the wing cases meet
end }
MAT.leg = { id = 7, ramp = RAMP.ink }
MAT.pebble = { id = 8, ramp = RAMP.stone }
MAT.mound = { id = 9, ramp = RAMP.soil, print = function(s, x, y, z)
    local g = grain(x * 2, z * 2, 7)
    if g > 0.9 then return IDX.u end
    if g < 0.12 then return IDX.t end
end }

--- building it -------------------------------------------------------------------

function World.new()
    local self = setmetatable({}, World)
    self.solids, self.pockets = {}, {}
    self.rows, self.cols = #MAP, #MAP[1]
    for r, row in ipairs(MAP) do assert(#row == self.cols, "map row " .. r .. " is the wrong length") end
    self.entrances = {}

    local function cell(c, r)
        local row = MAP[r + 1]
        if not row or c < 0 or c >= self.cols then return nil end
        return row:sub(c + 1, c + 1)
    end
    self.cell = cell
    cellAt = function(x, z) return cell(floor(x / TILE), floor(z / TILE)) end

    local nextPart = 10
    local function add(kind, mat, s)
        s.kind, s.mat, s.part = kind, mat, nextPart
        nextPart = nextPart + 1
        if kind == "ell" then
            local v = A.inv(s.at)
            s.inv = v
            s.bx = v[1] * DX + v[2] * DY + v[3] * DZ
            s.by = v[5] * DX + v[6] * DY + v[7] * DZ
            s.bz = v[9] * DX + v[10] * DY + v[11] * DZ
            s.qa = s.bx * s.bx + s.by * s.by + s.bz * s.bz
            -- A box round it for binning: the unit ball's box through the map.
            local m, cx, cy, cz = s.at, s.at[4], s.at[8], s.at[12]
            local ex = abs(m[1]) + abs(m[2]) + abs(m[3])
            local ey = abs(m[5]) + abs(m[6]) + abs(m[7])
            local ez = abs(m[9]) + abs(m[10]) + abs(m[11])
            s.x0, s.x1, s.y0, s.y1, s.z0, s.z1 = cx - ex, cx + ex, cy - ey, cy + ey, cz - ez, cz + ez
        elseif kind == "cyl" then
            s.x0, s.x1, s.z0, s.z1 = s.cx - s.r, s.cx + s.r, s.cz - s.r, s.cz + s.r
        end
        self.solids[#self.solids + 1] = s
        return s
    end
    local ell = T.ell

    -- The block of soil the whole board is cut from.
    local W, D = self.cols * TILE, self.rows * TILE
    add("box", MAT.soil, { x0 = 0, x1 = W, y0 = -12, y1 = 0, z0 = 0, z1 = D })
    -- Slabs: runs of '#' along a row are one box, so a long edge is one solid.
    for r = 0, self.rows - 1 do
        local c = 0
        while c < self.cols do
            if cell(c, r) == "#" then
                local c1 = c
                while cell(c1 + 1, r) == "#" do c1 = c1 + 1 end
                add("box", MAT.slab, { x0 = c * TILE, x1 = (c1 + 1) * TILE, y0 = -12, y1 = SLAB,
                    z0 = r * TILE, z1 = (r + 1) * TILE })
                c = c1 + 1
            else
                c = c + 1
            end
        end
    end

    -- Pockets, the Heart, and the trail's ends.
    for r = 0, self.rows - 1 do
        for c = 0, self.cols - 1 do
            local ch = cell(c, r)
            local cx, cz = c * TILE + TILE / 2, r * TILE + TILE / 2
            local seed = (c * 7 + r * 13) % 8
            local pk = POCKET[ch]
            if pk then
                local top
                local turn = A.rotY(seed * 0.785)
                if pk.kind == "leaf" then
                    add("ell", MAT.leaf, { at = ell(cx, 0.2, cz, 8, 1.3, 4.6, A.rotZ(0.08), turn) })
                    top = 1.4
                elseif pk.kind == "crumb" then
                    add("ell", MAT.crumb, { at = ell(cx, 0.5, cz, 4.5, 2.6, 3.6, turn) })
                    add("ell", MAT.crumb, { at = ell(cx + 2.5, 0.2, cz + 2, 2.4, 1.6, 2.2, turn) })
                    top = 2.8
                elseif pk.kind == "beetle" then
                    -- On its back: the reason it is rich.
                    add("ell", MAT.beetle, { at = ell(cx, 0.6, cz, 6, 2.6, 4.2, turn) })
                    add("ell", MAT.beetle, { at = A.mul(A.move(cx, 0, cz), turn, A.move(6.2, 0.9, 0), A.scale(2.2, 1.6, 2.4)) })
                    for n = -1, 1 do
                        for _, side in ipairs({ -1, 1 }) do
                            add("ell", MAT.leg, { at = A.mul(A.move(cx, 0, cz), turn,
                                T.ell(n * 2.6, 3.4, side * 3.2, 0.45, 2, 0.45, A.rotX(side * 0.5))) })
                        end
                    end
                    top = 3
                else
                    add("ell", MAT.pebble, { at = ell(cx, 0, cz, 5, 2.4, 4.2, turn) })
                    top = 2.3
                end
                self.pockets[#self.pockets + 1] = { x = cx, z = cz, y = top, c = c, r = r,
                    kind = pk.kind, quality = pk.quality }
            elseif ch == "H" then
                add("ell", MAT.mound, { at = ell(cx, -0.5, cz, 7, 3, 7) })
                self.heart = { x = cx, z = cz, y = 2.2, c = c, r = r }
            elseif ch == "E" then
                self.entrances[#self.entrances + 1] = { c = c, r = r, x = cx, z = cz }
            elseif ch == "." and grain(c, r, 9) > 0.72 then
                -- Gravel: not a pocket, just something to look at.
                add("ell", MAT.pebble, { at = ell(cx + (seed - 4), 0, cz + (seed % 3 - 1) * 3,
                    1.6 + seed * 0.2, 1.1, 1.4, A.rotY(seed)) })
            end
        end
    end

    self:route()

    -- How much of the screen the board covers, with a margin round it.
    local i0, j0, i1, j1 = math.huge, math.huge, -math.huge, -math.huge
    for _, x in ipairs({ 0, W }) do
        for _, z in ipairs({ 0, D }) do
            for _, y in ipairs({ -12, 30 }) do
                local i, j = T.project(x, y, z)
                i0, i1, j0, j1 = min(i0, i), max(i1, i), min(j0, j), max(j1, j)
            end
        end
    end
    self.i0, self.j0 = floor(i0) - 4, floor(j0) - 4
    self.w, self.h = ceil(i1) - self.i0 + 4, ceil(j1) - self.j0 + 4
    return self
end

-- The trail as a flow field: every trail tile knows how many steps it is from
-- the Heart, and an enemy on it walks to whichever neighbour is one fewer.
function World:route()
    local dist = {}
    local function key(c, r) return r * self.cols + c end
    local function walkable(c, r)
        local ch = self.cell(c, r)
        return ch == "=" or ch == "E" or ch == "H"
    end
    local h = self.heart
    local queue, head = { { h.c, h.r } }, 1
    dist[key(h.c, h.r)] = 0
    while queue[head] do
        local c, r = queue[head][1], queue[head][2]
        head = head + 1
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nc, nr = c + d[1], r + d[2]
            if walkable(nc, nr) and not dist[key(nc, nr)] then
                dist[key(nc, nr)] = dist[key(c, r)] + 1
                queue[#queue + 1] = { nc, nr }
            end
        end
    end
    self.dist = dist
    for _, e in ipairs(self.entrances) do assert(dist[key(e.c, e.r)], "an entrance with no way to the Heart") end
end

-- Steps to the Heart from tile (c, r), or nil off the trail.
function World:distAt(c, r)
    if c < 0 or r < 0 or c >= self.cols or r >= self.rows then return nil end
    return self.dist[r * self.cols + c]
end

-- The next trail tile towards the Heart from (c, r).
function World:nextTile(c, r)
    local d = self:distAt(c, r)
    if not d then return end
    for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nd = self:distAt(c + o[1], r + o[2])
        if nd and nd == d - 1 then return c + o[1], r + o[2] end
    end
end

-- Where each solid can land on the screen, binned in 16-pixel squares, so a
-- pixel only asks the handful that could be in it.
local BIN = 16

function World:bin()
    local bw, bh = ceil(self.w / BIN), ceil(self.h / BIN)
    local bins = {}
    for n = 1, bw * bh do bins[n] = {} end
    for _, s in ipairs(self.solids) do
        local i0, j0, i1, j1 = math.huge, math.huge, -math.huge, -math.huge
        for _, x in ipairs({ s.x0, s.x1 }) do
            for _, y in ipairs({ s.y0, s.y1 }) do
                for _, z in ipairs({ s.z0, s.z1 }) do
                    local i, j = T.project(x, y, z)
                    i0, i1, j0, j1 = min(i0, i), max(i1, i), min(j0, j), max(j1, j)
                end
            end
        end
        i0, i1 = floor(i0) - self.i0 - 1, ceil(i1) - self.i0 + 1
        j0, j1 = floor(j0) - self.j0 - 1, ceil(j1) - self.j0 + 1
        for by = max(0, floor(j0 / BIN)), min(bh - 1, floor(j1 / BIN)) do
            for bx = max(0, floor(i0 / BIN)), min(bw - 1, floor(i1 / BIN)) do
                local list = bins[by * bw + bx + 1]
                list[#list + 1] = s
            end
        end
    end
    return bins, bw
end

-- Paints the board. A coroutine body: it yields its progress (0..1) every few
-- rows so the load screen can say how far along it is.
function World:paint()
    local w, h = self.w, self.h
    local b = T.buffer(w, h)
    b.open = true
    self.wx = ffi.new("float[?]", w * h)
    self.wy = ffi.new("float[?]", w * h)
    self.wz = ffi.new("float[?]", w * h)
    self.up = ffi.new("uint8_t[?]", w * h)
    local bins, bw = self:bin()

    for pj = 0, h - 1 do
        for pi = 0, w - 1 do
            local ox, oy, oz = T.origin(self.i0 + pi + 0.5, self.j0 + pj + 0.5, BACK)
            local bt, nx, ny, nz, best = math.huge, 0, 1, 0, nil
            local bux, buy, buz
            for _, s in ipairs(bins[floor(pj / BIN) * bw + floor(pi / BIN) + 1]) do
                local t, ax, ay, az = HIT[s.kind](s, ox, oy, oz)
                if t and t < bt then
                    bt, nx, ny, nz, best = t, ax, ay, az, s
                    if s.kind == "ell" then bux, buy, buz = s.ux, s.uy, s.uz end
                end
            end
            local n = pj * w + pi
            if best then
                local x, y, z = ox + DX * bt, oy + DY * bt, oz + DZ * bt
                local m = best.mat
                local key, lev = T.shade(m.ramp, nx, ny, nz)
                if m.print then
                    if best.kind == "ell" then best.ux, best.uy, best.uz = bux, buy, buz end
                    local k = m.print(best, x, y, z, nx, ny, nz, lev)
                    if k then key, lev = k, 0 end
                end
                b.key[n], b.lev[n], b.shd[n] = key, lev, m.ramp[4]
                b.part[n], b.mat[n] = best.part, m.id
                b.dep[n] = BACK - bt
                b.dif[n] = T.diffuse(nx, ny, nz)
                b.nx[n], b.ny[n], b.nz[n] = nx, ny, nz
                self.wx[n], self.wy[n], self.wz[n] = x, y, z
                self.up[n] = ny > 0.7 and 1 or 0
            else
                b.dep[n] = -1e9
                self.wy[n] = -1e9
            end
        end
        if pj % 6 == 0 then coroutine.yield(pj / h) end
    end
    T.finish(b, 1.2)
    self.key, self.dep = b.key, b.dep

    -- Off the board is the dark under the patio.
    local data = love.image.newImageData(w, h)
    local bg = T.RGB[IDX.o]
    for pj = 0, h - 1 do
        for pi = 0, w - 1 do
            local k = self.key[pj * w + pi]
            local c = k ~= 0 and T.RGB[k] or bg
            data:setPixel(pi, pj, c[1], c[2], c[3], 1)
        end
    end
    self.image = love.graphics.newImage(data)
    self.image:setFilter("nearest", "nearest")
end

--- standing on it ----------------------------------------------------------------

-- The height of the ground at (x, z): the patio or the soil in the crack.
function World:groundAt(x, z)
    local ch = cellAt(x, z)
    if ch == "#" then return SLAB end
    return 0
end

-- Screen pixel (relative to the board's image) of a room point, and its depth.
function World:toImage(x, y, z)
    local i, j, d = T.project(x, y, z)
    return i - self.i0, j - self.j0, d
end

-- The room point under image pixel (i, j), or nil off the board.
function World:pick(i, j)
    i, j = floor(i), floor(j)
    if i < 0 or j < 0 or i >= self.w or j >= self.h then return end
    local n = j * self.w + i
    if self.wy[n] < -1e8 then return end
    return self.wx[n], self.wy[n], self.wz[n]
end

return World
