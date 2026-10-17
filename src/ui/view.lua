-- The camera and the two canvases it looks through: the board's at a zoom
-- that goes in and out in whole steps, the HUD's at one that stays put; panning,
-- zooming about a point, going a quarter round the board, and easing toward
-- whatever is selected.

local ffi = require "ffi"
local World = require "src.world"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Toolbar = require "src.ui.toolbar"
local Panel = require "src.ui.panel"
local flair = require "src.ui.flair"

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local wide = Draw.wide
local sound = flair.sound
local SHORT, TOP, BOTTOM, UI_STEP, ZOOM_STEPS = S.SHORT, S.TOP, S.BOTTOM, S.UI_STEP, S.ZOOM_STEPS

-- The board's picture: the window's worth, and pad past each edge of it.
local function padBoard(l, t, r, b)
    S.pad.l, S.pad.t, S.pad.r, S.pad.b = l, t, r, b
    local w, h = S.cw + l + r, S.ch + t + b
    S.canvas = love.graphics.newCanvas(w, h)
    S.canvas:setFilter("nearest", "nearest")
    -- The overlay is one byte-for-byte picture of everything laid over the board
    -- this frame: a pixel is either covered, fully, or not there. Painter's order
    -- is simply the order things are put.
    S.overlay = love.image.newImageData(w, h, "rgba8")
    S.opx = ffi.cast("uint8_t*", S.overlay:getFFIPointer())
    S.overlayImage = love.graphics.newImage(S.overlay)
    S.overlayImage:setFilter("nearest", "nearest")
end

local function fit()
    local w, h = love.graphics.getDimensions()
    local base = max(1, floor(min(w, h) / SHORT))
    S.uz = base + UI_STEP
    S.vw, S.vh = ceil(w / S.uz), ceil(h / S.uz)
    S.ui = love.graphics.newCanvas(S.vw, S.vh)
    S.ui:setFilter("nearest", "nearest")

    S.zoom = base + S.zoomStep
    S.cw, S.ch = ceil(w / S.zoom), ceil(h / S.zoom)
    padBoard(0, 0, 0, 0)
end

-- HUD pixels to board pixels: what the strip and toolbar cover of the board.
local function toBoard(u) return u * S.uz / S.zoom end

-- A board-image pixel to the HUD pixel over it.
local function toHud(i, j)
    return floor((i - floor(S.camx)) * S.zoom / S.uz), floor((j - floor(S.camy)) * S.zoom / S.uz)
end

-- The camera on the middle of the board, less what the strip and the
-- toolbar cover, moved by the pan.
local function centre()
    local l, r = toBoard(S.inset.l), toBoard(S.inset.r)
    local top, bottom = toBoard(S.inset.t + TOP), toBoard(S.inset.b + BOTTOM)
    S.camx = floor((S.world.w - (S.cw - l - r)) / 2 - l) + S.panx
    S.camy = floor((S.world.h - (S.ch - top - bottom)) / 2 - top) + S.pany
end

-- The board-image pixel under the mouse.
local function cursor()
    return floor(S.mouse.wx / S.zoom) + floor(S.camx), floor(S.mouse.wy / S.zoom) + floor(S.camy)
end

-- The pointer is at window pixel (x, y): where that is in HUD pixels too.
local function point(x, y)
    S.mouse.wx, S.mouse.wy = x, y
    S.mouse.x, S.mouse.y = floor(x / S.uz), floor(y / S.uz)
end

-- The zoom is whole steps past the one that fits the board: one step out of
-- it, ZOOM_STEPS in. A whole number, because the art is pixels.
local function stepRange()
    local base = max(1, floor(min(love.graphics.getDimensions()) / SHORT))
    return max(1, base - 1) - base, ZOOM_STEPS
end

-- Goes to a step and puts the board point (bx, by) under the window pixel
-- (sx, sy). Called with the same step it only pans: that is how a pinch's
-- slide is kept when it settles on the zoom it started at.
local function zoomTo(step, bx, by, sx, sy)
    if not S.world then return end
    local lo, hi = stepRange()
    S.zoomStep = max(lo, min(hi, step))
    S.focus, S.focused = nil, S.selected -- aimed at the old zoom; the player has taken over
    fit()
    centre()
    S.panx = S.panx + (bx - sx / S.zoom) - S.camx
    S.pany = S.pany + (by - sy / S.zoom) - S.camy
    centre()
    point(sx, sy)
end

