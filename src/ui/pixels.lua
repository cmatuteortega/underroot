-- The overlay: everything that changes on the board, laid a pixel at a time
-- over the board's picture into one byte-for-byte image, each pixel kept only
-- where it is nearer than the board there. And the same pictures flat on the
-- HUD (blit), for the toolbar, the cards and the panels.

local T = require "src.tracer"
local M = require "src.models"
local S = require "src.ui.state"

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local IDX = T.IDX

local RGB8 = {}
for k, c in ipairs(T.RGB) do RGB8[k] = { floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5) } end

-- Put key k at screen pixel (x, y).
local function putS(k, x, y)
    if k == 0 or x < 0 or y < 0 or x >= S.cw or y >= S.ch then return end
    local p = (y * S.cw + x) * 4
    local c = RGB8[k]
    S.opx[p], S.opx[p + 1], S.opx[p + 2], S.opx[p + 3] = c[1], c[2], c[3], 255
end

-- Put key k at board-image pixel (i, j).
local function put(k, i, j) putS(k, floor(i - floor(S.camx)), floor(j - floor(S.camy))) end

-- Put the board's own pixel back at board-image pixel (i, j), a step darker if
-- `dark`. A tiled board is colours, not keys: darker is a shade, not a ramp step.
local function putGround(i, j, dark)
    local n = j * S.world.w + i
    if not S.world.rgb then return put(dark and T.DARKER[S.world.key[n]] or S.world.key[n], i, j) end
    local x, y = floor(i - floor(S.camx)), floor(j - floor(S.camy))
    if x < 0 or y < 0 or x >= S.cw or y >= S.ch then return end
    local p, f = (y * S.cw + x) * 4, dark and 0.6 or 1
    local rgb = S.world.rgb
    S.opx[p], S.opx[p + 1], S.opx[p + 2], S.opx[p + 3] = rgb[n * 3] * f, rgb[n * 3 + 1] * f, rgb[n * 3 + 2] * f, 255
end

-- Is room depth d nearer than the board at image pixel (i, j)?
local function visible(i, j, d)
    if i < 0 or j < 0 or i >= S.world.w or j >= S.world.h then return true end
    return d >= S.world.dep[j * S.world.w + i] - 0.6
end

-- The board-image pixels a box of the room can cover, whichever way the board
-- is turned: i0, i1, j0, j1.
local function screenBox(x0, x1, y0, y1, z0, z1)
    local i0, i1, j0, j1 = math.huge, -math.huge, math.huge, -math.huge
    for _, x in ipairs({ x0, x1 }) do
        for _, y in ipairs({ y0, y1 }) do
            for _, z in ipairs({ z0, z1 }) do
                local i, j = S.world:toImage(x, y, z)
                i0, i1, j0, j1 = min(i0, i), max(i1, i), min(j0, j), max(j1, j)
            end
        end
    end
    return floor(i0) - 1, ceil(i1) + 1, floor(j0), ceil(j1)
end

-- A heading in the room as it is seen in the view shown.
local function turned(h) return h + S.world.turn * math.pi / 2 end

-- A picture laid down with its pivot at a room point, through a remap.
local function stamp(pic, x, y, z, remap)
    remap = remap or T.SAME
    local si, sj, d = S.world:toImage(x, y, z)
    local bi, bj = floor(si) - pic.oi, floor(sj) - pic.oj
    local w = pic.w
    for pj = 0, pic.h - 1 do
        for pi = 0, w - 1 do
            local n = pj * w + pi
            local k = pic.key[n]
            if k ~= 0 and visible(bi + pi, bj + pj, d + pic.dep[n]) then put(remap[k], bi + pi, bj + pj) end
        end
    end
end

