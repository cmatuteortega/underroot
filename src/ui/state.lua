-- The screen's state, shared by every part of it: the canvases and their
-- measures, the camera, the run being played and which screen is up, what the
-- pointer is over and what is in hand. One table, so the parts in src/ui/ can
-- each read and change it; the rules' own state is the Game (src/game.lua).

local D = require "src.defs"

local S = {}

S.SHORT = 240 -- game pixels across the short edge of the window
S.TOP, S.BOTTOM = 12, 32 -- the top strip, and room for the toolbar
S.ZOOM_STEPS = 4
S.TURN_TIME = 0.45 -- seconds the camera takes to go a quarter round

-- Two pictures, each at its own whole zoom. The board's zooms in and out
-- under the fingers; the HUD's (the strip, the toolbar, the words) never
-- changes with it, so a button is the same size at any zoom.
S.canvas, S.cw, S.ch, S.zoom = nil, nil, nil, nil -- the board
-- Board pixels the board's picture runs past each edge of the window: none,
-- except while a pinch may pull in what is off the screen.
S.pad = { l = 0, t = 0, r = 0, b = 0 }
S.ui, S.vw, S.vh, S.uz = nil, nil, nil, nil -- the HUD, and every screen measure the HUD lays out by
S.overlay, S.overlayImage, S.opx = nil, nil, nil
S.world, S.painter, S.progress = nil, nil, 0
S.game = nil
-- The levels: which one is being played, the boards already painted (one a
-- level, kept so a second run of it starts at once), and the level picker.
S.level = D.LEVELS[1]
S.worlds = {}
S.menu = nil -- the level picker is up (true), a level's loadout ("loadout"), or the title ("title")
S.pick = nil -- the loadout being picked: { n = level, set = { id = true }, enemy = kind }
S.chosen = nil -- the species the run brings, a list; nil brings them all (the shots)
S.challenge = false -- challenge mode chosen in the picker
S.camx, S.camy, S.panx, S.pany = 0, 0, 0, 0
S.mode = "grow"
S.drag = nil -- the node a link is being pulled from
S.tapped = nil -- the node just pressed: let go of it where it was, and it is selected
S.hover = {}
-- The pointer in HUD pixels (x, y) and window pixels (wx, wy).
S.mouse = { x = 0, y = 0, wx = 0, wy = 0 }
-- How far the HUD keeps in from each screen edge, in HUD pixels. None: the HUD
-- runs right to the border, notch and rounded corners and all, on a phone too.
S.inset = { l = 0, t = 0, r = 0, b = 0 }
-- Played with a finger: no hover, no right button, no keyboard. Set by the
-- last thing that pressed, so a tablet with a mouse plugged in reads the mouse.
S.touch = love.system.getOS() == "Android" or love.system.getOS() == "iOS"
S.press = nil -- a press on open ground: a tap if it is let go where it was, a pan if it moves
-- Whole zoom steps past the one that fits the board. A phone starts one in:
-- the board is a hand's width there, and a pocket wants to be a fingertip.
S.UI_STEP = S.touch and 1 or 0 -- the HUD's step, which stays put
S.zoomStep = S.UI_STEP
S.fingers, S.pinch = {}, nil -- the touches down, and the two being pinched
S.speed, S.paused = 1, false
-- The weather's word in the top strip, where the last HUD drawn put it:
-- { x, y, w, h, kind, next }. A finger has no hover, so a tap pins its tip
-- open (`weatherTip`, the kind) and a second tap shuts it.
S.weatherBox, S.weatherTip = nil, nil
S.heartFlash = 0
S.shake = 0 -- seconds of shaking left: a boss charging, a ball breaking
S.selected = nil -- the tower, mat or shelf whose upgrades are showing
S.peek = nil -- the species in hand whose panel the toolbar opened
-- The camera easing toward a selection: where panx, pany are headed, and what
-- they were sent there for (a new selection sends them again).
S.focus, S.focused = nil, nil
S.script = nil -- the --shots run
S.shot = nil -- and the whole screen it photographs
-- The camera going round: the frame it left, the screen point it turns about,
-- how far round and how long it has been at it.
S.turning = nil

-- To the level picker, with nothing in hand.
function S.openMenu()
    S.menu = true
    S.mode, S.drag, S.selected = "grow", nil, nil
end

-- A tap on nothing (no pocket, no plant, no thread, off the board) puts
-- everything down: the tool in hand, a thread being pulled, the selection.
function S.letGo()
    S.mode, S.drag, S.selected, S.peek = "grow", nil, nil, nil
end

return S
