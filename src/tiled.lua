-- A board built from a painted isometric tileset (assets/tiles/isometric.png,
-- 32 px tiles, eleven to a row) instead of traced from solids.
--
-- The tileset is drawn at the same angle as the tracer -- a square of ground
-- is a diamond twice as wide as it is tall -- and with T.UNIT at sqrt(1/2) a
-- 16-unit tile is exactly its 32 x 16 diamond, so a tile's top-face centre
-- falls on a whole pixel and a block one level up sits exactly 8 pixels higher.
-- Heights are whole blocks: a raised rim, the field, a sunken trail, and the
-- water a half block down inside its own block.
--
-- The tiles are stamped back to front, painter's order, and every pixel a tile
-- leaves is given a place in the room by which face of its block it is on: the
-- top diamond lies at the block's top, the lower left and right are its +z and
-- +x sides, and anything standing up above the diamond (a tuft, a bush, a rock)
-- is on an upright plane through the cell's middle, facing the camera. That
-- gives the same depth buffer and room positions a traced board has, so an ant
-- still goes behind the lip of the trail and a shadow still finds the ground.
--
-- What grows and what the game asks about (pockets, the Heart's mound) is
-- still traced, over the tiles, wherever it is nearer than them.

local ffi = require "ffi"
local T = require "src.tracer"

local floor, min, max, abs, sqrt = math.floor, math.min, math.max, math.abs, math.sqrt
local DX, DY, DZ = T.DX, T.DY, T.DZ
local IDX = T.IDX

local Tiled = {}

local TILE = 16
local PX = 32 -- a tile's picture, and the width of its diamond
local COLS = 11
-- One block's height in room units: eight pixels on the screen.
local CE = math.cos(math.rad(30))
local L = 8 * T.UNIT / CE
Tiled.L = L
local BASE = -2 -- the lowest block of every column: the diorama's floor
local BACK = 2000

-- Which tiles. Indices count along the sheet's rows from 0.
local SET = {
    dirt = { 0, 1, 2, 4, 5, 6, 8, 9, 10 },
    soil = { 0, 1, 2, 4, 5, 6, 8, 9, 10, 19, 20 },
    under = { 11, 12, 13, 0, 1 },
    trail = { 21, 21, 17, 18, 3 },
    grass = { 40 },
    lawn = { 38, 39, 37, 38 },
    bush = { 33, 34, 35, 36, 32, 31 },
    slab = { 63, 63, 61 },
    water = { 110, 111, 112, 113, 114, 115, 116, 117, 118, 119 },
    rimProp = { 45, 44, 52, 57, 53, 54, 64, 65, 49, 51, 45, 56 },
    fieldProp = { 43, 46, 58, 56 },
    pebbles = { 62, 53, 43 },
    flowers = { 41, 42, 47, 43 },
}

-- Each level's look: which characters stand a block up (`raised`, with the
-- tiles for their top and sides), the tiles for the rest of the field, and
-- what grows on the raised ground and in the field, how often.
local THEMES = {
    pond = {
        raised = { r = true }, raisedTop = SET.dirt, raisedSide = SET.dirt, tall = true,
        field = SET.grass, raisedProp = { SET.rimProp, 0.45 }, fieldProp = { ["."] = { SET.fieldProp, 0.2 } },
    },
    crack = {
        raised = { ["#"] = true }, raisedTop = SET.slab, raisedSide = SET.slab,
        field = SET.soil, fieldProp = { ["."] = { SET.pebbles, 0.15 } },
    },
    lawn = {
        raised = { Y = true }, raisedTop = SET.bush, raisedSide = SET.dirt,
        field = SET.lawn, fieldProp = { ['"'] = { SET.flowers, 0.12 } },
    },
}

-- A cheap hash, the same as the world's grain.
local function grain(x, z, k)
    local n = math.sin(floor(x) * 12.9898 + floor(z) * 78.233 + (k or 0) * 37.719) * 43758.5453
    return n - floor(n)