-- One step in or out about a window pixel (the cursor, or the middle).
local function zoomBy(d, sx, sy)
    local lo, hi = stepRange()
    -- No board yet (the picker before the first level): nothing to zoom.
    if S.painter or not S.world or S.zoomStep + d < lo or S.zoomStep + d > hi then return end
    sound("zoom", d > 0 and 1.2 or 0.85)
    sx, sy = sx or love.graphics.getWidth() / 2, sy or love.graphics.getHeight() / 2
    zoomTo(S.zoomStep + d, sx / S.zoom + S.camx, sy / S.zoom + S.camy, sx, sy)
end

-- Finishes painting view q of the board now, if the background has not got
-- there yet (see love.update).
local function paintNow(q)
    local bg = S.world.backPainter
    while not S.world:painted(q) and bg and coroutine.status(bg) ~= "dead" do
        local ok, err = coroutine.resume(bg)
        if not ok then error(err) end
    end
    if not S.world:painted(q) then
        local co = coroutine.create(function() S.world:paint(q) end)
        while coroutine.status(co) ~= "dead" do
            local ok, err = coroutine.resume(co)
            if not ok then error(err) end
        end
    end
end

-- Takes the camera a quarter turn round the board, d = 1 or -1. The ground
-- under the middle of the screen stays where it is and the board turns about
-- it; the frame being left is kept to be shown going round.
local function turnCamera(d)
    if S.turning or S.pinch or S.painter or S.menu or not S.game then return end
    local q = (S.world.turn + d) % World.TURNS
    paintNow(q)
    local mi, mj = floor(S.cw / 2), floor(S.ch / 2)
    local x, y, z = S.world:pick(mi + floor(S.camx), mj + floor(S.camy))
    if not x then
        x, z = S.world.W / 2, S.world.D / 2
        y = S.world:groundAt(x, z)
    end
    local i0, j0 = S.world:toImage(x, y, z)
    local i1, j1 = S.world:toImage(x + 10, y, z)
    local px, py = i0 - floor(S.camx), j0 - floor(S.camy)
    local a0 = math.atan2((j1 - j0) * 2, i1 - i0)

    local old = love.graphics.newCanvas(S.cw, S.ch)
    old:setFilter("nearest", "nearest")
    love.graphics.setCanvas(old)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(S.canvas)
    love.graphics.setCanvas()

    S.world:setTurn(q)
    S.focus = nil
    centre()
    local n0, m0 = S.world:toImage(x, y, z)
    S.panx = S.panx + (n0 - floor(S.camx)) - px
    S.pany = S.pany + (m0 - floor(S.camy)) - py
    centre()
    -- How far the picture goes round on the screen, measured with the ground
    -- unsquashed so a quarter turn of the room is a quarter turn of it.
    local n1, m1 = S.world:toImage(x + 10, y, z)
    local a = math.atan2((m1 - m0) * 2, n1 - n0) - a0
    a = (a + math.pi) % (2 * math.pi) - math.pi
    S.turning = { t = 0, old = old, px = px, py = py, angle = a, d = d }
    sound("turn", d > 0 and 1 or 0.85)
end

-- Where the camera should go to show `s` (a tower, mat or shelf) beside the
-- info panel: a third of the way across a wide screen, the panel on the right;
-- and half way down; on a narrow one in the middle of what is left under the
-- panel.
local function focusOn(s)
    local x, y, z
    if s.node then x, y, z = s.node.x, s.node.y + 6, s.node.z else x, y, z = s.x, (s.y or 0) + 3, s.z end
    local i, j = S.world:toImage(x, y, z)
    local hx, hy = (i - S.camx) * S.zoom / S.uz, (j - S.camy) * S.zoom / S.uz
    local wx, wy
    if wide() then
        wx, wy = floor(S.vw / 3), floor(S.vh / 2)
    else
        local P = Panel.info()
        wx = floor(S.vw / 2)
        wy = floor((P.y + P.h + Toolbar.barTop() - 30) / 2)
    end
    return { x = S.panx + toBoard(hx - wx), y = S.pany + toBoard(hy - wy) }
end

return {
    padBoard = padBoard,
    fit = fit,
    toBoard = toBoard,
    toHud = toHud,
    centre = centre,
    cursor = cursor,
    point = point,
    stepRange = stepRange,
    zoomTo = zoomTo,
    zoomBy = zoomBy,
    turnCamera = turnCamera,
    focusOn = focusOn,
}
