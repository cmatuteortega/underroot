-- What the mouse, a finger or a key means: each goes to the screen that is
-- up (src/ui/hud.lua for a run, else the picker, the loadout, the Spore Bank,
-- the encyclopedia or the title), after what they all share -- panning,
-- pinching, the wheel, a press that might be a tap or a drag.

local Sfx = require "src.sfx"
local S = require "src.ui.state"
local View = require "src.ui.view"
local flair = require "src.ui.flair"
local audio = require "src.ui.audio"
local codex = require "src.ui.codex"
local Title = require "src.ui.title"
local Loadout = require "src.ui.loadout"
local Bank = require "src.ui.bank"
local Menu = require "src.ui.menu"
local Hud = require "src.ui.hud"

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt
local padBoard, fit, centre, point, stepRange, zoomTo, zoomBy =
    View.padBoard, View.fit, View.centre, View.point, View.stepRange, View.zoomTo, View.zoomBy
local sound, deny = flair.sound, flair.deny

local input = {}

-- The screen up, the one the pointer and the keys go to: the run's own (the
-- HUD over the board) when no other is.
local SCREENS = { title = Title, loadout = Loadout, bank = Bank, codex = codex }
local function screen()
    if not S.menu then return Hud end
    return SCREENS[S.menu] or Menu
end

-- What the pointer is over, in S.hover.
local function findHover()
    S.hover = {}
    screen().hover(S.mouse.x, S.mouse.y)
end

-- Whatever is under the pointer that lights up when pressed: how to find its
-- box again (the layout can move under it while it is lit).
local function under()
    return screen().under()
end

local function click(b)
    local r = b == 1 and under()
    if r then flair.pressed = { t = 0.18, rect = r } end
    screen().click(b)
end

-- A press on a button or a node acts at once, so a thread can be pulled from
-- a node in one drag. A press anywhere else waits to see what it is: let go
-- where it was and it is a click there; moved first and it pans the board, which
-- is the only way to pan with one finger.
local SLOP = 3 -- HUD pixels a tap may wander and still be a tap

function input.mousepressed(x, y, b, istouch)
    if S.painter or S.pinch or S.turning then return end
    S.touch = istouch and true or false
    point(x, y)
    findHover()
    if b == 3 then S.mouse.pan = { wx = x, wy = y, px = S.panx, py = S.pany } return end
    if b == 1 and not (S.hover.button or S.hover.wave or S.hover.turn or S.hover.node or S.hover.mutation or S.hover.info) and not (S.mode == "grow" and S.drag) then
        S.press = { x = S.mouse.x, y = S.mouse.y, wx = x, wy = y, px = S.panx, py = S.pany }
        -- In the encyclopedia a drag scrolls it.
        if S.menu == "codex" then S.press.scroll = codex.getScroll() end
        return
    end
    click(b)
end

function input.mousereleased(x, y, b, istouch)
    if S.painter then return end
    if S.pinch then S.press = nil return end
    if b == 3 then S.mouse.pan = nil return end
    point(x, y)
    if b == 1 and S.press then
        local p = S.press
        S.press = nil
        if p.moved then return end
        -- The click lands where the press was, not wherever a finger rolled to.
        point(p.wx, p.wy)
        findHover()
        click(1)
        return
    end
    findHover()
    local t = S.tapped
    S.tapped = nil
    -- Pulled from one node and let go over another: a link.
    if b == 1 and S.mode == "grow" and S.drag and S.hover.node and S.hover.node ~= S.drag then
        if not S.game:grow(S.drag, S.hover.node) then deny() end
    elseif b == 1 and t and S.drag == t and S.hover.node == t then
        -- Let go where it was picked up: a tap, which selects its tower (or,
        -- on a bare pocket, puts the selection down).
        if t.tower then sound("panel") elseif S.selected then sound("back") end
        S.selected = t.tower
    end
    -- Links are only ever dragged: whatever was let go of, nothing is left in
    -- hand, so a tap never leaves a thread waiting for the next one.
    if b == 1 then S.drag = nil end
end