end
local function pick(list, c, r, k) return list[floor(grain(c, r, k) * #list) + 1] end

-- The map's characters as heights, in blocks: the top block of the column.
local TRAIL = { ["="] = true, E = true }
local WATER = { o = true, ["~"] = true, P = true }
local DEEP = { o = true, P = true, ["~"] = true } -- water, half a block down in its block

-- Raised ground stands a block up (two, now and then, along the back of a
-- `tall` level) and comes down to the field's height along the two near
-- edges, so it never hides what walks in front of it.
function Tiled.level(world, ch, c, r)
    local theme = THEMES[world.id]
    if theme.raised[ch] then
        if r == world.rows - 1 or c == world.cols - 1 then return 0 end
        if theme.tall and (r == 0 or c == 0) and grain(c, r, 81) > 0.6 then return 2 end
        return 1
    end
    if TRAIL[ch] or WATER[ch] then return -1 end
    return 0
end

-- The height of what stands on (c, r): water's surface is half a block down
-- inside its block.
function Tiled.ground(world, ch, c, r)
    local top = Tiled.level(world, ch, c, r) * L
    if DEEP[ch] then return top - L / 2 end
    return top
end

local sheet, spx, sw
local function load()
    if sheet then return end
    sheet = love.image.newImageData("assets/tiles/isometric.png")
    spx = ffi.cast("uint8_t*", sheet:getFFIPointer())
    sw = sheet:getWidth()
end

-- Nearest palette key to a colour, for what still reads the board by key
-- (the fairy ring's moss, the weather of the traced boards).
local nearest = {}
local function keyOf(r, g, b)
    local id = r * 65536 + g * 256 + b
    local k = nearest[id]
    if k then return k end
    local bd = math.huge
    for i, c in ipairs(T.RGB) do
        local d = (c[1] * 255 - r) ^ 2 + (c[2] * 255 - g) ^ 2 + (c[3] * 255 - b) ^ 2
        if d < bd then k, bd = i, d end
    end
    nearest[id] = k
    return k
end

-- The upright plane things stand on: through a cell's middle, facing you.
local UNX, UNZ
do
    local nx, nz = -DX, -DZ
    local n = sqrt(nx * nx + nz * nz)
    UNX, UNZ = nx / n, nz / n
end

function Tiled.paint(world)
    load()
    local w, h = world.w, world.h
    local n = w * h
    local rgb = ffi.new("uint8_t[?]", n * 3)
    local dep = ffi.new("float[?]", n)
    local wx, wy, wz = ffi.new("float[?]", n), ffi.new("float[?]", n), ffi.new("float[?]", n)
    local up = ffi.new("uint8_t[?]", n)
    for p = 0, n - 1 do dep[p], wy[p] = -1e9, -1e9 end
    world.rgb, world.dep, world.wx, world.wy, world.wz, world.up = rgb, dep, wx, wy, wz, up

    -- Lays tile `t` with its top-face centre over room point (cx, top, cz) --
    -- `drop` pixels lower for a tile whose face sits down inside its block --
    -- as a block of cell (c, r), or (`prop`) as a thing standing in it.
    -- `calm`: a water tile's top, whose bright rim is only kept along a shore,
    -- so open water reads as one sheet rather than a grid of tiles.
    -- `ford`: a trail tile seen through the water's top, half and half, for a
    -- flooded stretch of trail: the trodden path under the water.
    local function stamp(t, c, r, top, drop, prop, calm, ford)
        local cx, cz = c * TILE + TILE / 2, r * TILE + TILE / 2
        local si, sj = world:toImage(cx, top, cz)
        local bi, bj = floor(si + 0.5) - PX / 2, floor(sj + 0.5) - PX / 2
        local tx, ty = (t % COLS) * PX, floor(t / COLS) * PX
        local x1, z1 = (c + 1) * TILE - 0.001, (r + 1) * TILE - 0.001
        local face = top - drop * T.UNIT / CE
        local still -- the water's own colour, from the middle of its face
        if calm then
            local s = ((ty + PX / 2 + drop) * sw + tx + PX / 2) * 4
            still = { spx[s], spx[s + 1], spx[s + 2] }
        end
        for v = 0, PX - 1 do
            local j = bj + v
            if j >= 0 and j < h then
                for u = 0, PX - 1 do
                    local i = bi + u
                    local s = ((ty + v) * sw + tx + u) * 4
                    local du, dv = u + 0.5 - PX / 2, v + 0.5 - PX / 2 - drop
                    -- Calm water leaves out the lip its tile has above the
                    -- surface: the water behind shows there instead.
                    local lip = calm and dv < 0 and abs(du) / 16 + abs(dv) / 8 > 1
                    if i >= 0 and i < w and spx[s + 3] > 127 and not lip then
                        local ox, oy, oz = T.origin(world.i0 + i + 0.5, world.j0 + j + 0.5, BACK)
                        local tt, isUp
                        if prop or (dv < 0 and abs(du) / 16 + abs(dv) / 8 > 1) then
                            tt = ((cx - ox) * UNX + (cz - oz) * UNZ) / (DX * UNX + DZ * UNZ)
                        elseif abs(du) / 16 + abs(dv) / 8 <= 1 then
                            tt, isUp = (face - oy) / DY, true
                        elseif du > 0 then
                            tt = (x1 - ox) / DX
                        else
                            tt = (z1 - oz) / DZ
                        end
                        local x, y, z = ox + DX * tt, oy + DY * tt, oz + DZ * tt
                        local p = j * w + i
                        rgb[p * 3], rgb[p * 3 + 1], rgb[p * 3 + 2] = spx[s], spx[s + 1], spx[s + 2]
                        if calm and isUp and abs(du) / 16 + abs(dv) / 8 > 0.7 then
                            -- Which neighbour this edge of the diamond faces.
                            local nc, nr = c, r
                            if du < 0 and dv < 0 then nc = c - 1
                            elseif du > 0 and dv < 0 then nr = r - 1
                            elseif du > 0 then nc = c + 1
                            else nr = r + 1 end
                            if DEEP[world.cell(nc, nr)] then
                                rgb[p * 3], rgb[p * 3 + 1], rgb[p * 3 + 2] = still[1], still[2], still[3]
                            end
                        end
                        if ford and isUp then
                            local q = (((floor(ford / COLS) * PX) + v - drop) * sw + (ford % COLS) * PX + u) * 4
                            if spx[q + 3] > 127 then
                                rgb[p * 3] = (rgb[p * 3] + spx[q]) / 2
                                rgb[p * 3 + 1] = (rgb[p * 3 + 1] + spx[q + 1]) / 2
                                rgb[p * 3 + 2] = (rgb[p * 3 + 2] + spx[q + 2]) / 2
                            end
                        end
                        dep[p] = BACK - tt
                        wx[p], wy[p], wz[p] = x, y, z
                        up[p] = isUp and 1 or 0
                    end
                end
            end
        end
    end

    -- Back to front: by the diagonal a cell is on, and up each column.
    local cell = world.cell
    local theme = THEMES[world.id]
    for s = 0, world.cols + world.rows - 2 do
        for c = max(0, s - world.rows + 1), min(world.cols - 1, s) do
            local r = s - c
            local ch = cell(c, r)
            local top = Tiled.level(world, ch, c, r)
            local raised = theme.raised[ch]
            for k = BASE, top do
                local t, drop, calm, ford = pick(SET.under, c, r, k + 90), 0, false, nil
                if k == top then
                    if raised then t = pick(theme.raisedTop, c, r, 82)
                    elseif TRAIL[ch] then t = pick(SET.trail, c, r, 83)
                    elseif WATER[ch] then
                        t, drop, calm = pick(SET.water, c, r, 84), 4, true
                        if ch == "~" then ford = pick(SET.trail, c, r, 83) end
                    else t = pick(theme.field, c, r, 85) end
                elseif raised and k > 0 then
                    t = pick(theme.raisedSide, c, r, k + 86)
                end
                stamp(t, c, r, k * L, drop, false, calm, ford)
            end
            -- Something growing on the raised ground, or now and then in the field.
            local grow = raised and theme.raisedProp or theme.fieldProp[ch]
            if grow and grain(c, r, 87) < grow[2] then
                stamp(pick(grow[1], c, r, 88), c, r, (top + 1) * L, 0, true)
            end
        end
        coroutine.yield(0.5 * s / (world.cols + world.rows))
    end

    -- What is still traced (the pockets, the Heart's mound) goes over the tiles
    -- wherever it is nearer.
    local props = world:traceProps(function(pj) coroutine.yield(0.5 + 0.5 * pj / h) end)
    for p = 0, n - 1 do
        local k = props.key[p]
        if k ~= 0 and props.dep[p] > dep[p] - 0.5 then
            local c = T.RGB[k]
            rgb[p * 3], rgb[p * 3 + 1], rgb[p * 3 + 2] = c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5
            dep[p] = props.dep[p]
            wx[p], wy[p], wz[p], up[p] = props.wx[p], props.wy[p], props.wz[p], props.up[p]
        end
    end

    local key = ffi.new("uint8_t[?]", n)
    for p = 0, n - 1 do
        if dep[p] > -1e8 then key[p] = keyOf(rgb[p * 3], rgb[p * 3 + 1], rgb[p * 3 + 2]) end
    end
    world.key = key
    world.image = Tiled.image(world, function(p, r, g, b) return r, g, b end)
end

-- The board's picture, each pixel's colour passed through `f` (p, r, g, b).
local BG = T.RGB[IDX.o]
function Tiled.image(world, f)
    local w, h, rgb = world.w, world.h, world.rgb
    local data = love.image.newImageData(w, h)
    local d = ffi.cast("uint8_t*", data:getFFIPointer())
    for p = 0, w * h - 1 do
        local r, g, b
        if world.dep[p] > -1e8 then
            r, g, b = f(p, rgb[p * 3], rgb[p * 3 + 1], rgb[p * 3 + 2])
        else
            r, g, b = BG[1] * 255, BG[2] * 255, BG[3] * 255
        end
        d[p * 4], d[p * 4 + 1], d[p * 4 + 2], d[p * 4 + 3] = max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)), 255
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return img
end

-- The weathers, on colours rather than keys.
function Tiled.variant(world, kind)
    local up, wx, wz = world.up, world.wx, world.wz
    local w = world.w
    return Tiled.image(world, function(p, r, g, b)
        if kind == "night" then
            return r * 0.45, g * 0.5, b * 0.7
        elseif kind == "frost" then
            if up[p] == 1 and grain(wx[p] * 1.7, wz[p] * 1.7, 15) > 0.85 then return 226, 236, 240 end
            return r * 0.85 + 30, g * 0.85 + 34, b * 0.85 + 40
        elseif kind == "drought" then
            if g > r and g > b then r, g = (r + g) * 0.6, g * 0.85 end
            return r, g, b * 0.8
        elseif kind == "rain" then
            local ch = world.cellAt(wx[p], wz[p])
            if up[p] == 1 and TRAIL[ch] then
                local x, z = wx[p], wz[p]
                if math.sin(x * 0.21 + z * 0.13) + math.sin(z * 0.27 - x * 0.09) > 1.1 then
                    return ((p % w) + floor(p / w)) % 3 == 0 and 190 or 120, 160, 190
                end
            end
            return r * 0.78, g * 0.8, b * 0.88
        end
        return r, g, b
    end)
end

return Tiled
