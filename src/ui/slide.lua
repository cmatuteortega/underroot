-- The way from one screen to the next. The screen that was up slides off one
-- side as the new one comes in from the other: on a way in (a deeper screen),
-- left; on a way back (to one already passed on the way here), right. The
-- screens under the night sky -- the title, the home screen, the settings and
-- the level picker -- keep the sky, the ground and the sprout where they are
-- (src/ui/title.lua's backdrop), and only what is laid over it goes. The
-- network dives down into that ground from the home screen and comes back
-- up out of it (src/ui/network.lua), so that way does not slide either. Leaving a
-- run, the board stays put under the HUD going and the new screen coming.
--
-- Each screen draws onto `slide.front` (its backdrop onto S.ui, under it, while
-- that stays put), and slide.compose lays the two pictures onto S.ui where
-- they are along the way. The title's own way into the home screen is the
-- ground going down, so it does not slide; nor does anything in the shots.

local S = require "src.ui.state"
local flair = require "src.ui.flair"

local floor = math.floor

local slide = {}

slide.TIME = 0.35
-- The screens under the night sky.
slide.NIGHT = { title = true, home = true, settings = true, levels = true }
-- Ways that are not a slide: the screen's own animation does it.
slide.OWN = { ["title>home"] = true, ["home>network"] = true, ["network>home"] = true }

slide.cur = nil -- the screen up
slide.stack = {} -- the screens passed on the way to it, the first one first
slide.t0 = nil -- when the slide began, or nil when none is under way

-- Which screen is up: the board being painted, a menu, or the run.
function slide.key()
    if S.painter then return "loading" end
    if S.menu == true then return "levels" end
    return S.menu or "game"
end

local function canvas(c)
    if not c or c:getWidth() ~= S.vw or c:getHeight() ~= S.vh then c = love.graphics.newCanvas(S.vw, S.vh) end
    return c
end

-- How far along the slide is, eased (0..1), or nil when none is under way.
function slide.progress()
    if not slide.t0 then return nil end
    local f = (flair.now() - slide.t0) / slide.TIME
    if f >= 1 then slide.t0 = nil return nil end
    return f * f * (3 - 2 * f)
end

function slide.busy() return slide.progress() ~= nil end
-- The backdrop stays put under the screens: no slide, or one between two
-- under the night sky.
function slide.fixed() return not slide.busy() or slide.shared end
-- The board is still showing under a screen coming in over the run.
function slide.showsBoard() return slide.busy() and slide.board end

-- Called before each frame is drawn: if the screen up has changed since the
-- last frame, keep that frame's picture of the old one and start the slide.
function slide.check()
    slide.front = canvas(slide.front)
    slide.old = canvas(slide.old)
    local k = slide.key()
    if k == slide.cur then return end
    local from = slide.cur
    slide.cur = k
    -- Back to a screen passed on the way here is a way back; anywhere else is
    -- a way in, and goes on the list.
    local back = false
    for n = #slide.stack, 1, -1 do
        if slide.stack[n] == k then
            back = true
            for m = #slide.stack, n + 1, -1 do slide.stack[m] = nil end
            break
        end
    end
    if not back then slide.stack[#slide.stack + 1] = k end
    if not from or S.script or slide.OWN[from .. ">" .. k] then slide.t0 = nil return end
    slide.dir = back and -1 or 1
    slide.shared = slide.NIGHT[from] and slide.NIGHT[k] or false
    slide.board = from == "game"
    -- Last frame is still on the canvases: the old screen's own picture, or
    -- the whole screen when the backdrop goes with it.
    love.graphics.setCanvas(slide.old)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(slide.shared and slide.front or S.ui, 0, 0)
    love.graphics.setCanvas()
    -- The press lit on the old screen does not follow it off.
    flair.pressed = nil
    slide.t0 = flair.now()
end

-- The pictures onto S.ui (the canvas up): the old one going, the new one
-- coming, or just the screen up.
function slide.compose()
    local e = slide.progress()
    love.graphics.setColor(1, 1, 1)
    if e then
        love.graphics.draw(slide.old, floor(-slide.dir * e * S.vw + 0.5), 0)
        love.graphics.draw(slide.front, floor(slide.dir * (1 - e) * S.vw + 0.5), 0)
    else
        love.graphics.draw(slide.front, 0, 0)
    end
end

return slide