function input.mousemoved(x, y)
    point(x, y)
    if S.pinch then return end
    local pan = S.mouse.pan or S.press
    if S.press and not S.press.moved and (abs(S.mouse.x - S.press.x) > SLOP or abs(S.mouse.y - S.press.y) > SLOP) then
        S.press.moved = true
    end
    if S.press and S.press.moved and S.press.scroll then
        codex.setScroll(S.press.scroll - (S.mouse.y - S.press.y))
        return
    end
    if pan and (pan == S.mouse.pan or S.press.moved) then
        -- In board pixels: the ground stays under the finger at any zoom.
        S.panx = pan.px - floor((x - pan.wx) / S.zoom)
        S.pany = pan.py - floor((y - pan.wy) / S.zoom)
        S.focus = nil
    end
end

function input.wheelmoved(_, y)
    if S.menu == "codex" then codex.scrollBy(-y * 14) return end
    if y ~= 0 then zoomBy(y > 0 and 1 or -1, love.mouse.getPosition()) end
end

-- Pinching. While two fingers are down the finished frame is shown scaled by
-- however far they have spread and slid along with them, so the board follows
-- the hand at once; that picture is only a stretched copy for the moment the
-- fingers are on the glass. Let go and it settles on the nearest whole zoom,
-- with the board point that was under the fingers back under them, sharp.
-- Whatever the first finger had started -- a pan, a tap, a thread -- is
-- dropped, so a pinch never builds anything; and until the last finger lifts
-- no touch counts as a tap.
local function spread()
    local a, b = S.fingers[S.pinch.a], S.fingers[S.pinch.b]
    return sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2), (a.x + b.x) / 2, (a.y + b.y) / 2
end

function input.touchpressed(id, x, y)
    S.fingers[id] = { x = x, y = y }
    if S.pinch or S.painter then return end
    local ids = {}
    for k in pairs(S.fingers) do ids[#ids + 1] = k end
    if #ids == 2 then
        S.pinch = { a = ids[1], b = ids[2], s = 1 }
        local d, mx, my = spread()
        S.pinch.d0, S.pinch.x0, S.pinch.y0, S.pinch.x, S.pinch.y = max(d, 1), mx, my, mx, my
        if S.press then S.panx, S.pany = S.press.px, S.press.py; centre() end
        S.press, S.drag, S.tapped = nil, nil, nil
        -- Spread or pinched in, the frame shows past the window's edges: the
        -- whole board is drawn while the fingers are down, not just what was on
        -- the screen, so nothing is cut off until they let go.
        if S.world and S.game and not S.menu then
            local fx, fy, m = floor(S.camx), floor(S.camy), 8
            padBoard(max(0, fx + m), max(0, fy + m), max(0, S.world.w - fx - S.cw + m), max(0, S.world.h - fy - S.ch + m))
        end
    end
end

function input.touchmoved(id, x, y)
    if not S.fingers[id] then return end
    S.fingers[id].x, S.fingers[id].y = x, y
    if S.pinch and not S.pinch.done then
        local d, mx, my = spread()
        local lo, hi = stepRange()
        local base = S.zoom - S.zoomStep
        -- Held to what it can settle on, give or take half a step.
        S.pinch.s = max((base + lo - 0.45) / S.zoom, min((base + hi + 0.45) / S.zoom, d / S.pinch.d0))
        S.pinch.x, S.pinch.y = mx, my
    end
end

function input.touchreleased(id)
    if S.pinch and not S.pinch.done and (id == S.pinch.a or id == S.pinch.b) then
        local bx, by = S.pinch.x0 / S.zoom + S.camx, S.pinch.y0 / S.zoom + S.camy
        local step = floor(S.zoom * S.pinch.s + 0.5) - (S.zoom - S.zoomStep)
        zoomTo(step, bx, by, S.pinch.x, S.pinch.y)
        S.pinch.done = true
    end
    S.fingers[id] = nil
    if not next(S.fingers) then S.pinch = nil end
end

function input.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen())
        fit()
        return
    end
    if key == "v" then
        Sfx.cycle()
        audio.save()
        flair.note = 1.5
        sound("on")
        return
    end
    if S.painter then return end
    screen().key(key)
end

input.screen, input.findHover = screen, findHover

return input
