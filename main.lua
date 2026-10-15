-- Underfoot: a tower defense where you are the mycelium under a sprout.
--
-- Everything renders into a low-res canvas scaled up by a whole number, in the
-- thirteen colours of src/palette.lua and nothing else. The board is traced
-- once into one big picture with a depth buffer behind it (src/world.lua).
-- Each frame the things that change -- hyphae, fruiting bodies, enemies, their
-- shadows, spores, corpses -- are laid over it a pixel at a time into an
-- overlay, each pixel kept only where it is nearer than the board there, in
-- painter's order. So an ant goes behind a slab of the patio and a thread of
-- hypha dips out of sight past a crumb with nothing traced but the ant.
--
-- This file is the screen: the canvas, the camera, compositing, the HUD and
-- what the mouse (or a finger) means. The rules are in src/game.lua and the numbers in
-- src/defs.lua.

local ffi = require "ffi"
local T = require "src.tracer"
local World = require "src.world"
local Game = require "src.game"
local D = require "src.defs"
local M = require "src.models"
local Font = require "src.font"

local floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt
local IDX = T.IDX

local SHORT = 240 -- game pixels across the short edge of the window
local TOP, BOTTOM = 12, 32

-- Two pictures, each at its own whole zoom. The board's zooms in and out
-- under the fingers; the HUD's (the strip, the toolbar, the words) never
-- changes with it, so a button is the same size at any zoom.
local canvas, cw, ch, zoom -- the board
local ui, vw, vh, uz -- the HUD, and every screen measure the HUD lays out by
local overlay, overlayImage, opx
local world, painter, progress = nil, nil, 0
local game
-- The levels: which one is being played, the boards already painted (one a
-- level, kept so a second run of it starts at once), and the level picker.
local level = D.LEVELS[1]
local worlds = {}
local menu -- the level picker is up
local challenge = false -- challenge mode chosen in the picker
local won = {} -- levels won, saved between runs: { crack = true, ... }

-- What has been won lives in the save directory, one level id a line.
local function loadProgress()
    won = {}
    local data = love.filesystem.getInfo("progress.txt") and love.filesystem.read("progress.txt")
    if data then for id in data:gmatch("%S+") do won[id] = true end end
end