-- A one-pixel line in key k round a picture stamped as above: every empty pixel
-- next to one of its own, as near as the pixel it borders, so the board in front
-- still hides it.
local function outline(pic, x, y, z, k)
    local si, sj, d = S.world:toImage(x, y, z)
    local bi, bj = floor(si) - pic.oi, floor(sj) - pic.oj
    local w, h, key, dep = pic.w, pic.h, pic.key, pic.dep
    local function at(pi, pj)
        if pi < 0 or pj < 0 or pi >= w or pj >= h then return nil end
        local n = pj * w + pi
        if key[n] ~= 0 then return dep[n] end
    end
    for pj = -1, h do
        for pi = -1, w do
            if not at(pi, pj) then
                local near = at(pi - 1, pj) or at(pi + 1, pj) or at(pi, pj - 1) or at(pi, pj + 1)
                if near and visible(bi + pi, bj + pj, d + near) then put(k, bi + pi, bj + pj) end
            end
        end
    end
end

-- The same picture flat on the screen, for the toolbar and the upgrade cards.
-- Made into an image once per picture and remap, then drawn whole.
local blits = setmetatable({}, { __mode = "k" })
local function blit(pic, x, y, remap)
    remap = remap or T.SAME
    local per = blits[pic]
    if not per then per = {}; blits[pic] = per end
    local img = per[remap]
    if not img then
        local data = love.image.newImageData(pic.w, pic.h)
        for pj = 0, pic.h - 1 do
            for pi = 0, pic.w - 1 do
                local k = pic.key[pj * pic.w + pi]
                if k ~= 0 then
                    local c = T.RGB[remap[k]]
                    data:setPixel(pi, pj, c[1], c[2], c[3], 1)
                end
            end
        end
        img = love.graphics.newImage(data)
        img:setFilter("nearest", "nearest")
        per[remap] = img
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, x - pic.oi, y - pic.oj)
end

-- A shadow straight down onto whatever faces up under (x, z): each pixel there
-- goes one step darker.
local function shadow(x, z, r)
    local g = S.world:groundAt(x, z)
    local i0, i1, j0, j1 = screenBox(x - r, x + r, g - 1, g + 4, z - r, z + r)
    for j = max(0, j0), min(S.world.h - 1, j1) do
        for i = max(0, i0), min(S.world.w - 1, i1) do
            local n = j * S.world.w + i
            if S.world.up[n] == 1 and (S.world.wx[n] - x) ^ 2 + (S.world.wz[n] - z) ^ 2 <= r * r then
                putGround(i, j, true)
            end
        end
    end
end

-- A line plotted through the room, a pixel at a time, depth tested along it.
local function line3(x0, y0, z0, x1, y1, z1, k)
    local i0, j0, d0 = S.world:toImage(x0, y0, z0)
    local i1, j1, d1 = S.world:toImage(x1, y1, z1)
    local steps = max(1, ceil(max(abs(i1 - i0), abs(j1 - j0))))
    for s = 0, steps do
        local t = s / steps
        local i, j = floor(i0 + (i1 - i0) * t), floor(j0 + (j1 - j0) * t)
        if visible(i, j, d0 + (d1 - d0) * t + 1) then put(k, i, j) end
    end
end

-- A ring on the ground: a tower's reach.
local function ring(x, z, r, k, dash)
    local n = max(24, floor(r * 1.6))
    for s = 0, n - 1 do
        if not dash or s % 2 == 0 then
            local a = s / n * 2 * math.pi
            local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
            local i, j, d = S.world:toImage(px, S.world:groundAt(px, pz) + 0.3, pz)
            if visible(floor(i), floor(j), d + 1) then put(k, i, j) end
        end
    end
end

-- A fruiting body flat on a button or a card. The Humongous Fungus is shown
-- as it is coming up, or it would not fit.
local function icon(kind, branch, tier, idle)
    return M.tower(kind, branch, tier, idle, 0, kind == "giant" and 0.34 or nil)
end

-- What is not found yet: the picture in ink, a cutout.
local CUT = {}
for k = 1, #T.KEYS do CUT[k] = IDX.o end

return {
    putS = putS,
    put = put,
    putGround = putGround,
    visible = visible,
    screenBox = screenBox,
    turned = turned,
    stamp = stamp,
    outline = outline,
    blit = blit,
    icon = icon,
    shadow = shadow,
    line3 = line3,
    ring = ring,
    CUT = CUT,
}