local function saveProgress()
    local ids = {}
    for _, l in ipairs(D.LEVELS) do if won[l.id] then ids[#ids + 1] = l.id end end
    love.filesystem.write("progress.txt", table.concat(ids, "\n") .. "\n")
end

-- A level is open once the one before it is won; challenge mode once the last is.
local function levelOpen(n) return n == 1 or won[D.LEVELS[n - 1].id] end
local function challengeOpen() return won[D.LEVELS[#D.LEVELS].id] end
local camx, camy, panx, pany = 0, 0, 0, 0
local mode = "grow"
local drag -- the node a link is being pulled from
local dragAt -- where on the screen it was picked up
local hover = {}
-- The pointer in HUD pixels (x, y) and window pixels (wx, wy).
local mouse = { x = 0, y = 0, wx = 0, wy = 0 }
-- The safe area, in HUD pixels: a notch, a rounded corner or a home bar eats
-- into the window on a phone. The board runs under them; the HUD keeps out.
local inset = { l = 0, t = 0, r = 0, b = 0 }
-- Played with a finger: no hover, no right button, no keyboard. Set by the
-- last thing that pressed, so a tablet with a mouse plugged in reads the mouse.
local touch = love.system.getOS() == "Android" or love.system.getOS() == "iOS"
local press -- a press on open ground: a tap if it is let go where it was, a pan if it moves
-- Whole zoom steps past the one that fits the board. A phone starts one in:
-- the board is a hand's width there, and a pocket wants to be a fingertip.
local UI_STEP = touch and 1 or 0 -- the HUD's step, which stays put
local zoomStep = UI_STEP
local ZOOM_STEPS = 4
local fingers, pinch = {}, nil -- the touches down, and the two being pinched
local speed, paused = 1, false
local heartFlash = 0
local shake = 0 -- seconds of shaking left: a boss charging, a ball breaking
local selected -- the tower, mat or shelf whose upgrades are showing
local script -- the --shots run
local shot -- and the whole screen it photographs

--- the screen ----------------------------------------------------------------------

local function fit()
    local w, h = love.graphics.getDimensions()
    local base = max(1, floor(min(w, h) / SHORT))
    uz = base + UI_STEP
    vw, vh = ceil(w / uz), ceil(h / uz)
    ui = love.graphics.newCanvas(vw, vh)
    ui:setFilter("nearest", "nearest")
    local sx, sy, sw, sh = love.window.getSafeArea()
    inset.l, inset.t = ceil(sx / uz), ceil(sy / uz)
    inset.r, inset.b = ceil((w - sx - sw) / uz), ceil((h - sy - sh) / uz)

    zoom = base + zoomStep
    cw, ch = ceil(w / zoom), ceil(h / zoom)
    canvas = love.graphics.newCanvas(cw, ch)
    canvas:setFilter("nearest", "nearest")
    -- The overlay is one byte-for-byte picture of everything laid over the board
    -- this frame: a pixel is either covered, fully, or not there. Painter's order
    -- is simply the order things are put.
    overlay = love.image.newImageData(cw, ch, "rgba8")
    opx = ffi.cast("uint8_t*", overlay:getFFIPointer())
    overlayImage = love.graphics.newImage(overlay)
    overlayImage:setFilter("nearest", "nearest")
end

-- HUD pixels to board pixels: what the strip and toolbar cover of the board.
local function toBoard(u) return u * uz / zoom end
-- A board-image pixel to the HUD pixel over it.
local function toHud(i, j)
    return floor((i - floor(camx)) * zoom / uz), floor((j - floor(camy)) * zoom / uz)
end

function love.resize() fit() end
function love.displayrotated() fit() end

-- Sent to the background (a call, the home button): stop the clock rather
-- than let a wave run on unwatched.
function love.focus(f)
    if not f and not script and game then paused = true end
end

local RGB8 = {}
for k, c in ipairs(T.RGB) do RGB8[k] = { floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5) } end

-- Put key k at screen pixel (x, y).
local function putS(k, x, y)
    if k == 0 or x < 0 or y < 0 or x >= cw or y >= ch then return end
    local p = (y * cw + x) * 4
    local c = RGB8[k]
    opx[p], opx[p + 1], opx[p + 2], opx[p + 3] = c[1], c[2], c[3], 255
end
-- Put key k at board-image pixel (i, j).
local function put(k, i, j) putS(k, floor(i - floor(camx)), floor(j - floor(camy))) end

-- Put the board's own pixel back at board-image pixel (i, j), a step darker if
-- `dark`. A tiled board is colours, not keys: darker is a shade, not a ramp step.
local function putGround(i, j, dark)
    local n = j * world.w + i
    if not world.rgb then return put(dark and T.DARKER[world.key[n]] or world.key[n], i, j) end
    local x, y = floor(i - floor(camx)), floor(j - floor(camy))
    if x < 0 or y < 0 or x >= cw or y >= ch then return end
    local p, f = (y * cw + x) * 4, dark and 0.6 or 1
    local rgb = world.rgb
    opx[p], opx[p + 1], opx[p + 2], opx[p + 3] = rgb[n * 3] * f, rgb[n * 3 + 1] * f, rgb[n * 3 + 2] * f, 255
end

-- Is room depth d nearer than the board at image pixel (i, j)?
local function visible(i, j, d)
    if i < 0 or j < 0 or i >= world.w or j >= world.h then return true end
    return d >= world.dep[j * world.w + i] - 0.6
end

-- A picture laid down with its pivot at a room point, through a remap.
local function stamp(pic, x, y, z, remap)
    remap = remap or T.SAME
    local si, sj, d = world:toImage(x, y, z)
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
    local g = world:groundAt(x, z)
    local i0 = floor(world:toImage(x - r, g, z + r)) - 1
    local i1 = ceil(world:toImage(x + r, g, z - r)) + 1
    local _, j0 = world:toImage(x - r, g + 4, z - r)
    local _, j1 = world:toImage(x + r, g - 1, z + r)
    for j = max(0, floor(j0)), min(world.h - 1, ceil(j1)) do
        for i = max(0, i0), min(world.w - 1, i1) do
            local n = j * world.w + i
            if world.up[n] == 1 and (world.wx[n] - x) ^ 2 + (world.wz[n] - z) ^ 2 <= r * r then
                putGround(i, j, true)
            end
        end
    end
end

-- A line plotted through the room, a pixel at a time, depth tested along it.
local function line3(x0, y0, z0, x1, y1, z1, k)
    local i0, j0, d0 = world:toImage(x0, y0, z0)
    local i1, j1, d1 = world:toImage(x1, y1, z1)
    local steps = max(1, ceil(max(abs(i1 - i0), abs(j1 - j0))))
    for s = 0, steps do
        local t = s / steps
        local i, j = floor(i0 + (i1 - i0) * t), floor(j0 + (j1 - j0) * t)
        if visible(i, j, d0 + (d1 - d0) * t + 1) then put(k, i, j) end
    end
end

local function members(set)
    local k = 0
    for _ in pairs(set or {}) do k = k + 1 end
    return k
end

-- A ring on the ground: a tower's reach.
local function ring(x, z, r, k, dash)
    local n = max(24, floor(r * 1.6))
    for s = 0, n - 1 do
        if not dash or s % 2 == 0 then
            local a = s / n * 2 * math.pi
            local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
            local i, j, d = world:toImage(px, world:groundAt(px, pz) + 0.3, pz)
            if visible(floor(i), floor(j), d + 1) then put(k, i, j) end
        end
    end
end

--- the board's camera ----------------------------------------------------------------

local function centre()
    local l, r = toBoard(inset.l), toBoard(inset.r)
    local top, bottom = toBoard(inset.t + TOP), toBoard(inset.b + BOTTOM)
    camx = floor((world.w - (cw - l - r)) / 2 - l) + panx
    camy = floor((world.h - (ch - top - bottom)) / 2 - top) + pany
end

-- The board-image pixel under the mouse.
local function cursor()
    return floor(mouse.wx / zoom) + floor(camx), floor(mouse.wy / zoom) + floor(camy)
end

--- what the mouse is over ------------------------------------------------------------

local BUTTONS = {
    { mode = "grow", key = "1", name = "GROW HYPHAE", blurb = "DRAG FROM A FED NODE TO A POCKET. COST GROWS WITH LENGTH" },
}
for _, t in ipairs(D.TOWERS) do
    BUTTONS[#BUTTONS + 1] = { mode = t.id, key = t.key, name = t.name, blurb = t.blurb, cost = t.cost, tower = true }
end
BUTTONS[#BUTTONS + 1] = { mode = "prune", key = "X", name = "PRUNE", blurb = "CUT YOUR OWN LINK (HALF BACK) OR CLEAR A TOWER" }
BUTTONS[#BUTTONS + 1] = { mode = "pulse", key = "Q", name = "SPORE PULSE",
    blurb = "PICK A FED NODE: EVERY TOWER ON THE WAY THERE OVERCHARGES" }

-- The toolbar sits in the safe area along the bottom with the wave button at
-- its end. A screen too narrow for both (a phone held upright) narrows the
-- buttons first and then lifts the wave button onto a row of its own, at the
-- right, where a thumb is.
-- Too narrow even for that, the tools go onto two rows.
local BH, WW = 27, 44
local function bar()
    local avail = vw - inset.l - inset.r - 4
    local n = #BUTTONS
    local y = vh - inset.b - BH - 3
    local bw = min(30, floor((avail - 8 - WW + 2) / n) - 2)
    if bw >= 22 then
        local tools = n * (bw + 2) - 2
        local x0 = inset.l + 2 + floor((avail - tools - 8 - WW) / 2)
        return { rows = { { x0 = x0, y = y, from = 1, to = n } }, bw = bw, wx = x0 + tools + 8, wy = y, top = y }
    end
    bw = min(30, floor((avail + 2) / n) - 2)
    if bw >= 22 then
        local tools = n * (bw + 2) - 2
        local x0 = inset.l + 2 + floor((avail - tools) / 2)
        return { rows = { { x0 = x0, y = y, from = 1, to = n } }, bw = bw, wx = vw - inset.r - 2 - WW, wy = y - BH - 4, top = y - BH - 4 }
    end
    local per = ceil(n / 2)
    bw = min(30, floor((avail + 2) / per) - 2)
    local x0 = inset.l + 2 + floor((avail - (per * (bw + 2) - 2)) / 2)
    local y1 = y - BH - 3
    return { rows = { { x0 = x0, y = y1, from = 1, to = per }, { x0 = x0, y = y, from = per + 1, to = n } },
        bw = bw, wx = vw - inset.r - 2 - WW, wy = y1 - BH - 4, top = y1 - BH - 4 }
end
local function buttonRect(n)
    local b = bar()
    for _, r in ipairs(b.rows) do
        if n >= r.from and n <= r.to then return r.x0 + (n - r.from) * (b.bw + 2), r.y, b.bw, BH end
    end
end
local function waveRect()
    local b = bar()
    return b.wx, b.wy, WW, BH
end
-- The top of everything the toolbar puts down: the tip line sits above it.
local function barTop() return bar().top end
local function inside(x, y, rx, ry, rw, rh) return x >= rx and y >= ry and x < rx + rw and y < ry + rh end

-- The upgrade panel over the toolbar: a card for each upgrade open to
-- whatever is selected (two at the fork, one after, none at the top).
local CW, CH = 100, 24
local function panelCards()
    if not selected then return {} end
    local ups = game:upgrades(selected)
    local n = max(1, #ups)
    local total = n * CW + (n - 1) * 4
    local x0 = floor((vw - total) / 2)
    local y = barTop() - 5 - CH
    local cards = {}
    for k = 1, n do cards[k] = { x = x0 + (k - 1) * (CW + 4), y = y, w = CW, h = CH, up = ups[k] } end
    return cards
end

-- The mutation picker: three cards across the middle, or down it on a narrow screen.
local MW, MH = 118, 40
local function mutationCards()
    local list = game.choices or {}
    local n = #list
    local cards = {}
    if vw - inset.l - inset.r >= n * MW + (n - 1) * 6 + 8 then
        local x0 = floor((vw - (n * MW + (n - 1) * 6)) / 2)
        for k = 1, n do cards[k] = { x = x0 + (k - 1) * (MW + 6), y = floor(vh / 2) - 18, w = MW, h = MH, m = list[k] } end
    else
        local y0 = floor(vh / 2 - (n * MH + (n - 1) * 4) / 2)
        for k = 1, n do cards[k] = { x = floor((vw - MW) / 2), y = y0 + (k - 1) * (MH + 4), w = MW, h = MH, m = list[k] } end
    end
    return cards
end

-- The level picker: a card a level, across the middle (or down it on a
-- narrow screen), and the challenge switch under them once it is open.
local LW, LH = 124, 50
local function levelCards()
    local n = #D.LEVELS
    local cards = {}
    local y0
    if vw - inset.l - inset.r >= n * LW + (n - 1) * 6 + 8 then
        local x0 = floor((vw - (n * LW + (n - 1) * 6)) / 2)
        y0 = floor(vh / 2) - 30
        for k = 1, n do cards[k] = { x = x0 + (k - 1) * (LW + 6), y = y0, w = LW, h = LH, n = k } end
        y0 = y0 + LH + 8
    else
        y0 = floor(vh / 2 - (n * LH + (n - 1) * 4) / 2) - 8
        for k = 1, n do cards[k] = { x = floor((vw - LW) / 2), y = y0 + (k - 1) * (LH + 4), w = LW, h = LH, n = k } end
        y0 = y0 + n * (LH + 4) + 4
    end
    local switch = { x = floor((vw - LW) / 2), y = y0, w = LW, h = 16, challenge = true }
    return cards, switch
end

local function nodeScreen(n)
    local i, j = world:toImage(n.x, n.y + (n.heart and 10 or 5), n.z)
    return i, j
end

local function findHover()
    hover = {}
    local mx, my = mouse.x, mouse.y
    if menu then
        local cards, switch = levelCards()
        for k, c in ipairs(cards) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then hover.level = k return end
        end
        if challengeOpen() and inside(mx, my, switch.x, switch.y, switch.w, switch.h) then hover.challenge = true end
        return
    end
    if game.phase == "mutate" then
        for k, c in ipairs(mutationCards()) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then hover.mutation = k return end
        end
    end
    for k, c in ipairs(panelCards()) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then hover.card = k return end
    end
    for n = 1, #BUTTONS do
        if inside(mx, my, buttonRect(n)) then hover.button = n return end
    end
    if inside(mx, my, waveRect()) then hover.wave = true return end
    if my < inset.t + TOP then hover.strip = true return end
    local ci, cj = cursor()
    local best, bd = nil, 9
    for _, n in ipairs(game.nodes) do
        local i, j = nodeScreen(n)
        local d = sqrt((i - ci) ^ 2 + (j - cj) ^ 2)
        if d < bd then best, bd = n, d end
    end
    hover.node = best
    local x, _, z = world:pick(ci, cj)
    if x then
        hover.x, hover.z = x, z
        hover.c, hover.r = floor(x / World.TILE), floor(z / World.TILE)
        hover.mat = game:matAt(hover.c, hover.r)
    end
    if not best then
        local bl, bdist = nil, 3.5
        for _, l in ipairs(game.links) do
            local ai, aj = world:toImage(l.a.x, l.a.y, l.a.z)
            local bi, bj = world:toImage(l.b.x, l.b.y, l.b.z)
            local d = Game.segDist(ci, cj, ai, aj, bi, bj)
            if d < bdist then bl, bdist = l, d end
        end
        hover.link = bl
    end
end

--- the run ---------------------------------------------------------------------------

local function start()
    game = Game.new(world, level, { challenge = challenge })
    mode, drag, panx, pany, selected = "grow", nil, 0, 0, nil
    paused, speed = false, 1
    menu = nil
end

-- Plays level `n`: its board if it is painted already, else paint it first.
local function play(n)
    level = D.LEVELS[n]
    menu = nil
    if worlds[level.id] then
        world = worlds[level.id]
        start()
        return
    end
    world = World.new(level.map)
    worlds[level.id] = world
    progress = 0
    painter = coroutine.create(function() world:paint() end)
end

local function openMenu()
    menu = true
    mode, drag, selected = "grow", nil, nil
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    fit()
    loadProgress()
    for _, a in ipairs(args or {}) do
        if a == "--shots" then script = require("src.script") end
        if a == "--bot" then
            function love.errorhandler(msg) print("ERROR", msg, debug.traceback()) os.exit(1) end
            local rest = {}
            for k = 1, #args do if args[k] ~= "--bot" then rest[#rest + 1] = args[k] end end
            require("src.bot").run(rest)
            return
        end
        if a == "--sheet" then
            -- No one is watching: an error should say so and stop.
            function love.errorhandler(msg) print("ERROR", msg, debug.traceback()) os.exit(1) end
            require("src.sheet").run()
            return
        end
    end
    if script then
        -- The script plays the level it is told to (--shots pond), or the first.
        local n = 1
        for _, a in ipairs(args or {}) do
            for k, l in ipairs(D.LEVELS) do if a == l.id then n = k end end
        end
        script.level = D.LEVELS[n].id
        for _, a in ipairs(args or {}) do if a == "challenge" then challenge = true end end
        play(n)
    else
        openMenu()
    end
end

local function click(b)
    if menu then
        if hover.level and levelOpen(hover.level) then play(hover.level)
        elseif hover.challenge then challenge = not challenge end
        return
    end
    if b == 2 then
        mode, drag, selected = "grow", nil, nil
        return
    end
    if game.phase == "mutate" then
        -- The picker holds the game until a mutation is chosen.
        if hover.mutation then game:mutate(hover.mutation) end
        return
    end
    if hover.card then
        local c = panelCards()[hover.card]
        if c and c.up then game:upgrade(selected, c.up.branch) end
        return
    end
    if hover.button then
        -- The tool already in hand, picked again, is put down: the one way to
        -- cancel there is without a right button. A species not yet unlocked
        -- stays in its slot, dark.
        local bt = BUTTONS[hover.button]
        if bt.tower and not game:unlocked(bt.mode) then return end
        local m = bt.mode
        mode, drag = (m == mode and m ~= "grow") and "grow" or m, nil
        if mode ~= "grow" then selected = nil end
        return
    end
    if hover.wave then
        if game.phase == "build" then game:startWave() else speed = speed % 3 + 1 end
        return
    end
    if game.phase == "won" or game.phase == "lost" then openMenu() return end
    if hover.strip then
        -- No P key on a phone: the top strip is the pause button.
        if touch then paused = not paused end
        return
    end
    if mode == "grow" then
        if hover.node then
            if drag and drag ~= hover.node then
                game:grow(drag, hover.node)
                drag, selected = nil, nil
            else
                -- A tower is picked up as the end of a thread and shows its upgrades.
                drag, selected = hover.node, hover.node.tower
            end
        elseif hover.link and hover.link.state == "cut" then
            game:repair(hover.link)
        elseif hover.mat then
            drag, selected = nil, hover.mat
        else
            drag, selected = nil, nil
        end
    elseif mode == "prune" then
        if hover.node and hover.node.tower then
            game:sell(hover.node)
        elseif hover.link then
            game:prune(hover.link)
        elseif hover.mat then
            game:liftMat(hover.mat)
        end
    elseif D.TOWER[mode] and D.TOWER[mode].onTrail then
        if hover.c then
            local m = game:lay(mode, hover.c, hover.r)
            if m then selected = m end
        end
    elseif mode == "pulse" then
        if hover.node and game:pulse(hover.node) then mode = "grow" end
    else
        if hover.node then
            local t = game:build(mode, hover.node)
            if t then selected = t end
        end
    end
end

-- A press on a button or a node acts at once, so a thread can be pulled from
-- a node in one drag. A press anywhere else waits to see what it is: let go
-- where it was and it is a click there; moved first and it pans the board, which
-- is the only way to pan with one finger.
local SLOP = 3 -- HUD pixels a tap may wander and still be a tap

local function point(x, y)
    mouse.wx, mouse.wy = x, y
    mouse.x, mouse.y = floor(x / uz), floor(y / uz)
end

function love.mousepressed(x, y, b, istouch)
    if painter or pinch then return end
    touch = istouch and true or false
    point(x, y)
    findHover()
    if b == 3 then mouse.pan = { wx = x, wy = y, px = panx, py = pany } return end
    if b == 1 and not (hover.button or hover.wave or hover.node or hover.card or hover.mutation) and not (mode == "grow" and drag) then
        press = { x = mouse.x, y = mouse.y, wx = x, wy = y, px = panx, py = pany }
        return
    end
    local was = drag
    click(b)
    if drag and drag ~= was then dragAt = { x = mouse.x, y = mouse.y } end
end

function love.mousereleased(x, y, b, istouch)
    if painter then return end
    if pinch then press = nil return end
    if b == 3 then mouse.pan = nil return end
    point(x, y)
    if b == 1 and press then
        local p = press
        press = nil
        if p.moved then return end
        -- The click lands where the press was, not wherever a finger rolled to.
        point(p.wx, p.wy)
        findHover()
        click(1)
        return
    end
    findHover()
    -- Pulled from one node and let go over another: that is a link too.
    if b == 1 and mode == "grow" and drag and hover.node and hover.node ~= drag then
        game:grow(drag, hover.node)
        drag = nil
    elseif b == 1 and istouch and mode == "grow" and drag and not hover.node and not hover.button then
        -- A thread pulled out on a phone and dropped on bare ground was not
        -- meant: with no right button to cancel, letting go cancels.
        if dragAt and (abs(mouse.x - dragAt.x) > SLOP or abs(mouse.y - dragAt.y) > SLOP) then drag = nil end
    end
end

function love.mousemoved(x, y)
    point(x, y)
    if pinch then return end
    local pan = mouse.pan or press
    if press and not press.moved and (abs(mouse.x - press.x) > SLOP or abs(mouse.y - press.y) > SLOP) then
        press.moved = true
    end
    if pan and (pan == mouse.pan or press.moved) then
        -- In board pixels: the ground stays under the finger at any zoom.
        panx = pan.px - floor((x - pan.wx) / zoom)
        pany = pan.py - floor((y - pan.wy) / zoom)
    end
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
    local lo, hi = stepRange()
    zoomStep = max(lo, min(hi, step))
    fit()
    centre()
    panx = panx + (bx - sx / zoom) - camx
    pany = pany + (by - sy / zoom) - camy
    centre()
    point(sx, sy)
end

-- One step in or out about a window pixel (the cursor, or the middle).
local function zoomBy(d, sx, sy)
    local lo, hi = stepRange()
    if painter or zoomStep + d < lo or zoomStep + d > hi then return end
    sx, sy = sx or love.graphics.getWidth() / 2, sy or love.graphics.getHeight() / 2
    zoomTo(zoomStep + d, sx / zoom + camx, sy / zoom + camy, sx, sy)
end

function love.wheelmoved(_, y)
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
    local a, b = fingers[pinch.a], fingers[pinch.b]
    return sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2), (a.x + b.x) / 2, (a.y + b.y) / 2
end

function love.touchpressed(id, x, y)
    fingers[id] = { x = x, y = y }
    if pinch or painter then return end
    local ids = {}
    for k in pairs(fingers) do ids[#ids + 1] = k end
    if #ids == 2 then
        pinch = { a = ids[1], b = ids[2], s = 1 }
        local d, mx, my = spread()
        pinch.d0, pinch.x0, pinch.y0, pinch.x, pinch.y = max(d, 1), mx, my, mx, my
        if press then panx, pany = press.px, press.py; centre() end
        press, drag = nil, nil
    end
end

function love.touchmoved(id, x, y)
    if not fingers[id] then return end
    fingers[id].x, fingers[id].y = x, y
    if pinch and not pinch.done then
        local d, mx, my = spread()
        local lo, hi = stepRange()
        local base = zoom - zoomStep
        -- Held to what it can settle on, give or take half a step.
        pinch.s = max((base + lo - 0.45) / zoom, min((base + hi + 0.45) / zoom, d / pinch.d0))
        pinch.x, pinch.y = mx, my
    end
end

function love.touchreleased(id)
    if pinch and not pinch.done and (id == pinch.a or id == pinch.b) then
        local bx, by = pinch.x0 / zoom + camx, pinch.y0 / zoom + camy
        local step = floor(zoom * pinch.s + 0.5) - (zoom - zoomStep)
        zoomTo(step, bx, by, pinch.x, pinch.y)
        pinch.done = true
    end
    fingers[id] = nil
    if not next(fingers) then pinch = nil end
end

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen())
        fit()
        return
    end
    if painter then return end
    if menu then
        local n = tonumber(key)
        if n and D.LEVELS[n] and levelOpen(n) then play(n) end
        if key == "c" and challengeOpen() then challenge = not challenge end
        if key == "escape" and game then menu = nil end
        return
    end
    if key == "=" or key == "+" or key == "kp+" then zoomBy(1) end
    if key == "-" or key == "kp-" then zoomBy(-1) end
    if game.phase == "mutate" then
        local n = tonumber(key)
        if n then game:mutate(n) end
        return
    end
    if key == "escape" then
        -- Never quits: one key too many and a run is gone. The window's close does that.
        if drag or mode ~= "grow" or selected then mode, drag, selected = "grow", nil, nil else paused = not paused end
    end
    for _, b in ipairs(BUTTONS) do
        if key == b.key:lower() and not (b.tower and not game:unlocked(b.mode)) then mode, drag, selected = b.mode, nil, nil end
    end
    if (key == "z" or key == "c") and selected then
        local cards = panelCards()
        local c = cards[key == "z" and 1 or #cards]
        if c and c.up then game:upgrade(selected, c.up.branch) end
    end
    if key == "space" then
        if game.phase == "build" then game:startWave() end
    end
    if key == "f" then speed = speed % 3 + 1 end
    if key == "p" then paused = not paused end
    if key == "r" and (game.phase == "won" or game.phase == "lost" or love.keyboard.isDown("lshift")) then start() end
    if key == "m" then openMenu() end
    -- Won: on to the next level.
    if key == "n" and game.phase == "won" then
        for k, l in ipairs(D.LEVELS) do
            if l == level and D.LEVELS[k + 1] then play(k + 1) return end
        end
    end
end

function love.update(dt)
    if painter then
        local t0 = love.timer.getTime()
        -- Paint in slices, so the window keeps answering while the board goes down.
        while coroutine.status(painter) ~= "dead" and love.timer.getTime() - t0 < 1 / 30 do
            local ok, p = coroutine.resume(painter)
            if not ok then error(p) end
            progress = p or 1
        end
        if coroutine.status(painter) == "dead" then
            painter = nil
            start()
            if script then
                -- The script clicks like a player: it is told where things are
                -- in window pixels.
                script.begin(game, {
                    at = function(x, y, z)
                        local i, j = world:toImage(x, y, z)
                        return (floor(i) - floor(camx) + 0.5) * zoom, (floor(j) - floor(camy) + 0.5) * zoom
                    end,
                    select = function(t) selected = t end,
                    menu = function(on) if on then openMenu() else menu = nil end end,
                    button = function(name)
                        for n, b in ipairs(BUTTONS) do
                            if b.mode == name then
                                local x, y, w, h = buttonRect(n)
                                return (x + w / 2) * uz, (y + h / 2) * uz
                            end
                        end
                    end,
                })
            end
        end
        return
    end
    -- The shots are the whole screen: the board with the HUD laid over it
    -- (or the picker, which is all HUD). The script never zooms, so the two
    -- pictures are the same size.
    local function photograph()
        if not shot or shot:getWidth() ~= cw or shot:getHeight() ~= ch then shot = love.graphics.newCanvas(cw, ch) end
        love.graphics.setCanvas(shot)
        love.graphics.setColor(1, 1, 1)
        if not menu then love.graphics.draw(canvas) end
        love.graphics.draw(ui)
        love.graphics.setCanvas()
        script.after(game, shot)
    end
    if menu then
        findHover()
        if script then
            script.update(game, 1 / 30)
            photograph()
        end
        return
    end
    dt = min(dt, 1 / 30)
    if script then dt = 1 / 30 end

    local k = love.keyboard.isDown
    local pan = 120 * dt
    if k("left", "a") then panx = panx - pan end
    if k("right", "d") then panx = panx + pan end
    if k("up", "w") then pany = pany - pan end
    if k("down", "s") then pany = pany + pan end
    -- Zoomed in, the board is bigger than the screen: let every edge of it be
    -- reached, with a little ground to spare.
    local limx = max(40, (world.w - (cw - toBoard(inset.l + inset.r))) / 2 + 40)
    local limy = max(60, (world.h - (ch - toBoard(inset.t + inset.b + TOP + BOTTOM))) / 2 + 40)
    panx, pany = max(-limx, min(limx, panx)), max(-limy, min(limy, pany))
    centre()

    if script then script.update(game, dt) end
    findHover()
    if not paused then
        for _ = 1, speed do
            game:update(dt)
            if game.events.heart then heartFlash = 0.15 end
            if game.events.shake then shake = max(shake, game.events.shake) end
        end
    end
    heartFlash = max(0, heartFlash - dt)
    shake = max(0, shake - dt)
    if game.phase == "won" and not game.recorded then
        game.recorded = true
        if not script then
            won[level.id] = true
            saveProgress()
        end
    end
    -- What was selected may have been eaten, sterilised, sold or flattened.
    if selected then
        local gone
        if selected.node then gone = selected.node.tower ~= selected
        else
            gone = true
            for _, m in ipairs(game.mats) do if m == selected then gone = false end end
        end
        if gone then selected = nil end
    end
    if script then photograph() end
end

--- drawing the world -------------------------------------------------------------------

-- It never sags below the lower of its two ends' ground, so a thread between
-- two pockets on the field bridges a sunken trail or the pond rather than
-- dropping into it; one to a lily pad still comes down to the water.
local function linkY(l, f, x, z)
    local g = max(world:groundAt(x, z), min(0, l.a.y, l.b.y)) + 0.4
    local e = min(f, 1 - f) * l.len
    local ny = f < 0.5 and l.a.y or l.b.y
    return max(g, ny - e * 0.5)
end

-- A thread of hypha: two pixels deep so it reads as a thread and not a line,
-- with the nutrients in it shown as pulses running away from the Heart.
local function drawLink(l, highlight)
    local a, b = l.a, l.b
    local steps = max(2, ceil(l.len / 0.5))
    local up = a.hop <= b.hop -- which end the flow comes from
    local fed = l.state == "alive" and a.conn
    local t = game.clock
    local core, under = IDX.c, IDX.d
    if l.state == "alive" and not fed then core, under = IDX.d, IDX.u end
    if highlight then core = highlight end
    local surge = l.surge and l.state == "alive"
    if surge then core, under = IDX.l, IDX.c end
    local hurt = l.state == "alive" and l.hp < game:linkHp() * 0.5
    local gap0, gap1 = 2, -1 -- the part of a cut link that is not there
    if l.state == "cut" then
        local open = 0.7 * (1 - min(1, l.regrow))
        gap0, gap1 = 0.5 - open / 2, 0.5 + open / 2
    end
    for s = 0, steps do
        local f = s / steps
        local draw = true
        if l.state == "grow" then draw = f <= l.grow end
        if f > gap0 and f < gap1 then draw = false end
        if draw then
            local x, z = a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
            local i, j, d = world:toImage(x, linkY(l, f, x, z), z)
            i, j = floor(i), floor(j)
            if visible(i, j, d + 1.5) then
                local k = core
                if l.state == "cut" then
                    k = l.salted and IDX.w or (l.hand or l.regrow > 0) and IDX.c or IDX.n
                    if abs(f - gap0) < 0.03 or abs(f - gap1) < 0.03 then k = IDX.r end
                elseif l.state == "grow" and abs(f - l.grow) < 0.04 then
                    k = IDX.l
                elseif fed and not highlight then
                    local along = (up and f or 1 - f) * l.len
                    if surge then
                        if (along - t * 60) % 8 < 2 then k = IDX.w end
                    elseif (along - t * 18) % 12 < 1.3 then
                        k = IDX.l
                    end
                end
                if hurt and s % 5 == 0 and floor(t * 6) % 2 == 0 then k = IDX.r end
                put(under, i, j + 1)
                if l.thick then put(under, i, j + 2) end
                put(k, i, j)
                if l.thick then put(k, i, j + 1) end
            end
        end
    end
end

local MOSS = {}
for k = 1, #T.KEYS do MOSS[k] = k end
MOSS[IDX.n], MOSS[IDX.t], MOSS[IDX.u] = IDX.d, IDX.m, IDX.d

local function drawRing(r)
    local poly = r.nodes
    local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
    for _, n in ipairs(poly) do x0, x1, z0, z1 = min(x0, n.x), max(x1, n.x), min(z0, n.z), max(z1, n.z) end
    local i0 = floor(world:toImage(x0, 0, z1)) - 1
    local i1 = ceil(world:toImage(x1, 0, z0)) + 1
    local _, j0 = world:toImage(x0, 4, z0)
    local _, j1 = world:toImage(x1, 0, z1)
    for j = max(0, floor(j0)), min(world.h - 1, ceil(j1)) do
        for i = max(0, i0), min(world.w - 1, i1) do
            local n = j * world.w + i
            if world.up[n] == 1 and world.wy[n] < 1 and Game.inPoly(poly, world.wx[n], world.wz[n]) then
                local k = world.key[n]
                if MOSS[k] ~= k and (i + j) % 2 == 0 then put(MOSS[k], i, j) end
            end
        end
    end
    for s = 1, #poly do
        local a, b = poly[s], poly[s % #poly + 1]
        local len = sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
        for u = 3, len - 3, 5 do
            local f = u / len
            -- Set in from the thread a little, so the caps stand inside the ring.
            local cx = a.x + (b.x - a.x) * f
            local cz = a.z + (b.z - a.z) * f
            local i, j, d = world:toImage(cx, world:groundAt(cx, cz) + 1, cz)
            i, j = floor(i), floor(j) - 2
            if visible(i, j, d + 2) then put(IDX.t, i, j + 1); put(IDX.w, i, j) end
        end
    end
end

local function knot(n, k)
    local i, j = world:toImage(n.x, n.y + 0.5, n.z)
    i, j = floor(i), floor(j)
    put(IDX.d, i - 1, j + 1); put(IDX.d, i + 1, j + 1); put(IDX.d, i, j + 2)
    put(k, i - 1, j); put(k, i + 1, j); put(k, i, j - 1); put(k, i, j + 1); put(IDX.l, i, j)
end

local function bar(x, y, z, frac, k)
    local i, j = world:toImage(x, y, z)
    i, j = floor(i) - 4, floor(j)
    for n = -1, 8 do put(IDX.o, i + n, j - 1); put(IDX.o, i + n, j + 1) end
    put(IDX.o, i - 1, j); put(IDX.o, i + 8, j)
    for n = 0, 7 do put(n < floor(frac * 8 + 0.5) and k or IDX.u, i + n, j) end
end

-- A fruiting body's picture this frame: its look, breathing on its own beat,
-- kicking when it fires, coming up out of the ground when new.
local function towerLook(t, seed)
    local idle = (game.clock * 0.7 + seed * 0.37) % 1
    return M.tower(t.kind, t.branch, t.tier, idle, t.squash, t.grown)
end

-- A fruiting body flat on a button or a card. The Humongous Fungus is shown
-- as it is coming up, or it would not fit.
local function icon(kind, branch, tier, idle)
    return M.tower(kind, branch, tier, idle, 0, kind == "giant" and 0.34 or nil)
end

local function remapFor(t)
    if t.hunger == "dormant" then return T.DARKER2 end
    if t.hunger == "starved" or (t.webbed or 0) > 0 or (t.stun or 0) > 0 then return T.DARKER end
end

-- A cordyceps host is laid down in the fungus's colours.
local INFECT = {}
do
    local map = { w = "w", t = "t", s = "t", l = "t", c = "r", m = "t", g = "t", d = "r", k = "n", n = "n", u = "u", r = "r", o = "o" }
    for k, key in ipairs(T.KEYS) do INFECT[k] = IDX[map[key]] end
end

local function enemyPicture(e)
    local k = e.kind
    if k == "ant" then
        local rate = (e.state == "chew" or e.state == "gnawShelf") and 14 or 8
        return M.ant(e.h, floor(e.anim * rate) % 2)
    elseif k == "pillbug" then
        if e.rolling then return M.pillbug(e.h, true, floor(e.anim * 12) % 4) end
        return M.pillbug(e.h, false)
    elseif k == "mite" then
        return M.mite(e.h)
    elseif k == "gnat" then
        return M.gnat(e.h, floor(e.anim * 20) % 2)
    elseif k == "slug" then
        return M.slug(e.h, floor(e.anim * (e.state == "eat" and 4 or 2)) % 2)
    elseif k == "spider" then
        return M.spider(e.h, floor(e.anim * 10) % 2)
    elseif k == "knight" then
        return M.knight(e.h, floor(e.anim * 6) % 2)
    elseif k == "queen" then
        return M.queen(e.h, floor(e.anim * 5) % 2)
    elseif k == "stag" then
        return M.stag(e.h, floor(e.anim * (e.charging and 14 or 6)) % 2, e.charging ~= nil)
    elseif k == "dung" then
        -- It walks backwards, pushing: its picture faces away from the way it goes.
        return M.dung(e.h + math.pi, floor(e.anim * 5) % 2)
    elseif k == "moth" then
        return M.moth(e.h, floor(e.anim * 12) % 2)
    elseif k == "waterbug" then
        return M.waterbug(e.h, floor(e.anim * 5) % 2, e.state == "grab" or e.state == "lunge")
    elseif k == "centipede" then
        return M.centipede(e.h, floor(e.anim * 8) % 2)
    elseif k == "centseg" then
        return M.centseg(e.h, floor(e.anim * 8 + (e.x + e.z) * 0.1) % 2)
    elseif k == "bombardier" then
        return M.bombardier(e.h, floor(e.anim * 6) % 2, e.state == "siege")
    end
    return M.brine(floor(e.anim * 4) % 2)
end

local SHADOW = { ant = 4, pillbug = 4.5, brine = 3.5, gnat = 2.5, slug = 6, spider = 5, knight = 5,
    queen = 11, stag = 13, dung = 10, moth = 3.5, waterbug = 12, centipede = 6, centseg = 5.5, bombardier = 10 }

-- Something under the water: rings spreading on the surface where it is.
local function ripples(x, z, t)
    for ring = 0, 1 do
        local r = 5 + ((t * 6 + ring * 5) % 10)
        local n = floor(r * 2.4)
        for s = 0, n - 1 do
            if (s + ring) % 2 == 0 then
                local a = s / n * 2 * math.pi
                local px, pz = x + math.cos(a) * r, z + math.sin(a) * r * 0.9
                local i, j, d = world:toImage(px, world:groundAt(px, pz) + 0.2, pz)
                if visible(floor(i), floor(j), d + 1) then put(r < 9 and IDX.w or IDX.s, i, j) end
            end
        end
    end
end

-- A pool of a lamp's light at night: the ground in it is its daytime self again.
local function lightPool(x, z, r)
    local g = world:groundAt(x, z)
    local i0 = floor(world:toImage(x - r, g, z + r)) - 1
    local i1 = ceil(world:toImage(x + r, g, z - r)) + 1
    local _, j0 = world:toImage(x - r, g + 6, z - r)
    local _, j1 = world:toImage(x + r, g - 1, z + r)
    for j = max(0, floor(j0)), min(world.h - 1, ceil(j1)) do
        for i = max(0, i0), min(world.w - 1, i1) do
            local n = j * world.w + i
            local d2 = (world.wx[n] - x) ^ 2 + (world.wz[n] - z) ^ 2
            if world.up[n] == 1 and d2 <= r * r and (d2 < (r * 0.6) ^ 2 or (i + j) % 2 == 0) then putGround(i, j) end
        end
    end
end

-- The weather, drawn over everything on the board in screen pixels: rain in
-- streaks, frost as drifting flakes, drought as dust in the heat.
local function drawWeather(kind)
    local t = game.clock
    if kind == "rain" then
        for k = 1, floor(cw * ch / 260) do
            local x = floor((k * 7919 + floor(t * 50) * 31) % cw)
            local y = floor((k * 104729 + t * 260) % (ch + 8)) - 4
            for s = 0, 2 do putS(IDX.s, x, y + s) end
        end
    elseif kind == "frost" then
        for k = 1, floor(cw * ch / 900) do
            local y = floor((k * 104729 + t * 14) % ch)
            local x = floor((k * 7919 + math.sin(t * 0.8 + k) * 6) % cw)
            putS(IDX.w, x, y)
            if k % 4 == 0 then putS(IDX.w, x + 1, y); putS(IDX.w, x, y + 1) end
        end
    elseif kind == "drought" then
        for k = 1, floor(cw * ch / 1800) do
            local x = floor((k * 7919 + t * 9) % cw)
            local y = floor((k * 104729 + math.sin(t + k) * 3) % ch)
            putS(IDX.t, x, y)
        end
    end
end

-- Ink on the ground: the board under it goes dark, in a checker so the soil shows.
local function stain(x, z, r, life)
    local g = world:groundAt(x, z)
    local i0 = floor(world:toImage(x - r, g, z + r)) - 1
    local i1 = ceil(world:toImage(x + r, g, z - r)) + 1
    local _, j0 = world:toImage(x - r, g + 4, z - r)
    local _, j1 = world:toImage(x + r, g - 1, z + r)
    for j = max(0, floor(j0)), min(world.h - 1, ceil(j1)) do
        for i = max(0, i0), min(world.w - 1, i1) do
            local n = j * world.w + i
            local d2 = (world.wx[n] - x) ^ 2 + (world.wz[n] - z) ^ 2
            if world.up[n] == 1 and d2 <= r * r then
                local edge = d2 > (r * 0.7) ^ 2
                if not edge or (i + j) % 2 == 0 then put(edge and IDX.u or IDX.o, i, j) end
            end
        end
    end
end

-- A web thrown over a tower.
local function web(x, y, z)
    local i, j = world:toImage(x, y, z)
    i, j = floor(i), floor(j)
    for s = -6, 6 do
        put(IDX.w, i + s, j + floor(s / 2))
        put(IDX.w, i + s, j - floor(s / 2))
        if s % 3 == 0 then put(IDX.s, i + s, j + 3) end
    end
    for s = -6, 5 do put(IDX.s, i, j + s) end
end

-- Little things circling a head: stunned (cream) or boosted (glow).
local function circling(x, y, z, k, n, r)
    for s = 0, n - 1 do
        local a = game.clock * 5 + s * 2 * math.pi / n
        local i, j = world:toImage(x + math.cos(a) * r, y + math.sin(game.clock * 7 + s) * 2, z + math.sin(a) * r)
        put(k, i, j)
    end
end

-- An arc of a shot at fraction f between (x0, y0, z0) and (tx, 0, tz).
local function arc(s, height)
    local f = s.t / s.flight
    local x, z = s.x0 + (s.tx - s.x0) * f, s.z0 + (s.tz - s.z0) * f
    return x, s.y0 * (1 - f) + math.sin(math.pi * f) * height, z
end

local function dot(x, y, z, k, k2)
    local i, j, d = world:toImage(x, y, z)
    i, j = floor(i), floor(j)
    if visible(i, j, d + 2) then
        if k2 then put(k2, i + 1, j + 1); put(k2, i, j + 1); put(k2, i + 1, j) end
        put(k, i, j)
    end
end

local function drawBoard()
    -- A boss charging, a ball bursting: the board jumps.
    local cx0, cy0 = camx, camy
    if shake > 0 then
        camx = camx + love.math.random(-2, 2)
        camy = camy + love.math.random(-1, 1)
    end
    love.graphics.clear(unpack(T.RGB[IDX.o]))
    love.graphics.setColor(1, 1, 1)
    local sky = game.weather
    love.graphics.draw(sky and world:variant(sky) or world.image, -floor(camx), -floor(camy))
    ffi.fill(opx, cw * ch * 4, 0)
    local night = sky == "night"
    -- At night a lamp lights the ground round it.
    local lamps = {}
    for _, n in ipairs(game.nodes) do
        local t = n.tower
        if t and t.kind == "lamp" and (t.glow or 0) > 0 then
            lamps[#lamps + 1] = n
            if night then lightPool(n.x, n.z, min(34, t.glow * 0.45)) end
        end
    end
    local function lit(x, z)
        for _, n in ipairs(lamps) do
            local r = n.tower.glow
            if (n.x - x) ^ 2 + (n.z - z) ^ 2 <= r * r then return true end
        end
        return false
    end

    -- On the ground first: ink, shadows, mats, threads and rings.
    for _, p in ipairs(game.inks) do
        local r = p.r * min(1, (p.max - p.life) * 6) * min(1, p.life * 2)
        stain(p.x, p.z, r)
    end
    for _, e in ipairs(game.enemies) do
        if e.under then ripples(e.x, e.z, game.clock)
        elseif SHADOW[e.kind] and not e.hidden then shadow(e.x, e.z, SHADOW[e.kind]) end
        if e.ballHp and e.ballHp > 0 then
            local bx, bz = game:ballAt(e)
            shadow(bx, bz, 8)
        end
    end
    for _, m in ipairs(game.mats) do
        if m.kind == "mat" then
            local fading = not m.fed and m.life < 8 and floor(game.clock * 4) % 2 == 0
            stamp(towerLook(m, m.c + m.r), m.x, m.y, m.z, fading and T.DARKER or nil)
        end
    end
    local trailMode = D.TOWER[mode] and D.TOWER[mode].onTrail
    if trailMode and hover.c and not hover.button and mode == "mat" and world:distAt(hover.c, hover.r) then
        local ok = game:canLay(mode, hover.c, hover.r)
        stamp(M.tower(mode), hover.c * 16 + 8, world:groundAt(hover.c * 16 + 8, hover.r * 16 + 8), hover.r * 16 + 8, ok and T.DARKER or T.DARKER2)
    end
    for _, l in ipairs(game.links) do
        local hl
        if hover.link == l then
            if mode == "prune" then hl = IDX.r
            elseif l.state == "cut" and not l.hand and not l.salted then hl = IDX.l end
        end
        drawLink(l, hl)
    end
    for _, n in ipairs(game.nodes) do
        if not n.heart and not n.tower and #n.links > 0 then knot(n, n.conn and IDX.c or IDX.d) end
    end

    -- Fairy rings: the ground inside goes to moss, and a ring of tiny white
    -- caps comes up along the loop.
    for _, r in ipairs(game.rings) do drawRing(r) end

    -- While a thread is being pulled, every pocket it could reach shows it.
    if mode == "grow" and drag then
        for _, n in ipairs(game.nodes) do
            if n ~= drag and game:canLink(drag, n) then
                local i, j = world:toImage(n.x, n.y + 1, n.z)
                local k = floor(game.clock * 4) % 2 == 0 and IDX.l or IDX.c
                put(k, i, j - 1); put(k, i - 1, j); put(k, i + 1, j); put(k, i, j + 1)
            end
        end
    end

    -- Reach: whatever is hovered or selected, or what is about to be grown.
    local towerMode = D.TOWER[mode] and not trailMode
    local shown = hover.node and hover.node.tower or selected
    -- The rules that work through the network show the nodes they work on.
    local touched = shown and shown.node and game:touches(shown)
    if touched then
        for o in pairs(touched) do ring(o.x, o.z, 7, IDX.l, true) end
    end
    if shown and shown.kind == "stink" and shown.node then
        local lane = game:stat(shown, "lane")
        for _, l in ipairs(shown.node.links) do
            if game.alive(l) then
                local dx, dz = l.b.x - l.a.x, l.b.z - l.a.z
                local len = max(1, math.sqrt(dx * dx + dz * dz))
                local nx, nz = -dz / len * lane, dx / len * lane
                for s = 0, floor(len / 3) do
                    local f = s * 3 / len
                    for side = -1, 1, 2 do
                        local px, pz = l.a.x + dx * f + nx * side, l.a.z + dz * f + nz * side
                        local i, j, d = world:toImage(px, world:groundAt(px, pz) + 0.3, pz)
                        if visible(floor(i), floor(j), d + 1) then put(IDX.d, i, j) end
                    end
                end
            end
        end
    end
    if shown and game:stat(shown, "range") and shown.kind ~= "shelf" then
        local x, z = shown.node and shown.node.x or shown.x, shown.node and shown.node.z or shown.z
        local r = shown.node and game:towerRange(shown) or game:stat(shown, "range")
        if r > 0 then ring(x, z, r, IDX.l, true) end
        local bait = game:stat(shown, "bait")
        if bait then ring(x, z, bait, IDX.d, true) end
        local mr = game:stat(shown, "minRange")
        if mr then ring(x, z, mr, IDX.r, true) end
    elseif shown and shown.kind == "shelf" then
        ring(shown.x, shown.z, D.TOWER.shelf.shield, IDX.t, true)
    elseif towerMode and hover.node and not hover.node.heart then
        local q = World.QUALITY[hover.node.quality].power
        if D.TOWER[mode].range then ring(hover.node.x, hover.node.z, D.TOWER[mode].range * q, IDX.l, true) end
    end
    if selected then
        local x, z = selected.node and selected.node.x or selected.x, selected.node and selected.node.z or selected.z
        ring(x, z, 9 + floor(game.clock * 4) % 2, IDX.w)
    end
    if mode == "grow" and (drag or hover.node) then
        local from = drag or hover.node
        ring(from.x, from.z, game:linkReach(), from.conn and IDX.c or IDX.r, true)
    end

    -- The thread being pulled.
    if mode == "grow" and drag then
        local tx, tz, ty = hover.x, hover.z, 0.5
        if hover.node then tx, tz, ty = hover.node.x, hover.node.z, hover.node.y end
        if tx then
            local ok = hover.node and game:canLink(drag, hover.node)
            local k = ok and IDX.l or IDX.r
            local steps = max(2, ceil(sqrt((tx - drag.x) ^ 2 + (tz - drag.z) ^ 2) / 0.6))
            for s = 0, steps do
                if s % 4 < 3 then
                    local f = s / steps
                    local x, z = drag.x + (tx - drag.x) * f, drag.z + (tz - drag.z) * f
                    local i, j, d = world:toImage(x, max(world:groundAt(x, z) + 0.4, drag.y + (ty - drag.y) * f), z)
                    if visible(floor(i), floor(j), d + 1.5) then put(k, i, j) end
                end
            end
        end
    end

    -- Then everything standing up, furthest first.
    local movers = {}
    local function add(x, y, z, draw)
        local _, _, d = T.project(x, y, z)
        movers[#movers + 1] = { d = d, draw = draw }
    end
    local wilt = 1 - game.heartHp / game.heartMax
    add(game.heart.x, game.heart.y, game.heart.z, function()
        stamp(M.sprout(wilt), game.heart.x, game.heart.y - 1, game.heart.z, heartFlash > 0 and T.FLASH or nil)
    end)
    for _, n in ipairs(game.nodes) do
        local t = n.tower
        if t then
            add(n.x, n.y, n.z, function()
                stamp(towerLook(t, n.id), n.x, n.y, n.z, t.flash > 0 and T.FLASH or remapFor(t))
                if t.boost then circling(n.x, n.y + 7, n.z, IDX.w, 4, 6) end
                -- A stinkhorn always has a fly or two about it.
                if t.kind == "stink" and t.hunger ~= "dormant" and t.branch ~= 2 then circling(n.x, n.y + 17, n.z, IDX.o, 2, 4) end
                if t.webbed > 0 then web(n.x, n.y + 7, n.z) end
                if t.stun > 0 then circling(n.x, n.y + 15, n.z, IDX.t, 3, 4) end
                local cap = game:reserveMax(t)
                if cap > 0 and (t.reserve < cap - 0.05 or not n.conn) then
                    bar(n.x, n.y + 17, n.z, t.reserve / cap, n.conn and IDX.l or IDX.r)
                end
                local hp = game:maxHp(t)
                if t.hp < hp - 0.5 then bar(n.x, n.y + 21, n.z, t.hp / hp, IDX.r) end
            end)
        elseif towerMode and hover.node == n and not n.heart then
            add(n.x, n.y, n.z, function()
                local ok = game:canBuild(mode, n)
                stamp(M.tower(mode), n.x, n.y, n.z, ok and T.DARKER or T.DARKER2)
            end)
        end
    end
    for _, m in ipairs(game.mats) do
        if m.kind == "shelf" then
            add(m.x, m.y, m.z, function()
                stamp(towerLook(m, m.c + m.r), m.x, m.y, m.z, m.chewed and floor(game.clock * 10) % 2 == 0 and T.DARKER or nil)
                local hp = game:maxHp(m)
                if m.hp < hp - 0.5 then bar(m.x, m.y + 20, m.z, m.hp / hp, IDX.t) end
            end)
        end
    end
    if trailMode and mode == "shelf" and hover.c and not hover.button and world:distAt(hover.c, hover.r) then
        local x, z = hover.c * 16 + 8, hover.r * 16 + 8
        local y = world:groundAt(x, z)
        add(x, y, z, function()
            local ok = game:canLay(mode, hover.c, hover.r)
            stamp(M.tower(mode), x, y, z, ok and T.DARKER or T.DARKER2)
        end)
    end
    for _, c in ipairs(game.corpses) do
        local g = world:groundAt(c.x, c.z)
        add(c.x, g, c.z, function()
            local remap = T.DARKER
            if c.absorb then remap = floor(game.clock * 10) % 2 == 0 and T.DARKER2 or T.DARKER end
            stamp(M.corpse(c.kind, c.h or 0, c.fruit), c.x, g + (c.carried and 2.5 or 0), c.z, remap)
        end)
    end
    for _, e in ipairs(game.enemies) do
        local size = D.ENEMIES[e.kind].size or 1
        if not e.under and not e.hidden then add(e.x, e.y, e.z, function()
            local remap = e.flash > 0 and T.FLASH or nil
            local host = e.infected and e.infected > 0
            if host and not remap then remap = INFECT end
            -- At night what is not in a lamp's light is hard to see.
            if night and not remap and not lit(e.x, e.z) then remap = T.DARKER end
            stamp(enemyPicture(e), e.x, e.y, e.z, remap)
            if host and floor(game.clock * 6) % 2 == 0 then circling(e.x, e.y + 6, e.z, IDX.t, 2, 3) end
            if e.stun > 0 then circling(e.x, e.y + 8 * size, e.z, IDX.s, 3, 3) end
            if e.mark > 0 then
                local i, j = world:toImage(e.x, e.y + 9 * size + 3, e.z)
                put(IDX.l, i, j - 1); put(IDX.l, i - 1, j); put(IDX.l, i + 1, j); put(IDX.w, i, j)
            end
            if e.hp < e.maxHp and e.kind ~= "mite" and not e.boss then
                bar(e.x, e.y + (e.kind == "brine" and 12 or 10), e.z, e.hp / e.maxHp, IDX.r)
            end
        end) end
        if e.ballHp and e.ballHp > 0 then
            local bx, bz = game:ballAt(e)
            local g = world:groundAt(bx, bz)
            add(bx, g, bz, function()
                local cracked = e.ballHp < e.ballMax * 0.4
                stamp(M.ball(e.h, floor((e.ballRoll or 0) * 3) % 4, cracked), bx, g, bz, e.ballFlash > 0 and T.FLASH or nil)
            end)
        end
    end
    for _, s in ipairs(game.shots) do
        if s.kind == "spore" then
            local x, y, z = arc(s, 16)
            add(x, y, z, function() dot(x, y, z, IDX.w, IDX.t) end)
        elseif s.kind == "shell" then
            local x, y, z = arc(s, 46)
            add(x, y, z, function()
                local i, j, d = world:toImage(x, y, z)
                i, j = floor(i), floor(j)
                put(IDX.o, i - 1, j - 1); put(IDX.o, i + 2, j); put(IDX.o, i, j + 2); put(IDX.o, i - 1, j + 1); put(IDX.o, i + 1, j - 1)
                put(IDX.n, i, j); put(IDX.n, i + 1, j); put(IDX.u, i, j + 1); put(IDX.u, i + 1, j + 1); put(IDX.t, i, j - 1)
            end)
        elseif s.kind == "bomblet" then
            local x, y, z = arc(s, 10)
            add(x, y, z, function() dot(x, y, z, IDX.t, IDX.n) end)
        elseif s.kind == "cordy" then
            local x, y, z = arc(s, 12)
            add(x, y, z, function() dot(x, y, z, IDX.t, IDX.r) end)
        elseif s.kind == "ink" then
            local x, y, z = arc(s, 8)
            add(x, y, z, function() dot(x, y, z, IDX.o, IDX.u) end)
        else
            add(s.x1, s.y1, s.z1, function()
                line3(s.x0, s.y0, s.z0, s.x1, s.y1, s.z1, (s.big or s.mark) and IDX.l or IDX.w)
            end)
        end
    end
    table.sort(movers, function(a, b) return a.d < b.d end)
    for _, m in ipairs(movers) do m.draw() end

    -- Lingering toxin: a green haze turning over the ground.
    for _, c in ipairs(game.clouds) do
        local fade = min(1, c.life / 0.6)
        for s = 0, 21 do
            if (s * 7) % 10 < fade * 10 then
                local a = s / 22 * 2 * math.pi + game.clock * 0.6
                local rr = c.r * (0.25 + 0.75 * ((s * 7) % 5) / 4)
                local x, z = c.x + math.cos(a) * rr, c.z + math.sin(a) * rr
                local i, j, d = world:toImage(x, world:groundAt(x, z) + 1.5 + (s % 3) + math.sin(game.clock * 2 + s) * 0.8, z)
                if visible(floor(i), floor(j), d + 2) then put(s % 3 == 0 and IDX.d or IDX.m, i, j) end
            end
        end
    end

    for _, p in ipairs(game.fx) do
        if p.cloud then
            local f = 1 - p.life / p.max
            local r = p.r * (0.5 + 0.5 * f)
            local n = p.r > 14 and 44 or 30
            for s = 0, n - 1 do
                if love.math.random() > f * 0.8 then
                    local a = s / n * 2 * math.pi + f
                    local rr = r * (0.4 + 0.6 * ((s * 7) % 5) / 4)
                    local x, z = p.x + math.cos(a) * rr, p.z + math.sin(a) * rr
                    local i, j, d = world:toImage(x, world:groundAt(x, z) + 1 + f * 4 + (s % 3), z)
                    local k = s % 3 == 0 and IDX.t or IDX.w
                    if p.smoke then k = s % 3 == 0 and IDX.k or IDX.s end
                    if p.glowing then k = s % 3 == 0 and IDX.c or IDX.l end
                    if visible(floor(i), floor(j), d + 2) then put(k, i, j) end
                end
            end
        elseif p.wave then
            -- The Humongous Fungus's quake: a ring running out over the ground.
            local f = 1 - p.life / p.max
            local r = p.r * f
            local n = max(16, floor(r * 1.4))
            for s = 0, n - 1 do
                if (s + floor(f * 6)) % 3 ~= 0 then
                    local a = s / n * 2 * math.pi
                    local x, z = p.x + math.cos(a) * r, p.z + math.sin(a) * r
                    local i, j, d = world:toImage(x, world:groundAt(x, z) + 0.5, z)
                    local k = p.honey and (s % 2 == 0 and IDX.t or IDX.w) or (s % 2 == 0 and IDX.n or IDX.t)
                    if visible(floor(i), floor(j), d + 1) then put(k, i, j); put(IDX.u, i, j + 1) end
                end
            end
        elseif p.streak then
            if p.t >= 0 then
                local f = min(1, p.t / p.max)
                local x, z = p.x + (p.tx - p.x) * f, p.z + (p.tz - p.z) * f
                local i, j, d = world:toImage(x, p.y + math.sin(f * math.pi) * 6, z)
                if visible(floor(i), floor(j), d + 2) then put(IDX[p.k], i, j); put(IDX[p.k], i + 1, j) end
            end
        elseif p.glow then
            local f = p.t / p.max
            local x, z = p.x + (p.tx - p.x) * f, p.z + (p.tz - p.z) * f
            local i, j, d = world:toImage(x, world:groundAt(x, z) + 1 + math.sin(f * math.pi) * 4, z)
            if visible(floor(i), floor(j), d + 2) then put(IDX.l, i, j) end
        else
            local i, j, d = world:toImage(p.x, p.y, p.z)
            if visible(floor(i), floor(j), d + 1) then put(IDX[p.k], i, j) end
        end
    end

    if sky then drawWeather(sky) end

    overlayImage:replacePixels(overlay)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(overlayImage, 0, 0)
    camx, camy = cx0, cy0
end

--- lettering and the HUD -----------------------------------------------------------------

local function color(k) love.graphics.setColor(T.RGB[IDX[k]]) end

local function box(x, y, w, h, fill, edge)
    color(edge or "o")
    love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2)
    color(fill or "u")
    love.graphics.rectangle("fill", x, y, w, h)
end

local function text(s, x, y, k)
    color(k or "w")
    Font.print(s, x, y)
end

local function label(s, x, y, k, fill)
    box(x - 2, y - 2, Font.width(s) + 4, 9, fill or "u")
    text(s, x, y, k)
end

local function centred(s, y, k, fill)
    label(s, floor((vw - Font.width(s)) / 2), y, k, fill)
end

local function waveSummary(wave)
    local count, order = {}, {}
    for _, g in ipairs(wave) do
        if not count[g[1]] then order[#order + 1] = g[1]; count[g[1]] = 0 end
        count[g[1]] = count[g[1]] + g[2] * (g[1] == "mite" and D.ENEMIES.mite.swarm or 1)
    end
    local parts = {}
    if wave.weather then parts[1] = D.WEATHER[wave.weather].name .. ":" end
    for _, kind in ipairs(D.ENEMY_ORDER) do
        if count[kind] then
            local name = D.ENEMIES[kind].boss and D.ENEMIES[kind].name or kind:upper()
            parts[#parts + 1] = (D.ENEMIES[kind].boss and "" or (count[kind] .. " ")) .. name
        end
    end
    return table.concat(parts, "  ")
end

-- The same help in a finger's words: no keys, no right button, tap not click.
local function say(m, t) return touch and t or m end

-- A tower's name at its tier: the upgrade's, once it has one.
local function towerName(t)
    if t.branch then return D.TOWER[t.kind].up[t.branch][t.tier].name end
    return D.TOWER[t.kind].name
end

-- What to say at the bottom when nothing is hovered: the next thing to learn.
local function hint()
    if game.phase ~= "build" then
        local brine = false
        for _, e in ipairs(game.enemies) do if e.kind == "brine" and e.slide then brine = true end end
        if brine then return say("BRINE IN THE NETWORK! PRUNE (X) THE LINK IT IS ON", "BRINE IN THE NETWORK! PRUNE THE LINK IT IS ON"), "r" end
        return nil
    end
    local living = 0
    for _, l in ipairs(game.links) do if l.state ~= "cut" then living = living + 1 end end
    local towers = 0
    for _, n in ipairs(game.nodes) do if n.tower then towers = towers + 1 end end
    if living == 0 then return "DRAG FROM THE SPROUT TO A POCKET TO GROW A LINK", "g" end
    if towers == 0 then return say("PICK A FRUITING BODY BELOW, THEN CLICK A LINKED POCKET", "PICK A FRUITING BODY BELOW, THEN TAP A LINKED POCKET"), "g" end
    local nxt = game:nextWave()
    if nxt then
        for _, g in ipairs(nxt) do
            local e = D.ENEMIES[g[1]]
            if e.boss then return "BOSS NEXT: " .. e.name .. ". " .. e.blurb, "r" end
        end
    end
    if game.newSpecies then
        local kind = game.newSpecies
        local grown = false
        for _, n in ipairs(game.nodes) do if n.tower and n.tower.kind == kind then grown = true end end
        for _, m in ipairs(game.mats) do if m.kind == kind then grown = true end end
        if not grown then return "NEW SPECIES: " .. D.TOWER[kind].name .. ". " .. D.TOWER[kind].blurb, "l" end
    end
    if nxt then
        for _, g in ipairs(nxt) do
            if not game.seen[g[1]] then return "NEW: " .. D.ENEMIES[g[1]].name .. ". " .. D.ENEMIES[g[1]].blurb, "t" end
        end
        if nxt.weather then
            local wx = D.WEATHER[nxt.weather]
            return wx.name .. " NEXT WAVE: " .. wx.blurb, "s"
        end
    end
    if selected and game:upgrades(selected)[1] and game.wave <= 2 then
        return say("UPGRADES: CLICK A CARD ABOVE, OR Z / C", "UPGRADES: TAP A CARD ABOVE"), "l"
    end
    if game.wave == 0 then return say("SPACE TO START THE FIRST WAVE", "TAP START FOR THE FIRST WAVE"), "g" end
end

local function tooltip()
    if hover.mutation then
        local m = game.choices[hover.mutation]
        return m.name .. ": " .. m.blurb, "l"
    end
    if game.phase == "mutate" then return say("THE NETWORK MUTATES. PICK ONE (1 2 3)", "THE NETWORK MUTATES. PICK ONE"), "l" end
    if hover.card then
        local c = panelCards()[hover.card]
        if not c.up then return towerName(selected) .. ": FULLY GROWN", "w" end
        local ok, why = game:canUpgrade(selected, c.up.branch)
        return c.up.row.name .. ": " .. c.up.row.blurb .. (ok and "" or ("  (" .. why .. ")")), ok and "l" or "r"
    end
    if hover.button then
        local b = BUTTONS[hover.button]
        if b.tower and not game:unlocked(b.mode) then
            return b.name .. ": UNLOCKS AFTER WAVE " .. game:unlockAt(b.mode), "r"
        end
        return b.name .. (b.cost and (" (" .. b.cost .. ")") or "") .. ": " .. b.blurb, "w"
    end
    if hover.wave then
        return game.phase == "build" and say("START THE NEXT WAVE (SPACE)", "START THE NEXT WAVE") or say("GAME SPEED (F)", "GAME SPEED"), "w"
    end
    if mode == "grow" and drag and hover.node and hover.node ~= drag then
        local ok, cost, why = game:canLink(drag, hover.node)
        if ok then return "GROW LINK: " .. cost, "l" end
        return (why or "") .. (cost and ("  (" .. cost .. ")") or ""), "r"
    end
    if mode == "pulse" and hover.node then
        if game.pulseCd > 0 then return "PULSE REGROWING: " .. math.ceil(game.pulseCd) .. "S", "r" end
        if not hover.node.conn then return "NOT FED: THE PULSE CANNOT REACH IT", "r" end
        return "SEND THE PULSE HERE", "l"
    end
    if hover.node and hover.node.tower then
        local t = hover.node.tower
        local s = towerName(t)
        if mode == "prune" then return "CLEAR " .. s .. ": +" .. floor(t.spent * D.SELL), "r" end
        if t.webbed > 0 then s = s .. ": WEBBED SHUT"
        elseif t.stun > 0 then s = s .. ": STUNNED"
        elseif t.hunger == "dormant" then s = s .. ": DORMANT, NO NUTRIENTS"
        elseif not hover.node.conn then s = s .. ": CUT OFF, ON ITS RESERVE"
        elseif t.thirsty then s = s .. ": THIRSTY, NEEDS A RELAY BESIDE IT"
        elseif t.hunger == "starved" then s = s .. ": STARVED" end
        if t.hp < game:maxHp(t) then s = s .. "  HP " .. math.ceil(t.hp) end
        if t.kind == "puffer" then s = s .. "  PUFFS " .. max(1, min(4, game:degree(hover.node))) end
        if t.kind == "needle" and game:degree(hover.node) == 1 then s = s .. "  DEAD END X1.8" end
        if t.kind == "lamp" then s = s .. "  GLOW " .. floor(t.glow or 0) end
        if t.kind == "mane" then s = s .. "  TENDS " .. members(t.care) .. " NODES" end
        if t.kind == "relay" then s = s .. "  PUMPS INTO " .. #game:neighbours(hover.node) end
        if t.kind == "inky" then s = s .. "  FEEDS " .. #game:neighbours(hover.node) .. " FIRST" end
        if t.kind == "cordyceps" then s = s .. "  HOLD X" .. string.format("%.1f", game:deepHold(t)) end
        if t.kind == "stink" then s = s .. "  REEKS DOWN " .. game:degree(hover.node) .. " LINKS" end
        if t.kind == "mortar" and hover.node.pocket.high then s = s .. "  HIGH: NO MIN RANGE" end
        if t.kind == "giant" then
            local k = game:rooted(t)
            if t.grown < 1 then s = s .. "  GROWING " .. floor(t.grown * 100) .. "%"
            else s = s .. "  " .. k .. " NODES: HITS " .. floor(game:stat(t, "damage") + game:stat(t, "perNode") * k) end
        end
        if hover.node.ringed then s = s .. "  RING" end
        if (t.amp or 1) > 1 then s = s .. "  AMPED" end
        return s .. "  " .. hover.node.quality:upper() .. " POCKET", "w"
    end
    if hover.node then
        local n = hover.node
        if n.heart then return "THE SPROUT. IF IT DIES, YOU LOSE", "g" end
        local s = n.pocket.kind:upper() .. ": " .. n.quality:upper() .. " POCKET"
        if (n.salted or 0) > 0 then s = s .. ", SALTED" end
        if n.quality == "rich" then s = s .. ". +30% POWER, PAYS SUGAR" elseif n.quality == "poor" then s = s .. ". -25% POWER" end
        if n.pocket.high then s = s .. ". HIGH GROUND" elseif n.pocket.low then s = s .. ". LOW: RAIN WASHES IT" end
        if D.TOWER[mode] and not D.TOWER[mode].onTrail then
            local ok, why = game:canBuild(mode, n)
            if ok then return "GROW " .. D.TOWER[mode].name .. " HERE: " .. D.TOWER[mode].cost, "l" end
            if why then return why, "r" end
        end
        return s, "w"
    end
    if hover.link then
        local l = hover.link
        if mode == "prune" then
            return "PRUNE LINK: +" .. floor(l.cost * (l.state == "alive" and D.LINK.prune or D.LINK.prune * 0.5)), "r"
        end
        if l.state == "cut" then
            if l.salted then return "SALTED LINK. IT WILL NOT REGROW: PRUNE IT", "w" end
            if l.hand then return "REGROWING", "l" end
            return say("CUT LINK. CLICK TO REGROW: ", "CUT LINK. TAP TO REGROW: ") .. game:repairCost(l), "l"
        end
        if l.state == "grow" then return "GROWING", "l" end
        local s = "LINK " .. floor(l.hp) .. "/" .. floor(game:linkHp()) .. "  FLOW " .. (l.cap or D.LINK.cap)
        if l.thick then s = s .. " (RELAY)" end
        if not l.a.conn then s = s .. "  NOT FED" end
        return s, "w"
    end
    if D.TOWER[mode] and D.TOWER[mode].onTrail and hover.c then
        local d = D.TOWER[mode]
        local ok, why = game:canLay(mode, hover.c, hover.r)
        if ok then return "GROW " .. d.name .. ": " .. d.cost, "l" end
        if not world:distAt(hover.c, hover.r) then return d.name .. " GOES ON THE TRAIL", "r" end
        return why or "", "r"
    end
    if mode == "prune" and hover.mat then return "LIFT " .. D.TOWER[hover.mat.kind].name .. ": +" .. game:liftValue(hover.mat), "r" end
    if hover.mat and mode == "grow" then
        local m = hover.mat
        local s = towerName(m)
        if m.kind == "mat" then
            s = s .. (m.fed and (": " .. m.draped .. " LINK" .. (m.draped > 1 and "S" or "") .. " OVER IT")
                or ": WITHERING " .. math.ceil(m.life) .. "S")
            s = s .. "  SLOW " .. floor((1 - game:matSlow(m)) * 100) .. "%"
        else s = s .. "  HP " .. math.ceil(m.hp) .. "/" .. game:maxHp(m) end
        return s, "w"
    end
    if mode == "grow" and drag then return say("LET GO OVER A GLOWING POCKET. RIGHT CLICK CANCELS", "TAP A GLOWING POCKET. TAP THE GROUND TO CANCEL"), "l" end
    if mode == "pulse" then
        if game.pulseCd > 0 then return "PULSE REGROWING: " .. math.ceil(game.pulseCd) .. "S", "r" end
        return say("CLICK A FED NODE TO SEND THE PULSE", "TAP A FED NODE TO SEND THE PULSE"), "l"
    end
end

local function drawHud()
    -- The top strip.
    color("o")
    love.graphics.rectangle("fill", 0, 0, vw, inset.t + TOP - 1)
    local ty = inset.t + 3
    local inc = game.income or 0
    local s = "NUTRIENTS " .. floor(game.nutrients)
    text(s, inset.l + 3, ty, "l")
    local x = inset.l + 3 + Font.width(s) + 2
    if game.phase == "wave" then
        local i = (inc >= 0 and "+" or "") .. string.format("%.1f", inc)
        text(i, x + 2, ty, inc >= 0 and "c" or "r")
        x = x + Font.width(i) + 4
    end
    s = "SPROUT " .. math.ceil(game.heartHp) .. "/" .. game.heartMax
    text(s, x + 8, ty, game.heartHp < game.heartMax * 0.4 and "r" or "g")
    local w = "WAVE " .. game.wave .. "/" .. #game.waves
    local nxt = game:nextWave()
    local right = w
    if nxt and game.phase == "build" then right = "NEXT: " .. waveSummary(nxt) .. "   " .. w end
    if game.phase == "wave" then
        local left = #game.queue
        for _, e in ipairs(game.enemies) do left = left + 1 end
        right = left .. " LEFT   " .. w
        if game.weather then right = D.WEATHER[game.weather].name .. "   " .. right end
    end
    local leftEnd = x + 8 + Font.width(s) + 8
    local rx = vw - inset.r - Font.width(right) - 3
    -- A narrow screen keeps the wave count and lets the forecast go: the
    -- gates still say how many come in at each.
    if rx < leftEnd and right ~= w then right = w; rx = vw - inset.r - Font.width(w) - 3 end
    text(right, rx, ty, "w")
    if paused then
        if touch then centred("PAUSED. TAP THE TOP BAR TO GO ON", floor(vh / 2) - 40, "r")
        else text("PAUSED", floor((vw - Font.width("PAUSED")) / 2), ty, "r") end
    end

    -- Gates: where the next wave comes in.
    if nxt and game.phase == "build" then
        local per = {}
        for _, g in ipairs(nxt) do per[g[4]] = (per[g[4]] or 0) + g[2] * (g[1] == "mite" and D.ENEMIES.mite.swarm or 1) end
        for gate, n in pairs(per) do
            local e = world.entrances[gate]
            if e then
                local i, j = world:toImage(e.x - 6, world:groundAt(e.x, e.z) + 6, e.z)
                local sx, sy = toHud(i, j)
                if floor(game.clock * 2) % 2 == 0 then label(n .. " IN", sx - 6, sy - 10, "w", "r") end
            end
        end
    end

    -- Words in the world.
    for _, t in ipairs(game.texts) do
        local i, j = world:toImage(t.x, t.y, t.z)
        local sx, sy = toHud(i, j)
        sx = sx - floor(Font.width(t.text) / 2)
        text(t.text, sx, sy + 1, "o")
        text(t.text, sx, sy, t.k)
    end

    -- The toolbar.
    for n, b in ipairs(BUTTONS) do
        local bx, by, bw, bh = buttonRect(n)
        local on = mode == b.mode
        box(bx, by, bw, bh, on and "n" or "u", on and "l" or (hover.button == n and "t" or "o"))
        local cx, cy = bx + floor(bw / 2), by + bh - 9
        if b.mode == "grow" then
            color("d")
            for s = 0, 14 do love.graphics.rectangle("fill", bx + 8 + s, by + 15 - floor(s / 2) + 1, 1, 1) end
            color("c")
            for s = 0, 14 do love.graphics.rectangle("fill", bx + 8 + s, by + 15 - floor(s / 2), 1, 1) end
            color("l")
            love.graphics.rectangle("fill", bx + 8 + floor(game.clock * 10) % 15, by + 15 - floor((floor(game.clock * 10) % 15) / 2), 1, 1)
        elseif b.mode == "prune" then
            text("X", cx - 1, by + 9, "r")
        elseif b.mode == "pulse" then
            local ready = game.pulseCd <= 0
            local k = ready and (floor(game.clock * 3) % 2 == 0 and "w" or "l") or "d"
            color(k)
            for s = -4, 4 do love.graphics.rectangle("fill", cx + s, by + 12 - floor(abs(s) / 2) * ((s % 2 == 0) and 1 or -1), 1, 1) end
            love.graphics.rectangle("fill", cx - 1, by + 10, 3, 3)
            if not ready then
                local c = tostring(math.ceil(game.pulseCd))
                text(c, bx + bw - Font.width(c) - 1, by + bh - 6, "r")
            end
        else
            local open = game:unlocked(b.mode)
            local pic = icon(b.mode, nil, 0, on and (game.clock * 0.7) % 1 or 0)
            local afford = game.nutrients >= (b.cost or 0)
            blit(pic, cx, b.mode == "mat" and by + 14 or by + 21, (not afford or not open) and T.DARKER2 or nil)
        end
        if not touch then text(b.key, bx + 1, by + 1, "s") end
        if b.tower and not game:unlocked(b.mode) then
            local c = "W" .. game:unlockAt(b.mode)
            text(c, bx + bw - Font.width(c) - 1, by + bh - 6, "k")
        elseif b.cost then
            local c = tostring(b.cost)
            text(c, bx + bw - Font.width(c) - 1, by + bh - 6, game.nutrients >= b.cost and "l" or "r")
        end
    end
    local wx, wy, ww, wh = waveRect()
    if game.phase == "build" then
        box(wx, wy, ww, wh, hover.wave and "m" or "d", "g")
        text("START", wx + floor((ww - Font.width("START")) / 2), wy + 5, "g")
        local s2 = "WAVE " .. (game.wave + 1)
        text(s2, wx + floor((ww - Font.width(s2)) / 2), wy + 13, "w")
        if not touch then text("SPACE", wx + floor((ww - Font.width("SPACE")) / 2), wy + 20, "s") end
    else
        box(wx, wy, ww, wh, "u", hover.wave and "t" or "o")
        local s2 = "SPEED X" .. speed
        text(s2, wx + floor((ww - Font.width(s2)) / 2), wy + 9, "w")
        if not touch then text("F", wx + floor((ww - 3) / 2), wy + 18, "s") end
    end

    -- The upgrade panel: what the selected thing can become.
    local cards = panelCards()
    for k, c in ipairs(cards) do
        local u = c.up
        local can = u and game:canUpgrade(selected, u.branch)
        box(c.x, c.y, c.w, c.h, hover.card == k and "n" or "u", u and (can and "l" or "k") or "t")
        if u then
            local pic = icon(selected.kind, u.branch, u.tier, (game.clock * 0.7) % 1)
            blit(pic, c.x + 11, c.y + c.h - (selected.kind == "mat" and 8 or 3), can and nil or T.DARKER)
            text(u.row.name, c.x + 23, c.y + 3, "w")
            local tag = (u.tier == 1 and "I" or "II") .. "  " .. u.row.cost
            text(tag, c.x + 23, c.y + 11, can and "l" or "r")
            if not touch then
                local key = (#cards == 1 or k == 1) and "Z" or "C"
                if #cards == 1 then key = "Z/C" end
                text(key, c.x + c.w - Font.width(key) - 2, c.y + 11, "s")
            end
            -- Two pips: how far up its branch it has grown.
            for p = 1, 2 do
                color(p <= (selected.tier or 0) and "l" or "k")
                love.graphics.rectangle("fill", c.x + 23 + (p - 1) * 4, c.y + 18, 3, 2)
            end
        else
            local pic = icon(selected.kind, selected.branch, selected.tier, (game.clock * 0.7) % 1)
            blit(pic, c.x + 11, c.y + c.h - (selected.kind == "mat" and 8 or 3))
            text(towerName(selected), c.x + 23, c.y + 3, "w")
            text("FULLY GROWN", c.x + 23, c.y + 11, "t")
        end
    end
    local tipBase = cards[1] and cards[1].y - 4 or barTop()

    -- A boss on the board: its name and its health across the top.
    local boss
    for _, e in ipairs(game.enemies) do if e.boss then boss = e break end end
    if boss then
        local d = D.ENEMIES[boss.kind]
        local w = min(170, vw - inset.l - inset.r - 20)
        local bx, by = floor((vw - w) / 2), inset.t + TOP + 3
        -- A train's health is all of its segments'.
        local hp, top = boss.hp, boss.maxHp
        if boss.train then
            hp, top = 0, boss.train.max
            for _, e in ipairs(game.enemies) do if e.train == boss.train and not e.dead then hp = hp + e.hp end end
        end
        box(bx, by, w, 4, "u", "o")
        color("r")
        love.graphics.rectangle("fill", bx, by, floor(w * max(0, hp / top)), 4)
        if boss.ballHp and boss.ballHp > 0 then
            box(bx, by + 6, w, 2, "u", "o")
            color("t")
            love.graphics.rectangle("fill", bx, by + 6, floor(w * boss.ballHp / boss.ballMax), 2)
        end
        local name = d.name .. (boss.under and " (UNDER WATER)" or "")
        text(name, floor((vw - Font.width(name)) / 2), by + (boss.ballHp and boss.ballHp > 0 and 11 or 7), "w")
    end
    if game.bossIntro then
        local d = D.ENEMIES[game.bossIntro.kind]
        if floor(game.bossIntro.t * 4) % 4 ~= 0 or game.bossIntro.t < 2.5 then
            centred(d.name, inset.t + TOP + 22, "r", "o")
        end
        centred(d.blurb, inset.t + TOP + 33, "w", "o")
    end

    -- One line of help above the toolbar.
    local tip, k = tooltip()
    if not tip then tip, k = hint() end
    if tip then
        -- Too long for the screen (a phone held upright): broken at a word onto
        -- a second line above, rather than cut off.
        local room = vw - inset.l - inset.r - 8
        local lines = { tip }
        if Font.width(tip) > room then
            local cut
            for i = #tip, 1, -1 do
                if tip:sub(i, i) == " " and Font.width(tip:sub(1, i - 1)) <= room then cut = i break end
            end
            if cut then lines = { tip:sub(1, cut - 1), tip:sub(cut + 1) } end
        end
        for n, l in ipairs(lines) do
            if Font.width(l) > room then l = l:sub(1, floor(room / 4)) end
            centred(l, tipBase - 11 - (#lines - n) * 10, k)
        end
    end

    if game.phase == "mutate" then
        local cs = mutationCards()
        centred("THE NETWORK MUTATES", cs[1].y - 14, "l", "o")
        for k, c in ipairs(cs) do
            box(c.x, c.y, c.w, c.h, hover.mutation == k and "n" or "u", hover.mutation == k and "l" or "c")
            text(c.m.name, c.x + 4, c.y + 4, "l")
            if not touch then text(tostring(k), c.x + c.w - 6, c.y + 4, "s") end
            -- The blurb, broken into lines that fit the card.
            local line, y = "", c.y + 14
            for word in c.m.blurb:gmatch("%S+") do
                local try = line == "" and word or line .. " " .. word
                if Font.width(try) > c.w - 8 then
                    text(line, c.x + 4, y, "w")
                    line, y = word, y + 7
                else
                    line = try
                end
            end
            text(line, c.x + 4, y, "w")
        end
    end

    if game.phase == "won" then
        local last = level == D.LEVELS[#D.LEVELS]
        centred(level.name .. (game.challenge and " (CHALLENGE)" or "") .. ": THE SPROUT LIVES", floor(vh / 2) - 24, "g")
        centred("KILLS " .. game.stats.kills .. "   BOSSES " .. game.stats.bosses .. "   DRUNK " .. floor(game.stats.drunk) .. "   CUTS " .. game.stats.cuts, floor(vh / 2) - 12, "w")
        centred(say((last and "" or "N: NEXT LEVEL   ") .. "R: AGAIN   M: LEVELS", "TAP FOR THE LEVELS"), floor(vh / 2), "l")
        if last and not game.challenge then centred("CHALLENGE MODE IS OPEN", floor(vh / 2) + 12, "r") end
    elseif game.phase == "lost" then
        centred("THE SPROUT HAS WILTED", floor(vh / 2) - 24, "r")
        centred("YOU HELD " .. (game.wave - 1) .. " WAVES OF " .. #game.waves, floor(vh / 2) - 12, "w")
        centred(say("R: TRY AGAIN   M: LEVELS", "TAP FOR THE LEVELS"), floor(vh / 2), "l")
    end
end

-- Words broken into lines `w` wide, from (x, y) down, seven pixels a line.
local function wrap(s, x, y, w, k)
    local line = ""
    for word in s:gmatch("%S+") do
        local try = line == "" and word or line .. " " .. word
        if Font.width(try) > w then
            text(line, x, y, k)
            line, y = word, y + 7
        else
            line = try
        end
    end
    text(line, x, y, k)
    return y + 7
end

local function drawMenu()
    color("o")
    love.graphics.rectangle("fill", 0, 0, vw, vh)
    local cards, switch = levelCards()
    centred("UNDERFOOT", cards[1].y - 30, "g", "o")
    centred("WHERE DOES THE SPROUT COME UP?", cards[1].y - 18, "t", "o")
    for k, c in ipairs(cards) do
        local l = D.LEVELS[k]
        local open, on = levelOpen(k), hover.level == k
        box(c.x, c.y, c.w, c.h, on and open and "n" or "u", won[l.id] and "g" or (open and (on and "l" or "c") or "k"))
        text(k .. "  " .. l.name, c.x + 4, c.y + 4, open and "w" or "k")
        if not open then
            text("WIN " .. D.LEVELS[k - 1].name, c.x + 4, c.y + 14, "r")
            text("TO OPEN IT", c.x + 4, c.y + 21, "r")
        else
            local y = wrap(l.idea, c.x + 4, c.y + 14, c.w - 8, "t")
            wrap("BOSS: " .. l.boss, c.x + 4, y + 1, c.w - 8, "r")
            local tag = won[l.id] and "WON" or (#l.waves .. " WAVES")
            text(tag, c.x + c.w - Font.width(tag) - 4, c.y + c.h - 8, won[l.id] and "g" or "s")
        end
    end
    if challengeOpen() then
        local c = switch
        box(c.x, c.y, c.w, c.h, hover.challenge and "n" or "u", challenge and "r" or "k")
        local s = "CHALLENGE: " .. (challenge and "ON" or "OFF")
        text(s, c.x + floor((c.w - Font.width(s)) / 2), c.y + 5, challenge and "r" or "w")
        if hover.challenge or challenge then
            centred("A LAST WAVE ON ANY LEVEL: THE BOMBARDIER BEETLE", c.y + c.h + 6, "r", "o")
        end
    end
    local hintY = vh - inset.b - 12
    centred(say("1 2 3 OR CLICK A LEVEL", "TAP A LEVEL") .. (challengeOpen() and say("   C: CHALLENGE", "") or ""), hintY, "s", "o")
end

local function drawLoading()
    love.graphics.clear(unpack(T.RGB[IDX.o]))
    local s = "GROWING " .. level.name
    local w = 80
    local x, y = floor((vw - w) / 2), floor(vh / 2)
    text(s, floor((vw - Font.width(s)) / 2), y - 10, "t")
    color("u")
    love.graphics.rectangle("fill", x, y, w, 4)
    color("c")
    love.graphics.rectangle("fill", x, y, floor(w * progress), 4)
end

function love.draw()
    -- The HUD's picture starts empty each frame (nothing where the board shows
    -- through) and everything on it is drawn solid, so laying it over the board
    -- covers a pixel fully or not at all.
    love.graphics.setCanvas(ui)
    love.graphics.clear(0, 0, 0, 0)
    if painter then
        drawLoading()
    elseif menu then
        drawMenu()
    else
        drawHud()
        love.graphics.setCanvas(canvas)
        drawBoard()
    end
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    if painter or menu then
        -- Nothing to stretch: the loading bar or the picker is the whole screen.
    elseif pinch and not pinch.done then
        -- Mid-pinch: the frame stretched about where the fingers started and
        -- moved to where they are (see love.touchpressed).
        love.graphics.clear(unpack(T.RGB[IDX.o]))
        local z = zoom * pinch.s
        love.graphics.draw(canvas, pinch.x - pinch.x0 * pinch.s, pinch.y - pinch.y0 * pinch.s, 0, z, z)
    else
        love.graphics.draw(canvas, 0, 0, 0, zoom, zoom)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(ui, 0, 0, 0, uz, uz)
end
