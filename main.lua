-- Groute: a tower defense where you are the mycelium under a sprout.
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
-- The camera goes round the board a quarter turn at a time (the buttons at the
-- bottom right and left, or E and Q): the board has a picture for each side
-- (see World:toView) and the turn between them is the picture going round,
-- squashed as the ground is, before the next one takes its place.
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
local Sfx = require "src.sfx"
-- The sound's glue to the screen (the sounds themselves are src/sfx.lua).
local audio = {}

local floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt
local IDX = T.IDX

local SHORT = 240 -- game pixels across the short edge of the window
local TOP, BOTTOM = 12, 32

-- Two pictures, each at its own whole zoom. The board's zooms in and out
-- under the fingers; the HUD's (the strip, the toolbar, the words) never
-- changes with it, so a button is the same size at any zoom.
local canvas, cw, ch, zoom -- the board
-- Board pixels the board's picture runs past each edge of the window: none,
-- except while a pinch may pull in what is off the screen.
local pad = { l = 0, t = 0, r = 0, b = 0 }
local ui, vw, vh, uz -- the HUD, and every screen measure the HUD lays out by
local overlay, overlayImage, opx
local world, painter, progress = nil, nil, 0
local game
-- The levels: which one is being played, the boards already painted (one a
-- level, kept so a second run of it starts at once), and the level picker.
local level = D.LEVELS[1]
local worlds = {}
local menu -- the level picker is up (true), or a level's loadout ("loadout")
local pick -- the loadout being picked: { n = level, set = { id = true }, enemy = kind }
local chosen -- the species the run brings, a list; nil brings them all (the shots)
local loadouts = {} -- each level's last loadout, saved between runs: { crack = { "puffer", ... } }
local challenge = false -- challenge mode chosen in the picker
local won = {} -- levels won, saved between runs: { crack = true, ... }
local records = {} -- the most waves held in endless on each level, saved: { crack = 21, ... }

-- What has been won lives in the save directory, one level id a line.
-- How loud: 1, 0.5 or 0 (the V key goes round them), kept between runs.
function audio.load()
    local data = love.filesystem.getInfo("sound.txt") and love.filesystem.read("sound.txt")
    local v = data and tonumber(data:match("[%d%.]+"))
    if v then Sfx.level = v end
end

function audio.save() love.filesystem.write("sound.txt", tostring(Sfx.level) .. "\n") end

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

-- The endless records too, a line a level: its id and the most waves held.
local function loadRecords()
    records = {}
    local data = love.filesystem.getInfo("endless.txt") and love.filesystem.read("endless.txt")
    if not data then return end
    for id, n in data:gmatch("(%S+)%s+(%d+)") do
        if D.LEVEL[id] then records[id] = tonumber(n) end
    end
end

local function saveRecords()
    local lines = {}
    for _, l in ipairs(D.LEVELS) do
        if records[l.id] then lines[#lines + 1] = l.id .. " " .. records[l.id] end
    end
    love.filesystem.write("endless.txt", table.concat(lines, "\n") .. "\n")
end

-- Each level's loadout lives in the save directory too, a line a level: its id
-- and then the species it brings.
local function loadLoadouts()
    loadouts = {}
    local data = love.filesystem.getInfo("loadout.txt") and love.filesystem.read("loadout.txt")
    if not data then return end
    for line in data:gmatch("[^\n]+") do
        local list, id = {}, nil
        for w in line:gmatch("%S+") do
            if not id then id = w
            elseif D.TOWER[w] and #list < D.LOADOUT then list[#list + 1] = w end
        end
        if id and D.LEVEL[id] and #list > 0 then loadouts[id] = list end
    end
end

local function saveLoadouts()
    local lines = {}
    for _, l in ipairs(D.LEVELS) do
        if loadouts[l.id] then lines[#lines + 1] = l.id .. " " .. table.concat(loadouts[l.id], " ") end
    end
    love.filesystem.write("loadout.txt", table.concat(lines, "\n") .. "\n")
end

-- A level is open once the one before it is won; challenge mode once the last is.
-- One won already, or any after it, keeps it open: a save from before the
-- Flowerpot, the Shed Floor and the Rotting Log came in still has the Pond
-- Edge and the Lawn.
local function levelOpen(n)
    if n == 1 or won[D.LEVELS[n - 1].id] then return true end
    for k = n, #D.LEVELS do if won[D.LEVELS[k].id] then return true end end
    return false
end
local function challengeOpen() return won[D.LEVELS[#D.LEVELS].id] end
local camx, camy, panx, pany = 0, 0, 0, 0
local mode = "grow"
local drag -- the node a link is being pulled from
local tapped -- the node just flair.pressed: let go of it where it was, and it is selected
local hover = {}
-- The pointer in HUD pixels (x, y) and window pixels (wx, wy).
local mouse = { x = 0, y = 0, wx = 0, wy = 0 }
-- How far the HUD keeps in from each screen edge, in HUD pixels. None: the HUD
-- runs right to the border, notch and rounded corners and all, on a phone too.
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
-- The weather's word in the top strip, where the last HUD drawn put it:
-- { x, y, w, h, kind, next }. A finger has no hover, so a tap pins its tip
-- open (`weatherTip`, the kind) and a second tap shuts it.
local weatherBox, weatherTip = nil, nil
local heartFlash = 0
local shake = 0 -- seconds of shaking left: a boss charging, a ball breaking
-- The HUD's own flourishes: the last thing pressed lighting up, the nutrients
-- going red when they fall short (bright when a lot comes in at once), the
-- edge of the screen going red when the sprout is hit, and a word across the
-- screen when a wave comes or goes.
--   pressed  { t, rect }: the thing just pressed, and how to find its box
--   nut      { t, k }: the nutrients' flash
--   hurt     seconds of red edge left
--   banner   { text, sub, k, t, max }
--   note     seconds left of the word saying how loud the sound is now
--   beat     the sprout's heartbeat, when it is low
local flair = { nut = { t = 0, k = "l" }, hurt = 0, note = 0, lastNut = 0 }

-- A sound of the HUD's: not anywhere on the board, so dead centre.
local function sound(name, pitch) Sfx.play(name, 0, 1, pitch) end

-- Not allowed, or not enough: a buzz, and the nutrients flash red.
local function deny()
    sound("deny")
    flair.nut = { t = 0.4, k = "r" }
end
local selected -- the tower, mat or shelf whose upgrades are showing
local peek -- the species in hand whose panel the toolbar opened
-- The camera easing toward a selection: where panx, pany are headed, and what
-- they were sent there for (a new selection sends them again).
local focus, focused
local script -- the --shots run
local shot -- and the whole screen it photographs
-- The camera going round: the frame it left, the screen point it turns about,
-- how far round and how long it has been at it.
local turning
local TURN_TIME = 0.45

--- the screen ----------------------------------------------------------------------

-- The board's picture: the window's worth, and pad past each edge of it.
local function padBoard(l, t, r, b)
    pad.l, pad.t, pad.r, pad.b = l, t, r, b
    local w, h = cw + l + r, ch + t + b
    canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter("nearest", "nearest")
    -- The overlay is one byte-for-byte picture of everything laid over the board
    -- this frame: a pixel is either covered, fully, or not there. Painter's order
    -- is simply the order things are put.
    overlay = love.image.newImageData(w, h, "rgba8")
    opx = ffi.cast("uint8_t*", overlay:getFFIPointer())
    overlayImage = love.graphics.newImage(overlay)
    overlayImage:setFilter("nearest", "nearest")
end

-- The title-bar / taskbar icon, the same picture the packaged .exe, .app,
-- AppImage and APK carry (assets/icon/, see desktop/icon.py), four times up so
-- the window system shrinks it rather than smears it.
local function setWindowIcon()
    local ok, small = pcall(love.image.newImageData, "assets/icon/icon.png")
    if not ok then return end
    local w, h = small:getDimensions()
    local icon = love.image.newImageData(w * 4, h * 4)
    icon:mapPixel(function(x, y) return small:getPixel(floor(x / 4), floor(y / 4)) end)
    love.window.setIcon(icon)
end

local function fit()
    local w, h = love.graphics.getDimensions()
    local base = max(1, floor(min(w, h) / SHORT))
    uz = base + UI_STEP
    vw, vh = ceil(w / uz), ceil(h / uz)
    ui = love.graphics.newCanvas(vw, vh)
    ui:setFilter("nearest", "nearest")

    zoom = base + zoomStep
    cw, ch = ceil(w / zoom), ceil(h / zoom)
    padBoard(0, 0, 0, 0)
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

-- The board-image pixels a box of the room can cover, whichever way the board
-- is turned: i0, i1, j0, j1.
local function screenBox(x0, x1, y0, y1, z0, z1)
    local i0, i1, j0, j1 = math.huge, -math.huge, math.huge, -math.huge
    for _, x in ipairs({ x0, x1 }) do
        for _, y in ipairs({ y0, y1 }) do
            for _, z in ipairs({ z0, z1 }) do
                local i, j = world:toImage(x, y, z)
                i0, i1, j0, j1 = min(i0, i), max(i1, i), min(j0, j), max(j1, j)
            end
        end
    end
    return floor(i0) - 1, ceil(i1) + 1, floor(j0), ceil(j1)
end

-- A heading in the room as it is seen in the view shown.
local function turned(h) return h + world.turn * math.pi / 2 end

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

-- A one-pixel line in key k round a picture stamped as above: every empty pixel
-- next to one of its own, as near as the pixel it borders, so the board in front
-- still hides it.
local function outline(pic, x, y, z, k)
    local si, sj, d = world:toImage(x, y, z)
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
    local g = world:groundAt(x, z)
    local i0, i1, j0, j1 = screenBox(x - r, x + r, g - 1, g + 4, z - r, z + r)
    for j = max(0, j0), min(world.h - 1, j1) do
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

-- The toolbar: regrow-all, the species the run brought (in their usual order,
-- each on its usual key), prune and the pulse. Laid out again for each run.
local BUTTONS = {}
local function layTools(g)
    for k = #BUTTONS, 1, -1 do BUTTONS[k] = nil end
    -- Not a tool: a press regrows every cut link at once (links are grown by
    -- dragging, with nothing in hand).
    BUTTONS[1] = { mode = "regrow", key = "1", name = "REGROW ALL", action = true }
    for _, t in ipairs(D.TOWERS) do
        if not g or g:brought(t.id) then
            BUTTONS[#BUTTONS + 1] = { mode = t.id, key = t.key, name = t.name, blurb = t.blurb, cost = t.cost, tower = true }
        end
    end
    BUTTONS[#BUTTONS + 1] = { mode = "prune", key = "X", name = "PRUNE", blurb = "CUT YOUR OWN LINK (HALF BACK) OR CLEAR A TOWER" }
    BUTTONS[#BUTTONS + 1] = { mode = "pulse", key = "Q", name = "SPORE PULSE",
        blurb = "PICK A FED NODE: EVERY TOWER ON THE WAY THERE OVERCHARGES" }
end
layTools()

-- The toolbar sits along the bottom with the wave button at
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
-- The buttons that take the camera round the board, over the toolbar:
-- clockwise (d = 1) in the bottom right corner, back (d = -1) in the left.
local RW, RH = 22, 18
local function turnRect(d)
    local x = d == -1 and inset.l + 2 or vw - inset.r - 2 - RW
    return x, barTop() - RH - 5, RW, RH
end
local function inside(x, y, rx, ry, rw, rh) return x >= rx and y >= ry and x < rx + rw and y < ry + rh end

-- The info panel: everything about one species, or one fruiting body as it
-- has grown. Down the right side on a wide screen; across the top of the board
-- (or the bottom of the loadout) on a narrow one. Shown for whatever is
-- selected in a run, and for the card tapped in the loadout.
local function wide() return vw > vh end
local function infoWidth() return wide() and min(150, floor(vw * 0.36)) or vw - inset.l - inset.r - 6 end

-- Words broken into lines no wider than w.
local function wrapLines(str, w)
    local lines, line = {}, ""
    for word in str:gmatch("%S+") do
        local try = line == "" and word or line .. " " .. word
        if Font.width(try) > w and line ~= "" then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function number(v)
    if v == floor(v) then return tostring(v) end
    return string.format("%.1f", v)
end

-- The panel's lines, each { s, k (colour), x, h }: the name and role beside
-- the picture, the long account, the numbers (live, for one on the board),
-- and both upgrade branches with what is grown, open or shut.
local function infoLines(kind, t, w)
    local d = D.TOWER[kind]
    local out, height = {}, 0
    local function add(str, k, x, h)
        x = x or 0
        for _, l in ipairs(wrapLines(str, w - x)) do
            out[#out + 1] = { s = l, k = k, x = x, h = h or 7 }
            height = height + (h or 7)
        end
    end
    local function gap(h) out[#out + 1] = { h = h }; height = height + h end
    local function get(k) if t then return game:stat(t, k) end return d[k] end

    add(t and t.branch and d.up[t.branch][t.tier].name or d.name, "w", 24, 8)
    add(d.role .. "   " .. (t and ("SPENT " .. t.spent) or ("COST " .. d.cost)), "t", 24)
    if height < 22 then gap(22 - height) end

    -- On the board: what is wrong with it, if anything.
    if t then
        local why
        if t.hunger == "dormant" then why = "DORMANT: LINK IT TO THE SPROUT"
        elseif t.hunger == "starved" then why = "STARVED: HALF PACE"
        elseif t.thirsty then why = "THIRSTY: FEED IT FROM A RELAY"
        elseif (t.webbed or 0) > 0 then why = "WEBBED SHUT"
        elseif kind == "mat" and not t.fed then why = "WITHERING: DRAPE A LINK OVER IT" end
        if why then add(why, "r"); gap(2) end
    end

    -- A species read about first; one on the board puts its numbers and its
    -- upgrades first, so a short panel still has them.
    if not t then add(d.about, "w"); gap(3) end
    local parts = {}
    if get("damage") then parts[#parts + 1] = "DAMAGE " .. number(get("damage")) end
    if get("every") then parts[#parts + 1] = "EVERY " .. number(get("every")) .. "S" end
    local r = (t and t.node) and game:towerRange(t) or get("range")
    if r then parts[#parts + 1] = "RANGE " .. floor(r + 0.5) end
    if get("splash") then parts[#parts + 1] = "SPLASH " .. number(get("splash")) end
    if kind == "mat" then parts[#parts + 1] = "SLOW " .. floor((1 - (t and game:matSlow(t) or d.slow)) * 100 + 0.5) .. "%" end
    if kind == "relay" then
        parts[#parts + 1] = "FLOW X" .. number(get("capMul"))
        parts[#parts + 1] = "DAMAGE +" .. floor(((get("amp") or 1) - 1) * 100 + 0.5) .. "%"
    end
    if t and t.hp and kind ~= "mat" then parts[#parts + 1] = "HP " .. math.ceil(t.hp) .. "/" .. game:maxHp(t)
    elseif not t and d.hp then parts[#parts + 1] = "HP " .. d.hp end
    -- A number never parted from its name: lines broken between them.
    local line = ""
    for _, part in ipairs(parts) do
        local try = line == "" and part or line .. "  " .. part
        if Font.width(try) > w and line ~= "" then add(line, "l"); line = part else line = try end
    end
    if line ~= "" then add(line, "l") end

    -- On the board, what it can grow into next is a button: the upgrade itself.
    local open = {}
    if t then for _, u in ipairs(game:upgrades(t)) do open[u.branch * 10 + u.tier] = u end end
    gap(4)
    add("UPGRADES", "t")
    for b = 1, 2 do
        if b == 2 then add("OR", "s") end
        local shut = t and t.branch and t.branch ~= b
        for tier = 1, 2 do
            local row = d.up[b][tier]
            local u = open[b * 10 + tier]
            if u then
                local blurb = wrapLines(row.blurb, w - 8)
                local h = 11 + 7 * #blurb
                out[#out + 1] = { up = u, row = row, blurb = blurb, h = h + 3 }
                height = height + h + 3
            else
                local grown = t and t.branch == b and t.tier >= tier
                local k = grown and "g" or (shut and "k" or "w")
                add((tier == 1 and "I  " or "II ") .. row.name .. "  " .. (grown and "GROWN" or row.cost), k)
                -- On the board only what it can grow now says what it does.
                if not t then add(row.blurb, "s", 12) end
            end
        end
    end
    if t then gap(4); add(d.about, "s") end
    return out, height
end

-- The panel open now, laid out: nil if there is none.
local function info()
    local kind, t
    if menu == "loadout" then
        kind = pick and pick.info
    elseif not menu and game and (game.phase == "build" or game.phase == "wave") then
        if selected then kind, t = selected.kind, selected
        elseif peek and peek == mode then kind = peek end
    end
    if not kind then return end
    local w = infoWidth()
    local lines, h = infoLines(kind, t, w - 8)
    local P = { kind = kind, t = t, lines = lines, w = w }
    if menu == "loadout" then
        if wide() then
            P.x, P.y, P.h = vw - inset.r - w - 3, inset.t + 3, vh - inset.t - inset.b - 6
        else
            -- Room for the BRING / LEAVE button under the words.
            P.h = min(h + 28, floor(vh * 0.55))
            P.x, P.y = inset.l + 3, vh - inset.b - 3 - P.h
        end
        P.button = { x = P.x + 4, y = P.y + P.h - 18, w = w - 8, h = 14 }
    else
        local top = inset.t + TOP + 2
        if wide() then
            local _, ty = turnRect(1)
            P.x, P.y, P.h = vw - inset.r - w - 3, top, ty - 4 - top
        else
            P.x, P.y, P.h = inset.l + 3, top, min(h + 8, floor((barTop() - top) * 0.6))
        end
    end
    -- Where each line sits, so an upgrade's button can be hit; one cut off by
    -- the bottom of the panel cannot.
    local y = P.y + 4
    for _, l in ipairs(lines) do
        l.y = y
        y = y + l.h
        if l.up and y > P.y + P.h then l.up = nil end
    end
    return P
end

-- What the panel leaves free across the screen, as left and right edges.
local function freeSpan()
    local P = info()
    if P and wide() then return inset.l, P.x - 3 end
    return inset.l, vw - inset.r
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

-- The level picker: a card a level, in rows of as many as fit across (three
-- on a wide screen, two rows of them; down the middle on a narrow one), and
-- the challenge switch under them once it is open.
local LW, LH = 124, 50
local function levelCards()
    local n = #D.LEVELS
    local cols = max(1, min(3, floor((vw - inset.l - inset.r - 8 + 6) / (LW + 6))))
    local rows = ceil(n / cols)
    local gap = cols == 1 and 4 or 6
    local cards = {}
    local y0 = floor(vh / 2 - (rows * LH + (rows - 1) * gap) / 2) - 8
    for k = 1, n do
        local row, col = floor((k - 1) / cols), (k - 1) % cols
        local across = min(cols, n - row * cols)
        local x0 = floor((vw - (across * LW + (across - 1) * 6)) / 2)
        cards[k] = { x = x0 + col * (LW + 6), y = y0 + row * (LH + gap), w = LW, h = LH, n = k }
    end
    y0 = y0 + rows * (LH + gap) + 4
    local switch = { x = floor((vw - LW) / 2), y = y0, w = LW, h = 16, challenge = true }
    return cards, switch
end

-- What a won level offers, a button each across the middle under the words:
-- the next level (if there is one), endless, again, the levels. Two rows if
-- one does not fit across.
local function wonButtons()
    local list = {}
    local last = level == D.LEVELS[#D.LEVELS]
    if not last then list[#list + 1] = { id = "next", text = "NEXT LEVEL", key = "N" } end
    list[#list + 1] = { id = "endless", text = "GO ENDLESS", key = "E" }
    list[#list + 1] = { id = "again", text = "AGAIN", key = "R" }
    list[#list + 1] = { id = "levels", text = "LEVELS", key = "M" }
    local gap = 4
    local function width(from, to)
        local w = gap * (to - from)
        for k = from, to do w = w + list[k].w end
        return w
    end
    for _, b in ipairs(list) do
        if not touch then b.text = b.key .. ": " .. b.text end
        b.w, b.h = Font.width(b.text) + 10, 15
    end
    local rows = { { 1, #list } }
    if width(1, #list) > vw - inset.l - inset.r - 8 then
        local half = ceil(#list / 2)
        rows = { { 1, half }, { half + 1, #list } }
    end
    local y = floor(vh / 2) - 1
    for _, row in ipairs(rows) do
        local x = floor((vw - width(row[1], row[2])) / 2)
        for k = row[1], row[2] do list[k].x, list[k].y = x, y; x = x + list[k].w + gap end
        y = y + 15 + gap
    end
    list.bottom = y
    return list
end

-- The level picker's sound switch, top right: a finger has no V key.
function audio.switch() return { x = vw - inset.r - 62, y = inset.t + 4, w = 58, h = 12 } end

-- The loadout picker: what the level sends (a chip an enemy, bosses last),
-- a card a species under it, and BACK and GO under those, all centred
-- down the screen. A narrow screen takes fewer cards a row.
local SW, SH = 62, 26
local function enemiesOf(lv)
    local seen = {}
    for _, w in ipairs(lv.waves) do for _, g in ipairs(w) do seen[g[1]] = true end end
    if challenge then for _, g in ipairs(D.CHALLENGE) do seen[g[1]] = true end end
    local list = {}
    for _, kind in ipairs(D.ENEMY_ORDER) do if seen[kind] then list[#list + 1] = kind end end
    return list
end

local function loadoutLayout()
    local lv = D.LEVELS[pick.n]
    -- With the panel open the picker keeps to the room it leaves: the left on a
    -- wide screen, the top on a narrow one.
    local open = pick.info ~= nil
    local left, right = inset.l, vw - inset.r
    if open and wide() then right = vw - inset.r - infoWidth() - 6 end
    local mid = floor((left + right) / 2)
    local avail = right - left - 8
    local cols = 6
    while cols > 2 and cols * SW + (cols - 1) * 4 > avail do cols = cols == 6 and 4 or cols - 1 end
    local rows = ceil(#D.TOWERS / cols)

    -- The chips, flowed into rows as wide as the cards.
    local width = max(cols * SW + (cols - 1) * 4, min(avail, 300))
    local chips, lines, x, line = {}, 1, 0, {}
    local function name(kind) return D.ENEMIES[kind].name end
    for _, kind in ipairs(enemiesOf(lv)) do
        local w = Font.width(name(kind)) + 6
        if x > 0 and x + w > width then lines, x = lines + 1, 0 end
        chips[#chips + 1] = { kind = kind, line = lines, dx = x, w = w, h = 9, name = name(kind) }
        x = x + w + 3
    end

    local height = 22 + 10 + lines * 12 + 6 + rows * (SH + 4) + 6 + 16
    local y = max(inset.t + 4, floor((vh - inset.b - 12 - height) / 2))
    if open and not wide() then y = inset.t + 4 end
    local top = y
    y = y + 32
    -- Each chip row centred on its own.
    local ends = {}
    for _, c in ipairs(chips) do ends[c.line] = c.dx + c.w end
    for _, c in ipairs(chips) do
        c.x = floor(mid - ends[c.line] / 2) + c.dx
        c.y = y + (c.line - 1) * 12
    end
    y = y + lines * 12 + 6

    local cards = {}
    local x0 = floor(mid - (cols * SW + (cols - 1) * 4) / 2)
    for k, t in ipairs(D.TOWERS) do
        local col, row = (k - 1) % cols, floor((k - 1) / cols)
        cards[k] = { x = x0 + col * (SW + 4), y = y + row * (SH + 4), w = SW, h = SH, t = t }
    end
    y = y + rows * (SH + 4) + 6
    local back = { x = mid - 54, y = y, w = 50, h = 16 }
    local go = { x = mid + 4, y = y, w = 50, h = 16 }
    return { top = top, chips = chips, chipsY = top + 32, cards = cards, back = back, go = go, mid = mid }
end

local function picked()
    local list = {}
    for _, t in ipairs(D.TOWERS) do if pick.set[t.id] then list[#list + 1] = t.id end end
    return list
end

-- A species in or out of the loadout. Full, it says so rather than drop one.
local function toggleSpecies(id)
    if pick.set[id] then pick.set[id] = nil; sound("off")
    elseif #picked() >= D.LOADOUT then pick.full = 1.5; sound("deny")
    else pick.set[id] = true; sound("on") end
end

local function nodeScreen(n)
    local i, j = world:toImage(n.x, n.y + (n.heart and 10 or 5), n.z)
    return i, j
end

local function findHover()
    hover = {}
    local mx, my = mouse.x, mouse.y
    if menu == "loadout" then
        local P = info()
        if P then
            if inside(mx, my, P.button.x, P.button.y, P.button.w, P.button.h) then hover.bring = true return end
            if inside(mx, my, P.x, P.y, P.w, P.h) then hover.info = true return end
        end
        local L = loadoutLayout()
        for _, c in ipairs(L.chips) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then hover.enemy = c.kind return end
        end
        for _, c in ipairs(L.cards) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then hover.species = c.t.id return end
        end
        if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then hover.back = true end
        if inside(mx, my, L.go.x, L.go.y, L.go.w, L.go.h) then hover.go = true end
        return
    end
    if menu then
        local cards, switch = levelCards()
        for k, c in ipairs(cards) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then hover.level = k return end
        end
        if challengeOpen() and inside(mx, my, switch.x, switch.y, switch.w, switch.h) then hover.challenge = true end
        local sw = audio.switch()
        if inside(mx, my, sw.x, sw.y, sw.w, sw.h) then hover.sound = true end
        return
    end
    if game.phase == "won" then
        for _, b in ipairs(wonButtons()) do
            if inside(mx, my, b.x, b.y, b.w, b.h) then hover.won = b.id return end
        end
    end
    if game.phase == "mutate" then
        for k, c in ipairs(mutationCards()) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then hover.mutation = k return end
        end
    end
    local P = info()
    if P and inside(mx, my, P.x, P.y, P.w, P.h) then
        hover.info = true
        for _, l in ipairs(P.lines) do
            if l.up and inside(mx, my, P.x + 3, l.y, P.w - 6, l.h - 3) then hover.up = l.up end
        end
        return
    end
    for n = 1, #BUTTONS do
        if inside(mx, my, buttonRect(n)) then hover.button = n return end
    end
    if inside(mx, my, waveRect()) then hover.wave = true return end
    if inside(mx, my, turnRect(1)) then hover.turn = 1 return end
    if inside(mx, my, turnRect(-1)) then hover.turn = -1 return end
    local wb = weatherBox
    if wb and inside(mx, my, wb.x, wb.y, wb.w, wb.h) then hover.weather = wb.kind return end
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
    game = Game.new(world, level, { challenge = challenge, loadout = chosen, best = records[level.id] })
    layTools(game)
    mode, drag, panx, pany, selected = "grow", nil, 0, 0, nil
    focus, focused = nil, nil
    paused, speed = false, 1
    menu = nil
end

-- Plays level `n` with the species in `chosen`: its board if it is painted
-- already, else paint it first.
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

-- Before level `n`: pick what to bring, starting from what was brought last
-- time (or the level's own suggestion the first time).
local openLoadout

-- Won: one of the buttons, or its key.
local function afterWin(id)
    if id == "endless" then sound("go"); game:goEndless()
    elseif id == "again" then sound("go"); start()
    elseif id == "levels" then sound("back"); openMenu()
    elseif id == "next" then
        for k, l in ipairs(D.LEVELS) do
            if l == level and D.LEVELS[k + 1] then sound("select"); openLoadout(k + 1) return end
        end
    end
end

function openLoadout(n)
    local lv = D.LEVELS[n]
    menu = "loadout"
    mode, drag, selected = "grow", nil, nil
    pick = { n = n, set = {}, full = 0 }
    for _, id in ipairs(loadouts[lv.id] or lv.loadout or {}) do pick.set[id] = true end
end

-- Off into the level with what was picked, remembered for next time.
local function setOff()
    local list = picked()
    if #list == 0 then sound("deny") return end
    sound("go")
    loadouts[D.LEVELS[pick.n].id] = list
    saveLoadouts()
    chosen = list
    play(pick.n)
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    setWindowIcon()
    fit()
    loadProgress()
    loadLoadouts()
    loadRecords()
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
    audio.load()
    Sfx.init()
    for _, a in ipairs(args or {}) do
        if a == "--sounds" then
            -- Dev: every sound written out as a .wav, to listen to one by one.
            Sfx.dump()
            print("sounds written to " .. love.filesystem.getSaveDirectory() .. "/sounds")
            love.event.quit()
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

-- A tap on nothing (no pocket, no plant, no thread, off the board) puts
-- everything down: the tool in hand, a thread being pulled, the selection.
local function letGo()
    mode, drag, selected, peek = "grow", nil, nil, nil
end

-- Finishes painting view q of the board now, if the background has not got
-- there yet (see love.update).
local function paintNow(q)
    local bg = world.backPainter
    while not world:painted(q) and bg and coroutine.status(bg) ~= "dead" do
        local ok, err = coroutine.resume(bg)
        if not ok then error(err) end
    end
    if not world:painted(q) then
        local co = coroutine.create(function() world:paint(q) end)
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
    if turning or pinch or painter or menu or not game then return end
    local q = (world.turn + d) % World.TURNS
    paintNow(q)
    local mi, mj = floor(cw / 2), floor(ch / 2)
    local x, y, z = world:pick(mi + floor(camx), mj + floor(camy))
    if not x then
        x, z = world.W / 2, world.D / 2
        y = world:groundAt(x, z)
    end
    local i0, j0 = world:toImage(x, y, z)
    local i1, j1 = world:toImage(x + 10, y, z)
    local px, py = i0 - floor(camx), j0 - floor(camy)
    local a0 = math.atan2((j1 - j0) * 2, i1 - i0)

    local old = love.graphics.newCanvas(cw, ch)
    old:setFilter("nearest", "nearest")
    love.graphics.setCanvas(old)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas)
    love.graphics.setCanvas()

    world:setTurn(q)
    focus = nil
    centre()
    local n0, m0 = world:toImage(x, y, z)
    panx = panx + (n0 - floor(camx)) - px
    pany = pany + (m0 - floor(camy)) - py
    centre()
    -- How far the picture goes round on the screen, measured with the ground
    -- unsquashed so a quarter turn of the room is a quarter turn of it.
    local n1, m1 = world:toImage(x + 10, y, z)
    local a = math.atan2((m1 - m0) * 2, n1 - n0) - a0
    a = (a + math.pi) % (2 * math.pi) - math.pi
    turning = { t = 0, old = old, px = px, py = py, angle = a, d = d }
    sound("turn", d > 0 and 1 or 0.85)
end

-- Whatever is under the pointer that lights up when pressed: how to find its
-- box again (the layout can move under it while it is lit).
function flair.under()
    if menu == "loadout" then
        local L = loadoutLayout()
        if hover.back then return function() return L.back.x, L.back.y, L.back.w, L.back.h end end
        if hover.go then return function() return L.go.x, L.go.y, L.go.w, L.go.h end end
        if hover.species then
            for _, c in ipairs(L.cards) do
                if c.t.id == hover.species then return function() return c.x, c.y, c.w, c.h end end
            end
        end
        return
    end
    if menu then
        if hover.level then
            local c = levelCards()[hover.level]
            return function() return c.x, c.y, c.w, c.h end
        end
        if hover.challenge then
            local _, c = levelCards()
            return function() return c.x, c.y, c.w, c.h end
        end
        if hover.sound then
            local c = audio.switch()
            return function() return c.x, c.y, c.w, c.h end
        end
        return
    end
    if hover.mutation then
        local c = mutationCards()[hover.mutation]
        return function() return c.x, c.y, c.w, c.h end
    end
    if hover.won then
        local id = hover.won
        return function()
            for _, b in ipairs(wonButtons()) do if b.id == id then return b.x, b.y, b.w, b.h end end
            return 0, 0, 0, 0
        end
    end
    if hover.button then
        local n = hover.button
        return function() return buttonRect(n) end
    end
    if hover.wave then return waveRect end
    if hover.turn then
        local d = hover.turn
        return function() return turnRect(d) end
    end
end

local function click(b)
    local r = b == 1 and flair.under()
    if r then flair.pressed = { t = 0.18, rect = r } end
    if menu == "loadout" then
        -- A card opens its panel; the same card again (or the panel's button)
        -- brings it or leaves it. Anywhere else shuts the panel.
        if hover.bring then toggleSpecies(pick.info) return end
        if hover.info then return end
        if b == 2 then
            sound("back")
            if pick.info then pick.info = nil else openMenu() end
            return
        elseif hover.species then
            if pick.info == hover.species then toggleSpecies(hover.species) else pick.info = hover.species; sound("panel") end
            return
        elseif hover.back then sound("back"); openMenu()
        elseif hover.go then setOff()
        elseif hover.enemy then
            -- Pinned, so a finger (which has no hover) can see the answers too.
            pick.enemy = pick.enemy ~= hover.enemy and hover.enemy or nil
            sound(pick.enemy and "select" or "back")
        elseif pick and pick.info then
            sound("back")
        end
        if pick then pick.info = nil end
        return
    end
    if menu then
        if hover.level and levelOpen(hover.level) then sound("select"); openLoadout(hover.level)
        elseif hover.level then deny()
        elseif hover.challenge then challenge = not challenge; sound(challenge and "on" or "off")
        elseif hover.sound then Sfx.cycle(); audio.save(); sound("on") end
        return
    end
    if weatherTip and not hover.weather then weatherTip = nil end
    if b == 2 then
        if mode ~= "grow" or drag or selected then sound("back") end
        mode, drag, selected = "grow", nil, nil
        return
    end
    if game.phase == "mutate" then
        -- The picker holds the game until a mutation is chosen.
        if hover.mutation then game:mutate(hover.mutation) end
        return
    end
    if hover.up then
        if not game:upgrade(selected, hover.up.branch) then deny() end
        return
    end
    if hover.info then return end
    if hover.button then
        -- The tool already in hand, picked again, is put down: the one way to
        -- cancel there is without a right button. A species not yet unlocked
        -- stays in its slot, dark.
        local bt = BUTTONS[hover.button]
        if bt.action then
            if game:repairAll() == 0 then deny() end
            return
        end
        if bt.tower and not game:unlocked(bt.mode) then deny() return end
        local m = bt.mode
        drag = nil
        if bt.tower and m == mode then
            -- The species in hand, picked again: its panel opens, or shuts. It
            -- stays in hand; a tap on the ground puts it down.
            peek, selected = peek ~= m and m or nil, nil
            sound(peek and "panel" or "back")
            return
        end
        mode, peek = (m == mode and m ~= "grow") and "grow" or m, nil
        if mode ~= "grow" then selected = nil end
        sound(mode == "grow" and "back" or "select")
        return
    end
    if hover.wave then
        if game.phase == "build" then game:startWave() else speed = speed % 3 + 1; sound("speed", 0.8 + 0.2 * speed) end
        return
    end
    if hover.turn then turnCamera(hover.turn) return end
    if game.phase == "won" then
        if hover.won then afterWin(hover.won) end
        return
    end
    if game.phase == "lost" then sound("click"); openMenu() return end
    if hover.weather then
        -- Not the pause: on a phone a tap opens what the weather does, and
        -- another shuts it. With a mouse, hovering is enough.
        if touch then
            weatherTip = weatherTip ~= hover.weather and hover.weather or nil
            sound(weatherTip and "panel" or "back")
        end
        return
    end
    if hover.strip then
        -- No P key on a phone: the top strip is the pause button.
        if touch then paused = not paused; sound(paused and "pause" or "unpause") end
        return
    end
    if mode == "grow" then
        if hover.node then
            if drag and drag ~= hover.node then
                if not game:grow(drag, hover.node) then deny() end
                drag, selected = nil, nil
            else
                -- A node is picked up as the end of a thread. Its tower is only
                -- selected (and the camera only goes to it) once it is let go
                -- where it was: pulled on to another node, it was a link.
                drag, tapped = hover.node, hover.node
            end
        elseif hover.link and hover.link.state == "cut" then
            if not game:repair(hover.link) then deny() end
        elseif hover.mat then
            drag, selected = nil, hover.mat
            sound("panel")
        else
            if selected then sound("back") end
            drag, selected = nil, nil
        end
    elseif mode == "prune" then
        if hover.node and hover.node.tower then
            game:sell(hover.node)
        elseif hover.link then
            game:prune(hover.link)
        elseif hover.mat then
            game:liftMat(hover.mat)
        else
            sound("back")
            letGo()
        end
    elseif D.TOWER[mode] and D.TOWER[mode].onTrail then
        -- Off the trail (or off the board) there is nowhere to lay it.
        if hover.c and world:distAt(hover.c, hover.r) then
            local m = game:lay(mode, hover.c, hover.r)
            if m then selected, peek = m, nil else deny() end
        else
            sound("back")
            letGo()
        end
    elseif mode == "pulse" then
        if not hover.node then sound("back"); letGo()
        elseif game:pulse(hover.node) then mode = "grow"
        else deny() end
    else
        if hover.node then
            local t = game:build(mode, hover.node)
            -- Planted, the species is put down: back to growing, with the new
            -- tower selected.
            if t then selected, peek, mode = t, nil, "grow" else deny() end
        else
            sound("back")
            letGo()
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
    if painter or pinch or turning then return end
    touch = istouch and true or false
    point(x, y)
    findHover()
    if b == 3 then mouse.pan = { wx = x, wy = y, px = panx, py = pany } return end
    if b == 1 and not (hover.button or hover.wave or hover.turn or hover.node or hover.mutation or hover.info) and not (mode == "grow" and drag) then
        press = { x = mouse.x, y = mouse.y, wx = x, wy = y, px = panx, py = pany }
        return
    end
    click(b)
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
    local t = tapped
    tapped = nil
    -- Pulled from one node and let go over another: a link.
    if b == 1 and mode == "grow" and drag and hover.node and hover.node ~= drag then
        if not game:grow(drag, hover.node) then deny() end
    elseif b == 1 and t and drag == t and hover.node == t then
        -- Let go where it was picked up: a tap, which selects its tower (or,
        -- on a bare pocket, puts the selection down).
        if t.tower then sound("panel") elseif selected then sound("back") end
        selected = t.tower
    end
    -- Links are only ever dragged: whatever was let go of, nothing is left in
    -- hand, so a tap never leaves a thread waiting for the next one.
    if b == 1 then drag = nil end
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
        focus = nil
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
    focus, focused = nil, selected -- aimed at the old zoom; the player has taken over
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
    sound("zoom", d > 0 and 1.2 or 0.85)
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
        press, drag, tapped = nil, nil, nil
        -- Spread or pinched in, the frame shows past the window's edges: the
        -- whole board is drawn while the fingers are down, not just what was on
        -- the screen, so nothing is cut off until they let go.
        if world and game and not menu then
            local fx, fy, m = floor(camx), floor(camy), 8
            padBoard(max(0, fx + m), max(0, fy + m), max(0, world.w - fx - cw + m), max(0, world.h - fy - ch + m))
        end
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
    if key == "v" then
        Sfx.cycle()
        audio.save()
        flair.note = 1.5
        sound("on")
        return
    end
    if painter then return end
    if menu == "loadout" then
        if key == "escape" or key == "backspace" then
            if pick.info then pick.info = nil else openMenu() end
            return
        end
        if key == "return" or key == "kpenter" or key == "space" then setOff() return end
        for _, t in ipairs(D.TOWERS) do
            if key == t.key:lower() then toggleSpecies(t.id) end
        end
        return
    end
    if menu then
        local n = tonumber(key)
        if n and D.LEVELS[n] then
            if levelOpen(n) then sound("select"); openLoadout(n) else deny() end
        end
        if key == "c" and challengeOpen() then challenge = not challenge; sound(challenge and "on" or "off") end
        if key == "escape" and game then sound("back"); menu = nil end
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
        if drag or mode ~= "grow" or selected then
            mode, drag, selected = "grow", nil, nil
            sound("back")
        else
            paused = not paused
            sound(paused and "pause" or "unpause")
        end
    end
    for n, b in ipairs(BUTTONS) do
        if key == b.key:lower() then
            flair.pressed = { t = 0.18, rect = function() return buttonRect(n) end }
            if b.action then
                if game:repairAll() == 0 then deny() end
            elseif not (b.tower and not game:unlocked(b.mode)) then
                mode, drag, selected, peek = b.mode, nil, nil, nil
                sound("select")
            else
                deny()
            end
        end
    end
    if (key == "z" or key == "c") and selected then
        local ups = game:upgrades(selected)
        local u = ups[key == "z" and 1 or #ups]
        if not (u and game:upgrade(selected, u.branch)) then deny() end
    end
    if key == "space" then
        if game.phase == "build" then
            flair.pressed = { t = 0.18, rect = waveRect }
            game:startWave()
        end
    end
    if key == "f" then speed = speed % 3 + 1; sound("speed", 0.8 + 0.2 * speed) end
    if key == "e" and game.phase == "won" then afterWin("endless") return end
    if key == "e" then turnCamera(love.keyboard.isDown("lshift", "rshift") and -1 or 1) end
    if key == "q" then turnCamera(-1) end
    if key == "p" then paused = not paused; sound(paused and "pause" or "unpause") end
    if key == "r" and (game.phase == "won" or game.phase == "lost" or love.keyboard.isDown("lshift")) then sound("go"); start() end
    if key == "m" then sound("back"); openMenu() end
    -- Won: on to the next level.
    if key == "n" and game.phase == "won" then afterWin("next") end
end

-- Where the camera should go to show `s` (a tower, mat or shelf) beside the
-- info panel: a third of the way across a wide screen, the panel on the right;
-- and half way down; on a narrow one in the middle of what is left under the
-- panel.
local function focusOn(s)
    local x, y, z
    if s.node then x, y, z = s.node.x, s.node.y + 6, s.node.z else x, y, z = s.x, (s.y or 0) + 3, s.z end
    local i, j = world:toImage(x, y, z)
    local hx, hy = (i - camx) * zoom / uz, (j - camy) * zoom / uz
    local wx, wy
    if wide() then
        wx, wy = floor(vw / 3), floor(vh / 2)
    else
        local P = info()
        wx = floor(vw / 2)
        wy = floor((P.y + P.h + barTop() - 30) / 2)
    end
    return { x = panx + toBoard(hx - wx), y = pany + toBoard(hy - wy) }
end

-- A tick when the pointer comes onto something that can be pressed (never
-- for a finger, which has no hover).
function audio.hover()
    local k = hover.button or hover.wave or hover.turn or (hover.up and hover.up.branch + 100) or hover.mutation
        or hover.level or hover.challenge or hover.sound or hover.species or hover.back or hover.go or hover.enemy
        or hover.bring or hover.weather or hover.won
    if k ~= nil then k = tostring(k) .. (hover.up and "u" or hover.mutation and "m" or hover.level and "l" or "") end
    if k and k ~= flair.lastHover and not touch then sound("hover") end
    flair.lastHover = k
end

-- What the game cued this frame, played from where on the screen it happened:
-- panned across, and quieter off the edge.
function audio.hear()
    for _, c in ipairs(game.cues) do
        local pan, vol = 0, c.vol or 1
        if c.x then
            local i, j = world:toImage(c.x, world:groundAt(c.x, c.z), c.z)
            local sx, sy = (i - floor(camx)) / cw, (j - floor(camy)) / ch
            pan = sx * 2 - 1
            if sx < -0.05 or sx > 1.05 or sy < -0.05 or sy > 1.05 then vol = vol * 0.35 end
        end
        Sfx.play(c.name, pan, vol)
        -- Some say so in words too.
        local n = c.name
        if n == "wave" then
            local w = game.weather and D.WEATHER[game.weather]
            flair.banner = { text = "WAVE " .. game.wave, sub = w and w.name .. ": " .. w.blurb, k = "r", t = 2.2, max = 2.2 }
        elseif n == "clear" then
            flair.banner = { text = "WAVE " .. game.cleared .. " CLEARED", k = "g", t = 1.8, max = 1.8 }
        elseif n == "unlock" and game.newSpecies then
            flair.banner = { text = "NEW SPECIES: " .. D.TOWER[game.newSpecies].name, k = "l", t = 2.4, max = 2.4 }
        elseif n == "ring" then
            flair.banner = { text = "A FAIRY RING CLOSES", sub = "TOWERS IN IT HIT HARDER. ENEMIES IN IT WADE", k = "l", t = 2.2, max = 2.2 }
        end
    end
    game.cues = {}
end

-- The loops under it all: the soil always, the network's hum as loud as it is
-- alive (and higher the more it carries), the weather's own.
function audio.ambience(dt)
    local want = { soil = 0.35 }
    local pitch
    if game and not menu and not painter then
        local living, surge = 0, false
        for _, l in ipairs(game.links) do
            if l.state == "alive" and l.a.conn then living = living + 1 end
            if l.surge then surge = true end
        end
        want.hum = min(0.5, living * 0.035) * (game.phase == "wave" and 1 or 0.6)
        pitch = 0.9 + 0.2 * min(1, living / 24) + (surge and 0.15 or 0)
        local w = game.weather
        if w == "rain" then want.rain = 0.5
        elseif w == "drought" then want.wind = 0.5
        elseif w == "night" then want.night = 0.4
        elseif w == "frost" then want.frost = 0.45; want.wind = 0.2 end
        if paused then for k, v in pairs(want) do want[k] = v * 0.4 end end
    end
    Sfx.update(dt, want, pitch)
end

function love.update(dt)
    Sfx.warm(0.004)
    audio.ambience(dt)
    flair.pressed = flair.pressed and flair.pressed.t > 0 and flair.pressed or nil
    if flair.pressed then flair.pressed.t = flair.pressed.t - dt end
    flair.nut.t = max(0, flair.nut.t - dt)
    flair.hurt = max(0, flair.hurt - dt)
    flair.note = max(0, flair.note - dt)
    if flair.banner then
        flair.banner.t = flair.banner.t - dt
        if flair.banner.t <= 0 then flair.banner = nil end
    end
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
            -- The other three sides of the board are painted in the background,
            -- a slice a frame, so the camera can go round at once.
            if not script and not world.backPainter then
                local w = world
                w.backPainter = coroutine.create(function()
                    for q = 0, World.TURNS - 1 do
                        if not w:painted(q) then w:paint(q) end
                    end
                end)
            end
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
                    selection = function() return selected end,
                    menu = function(on) if on then openMenu() else menu = nil end end,
                    loadout = function(n) if n then openLoadout(n) else menu, pick = nil, nil end end,
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
        if pick then pick.full = max(0, (pick.full or 0) - dt) end
        findHover()
        audio.hover()
        if script then
            script.update(game, 1 / 30)
            photograph()
        end
        return
    end
    local bg = world.backPainter
    if bg and coroutine.status(bg) ~= "dead" then
        local t0 = love.timer.getTime()
        while coroutine.status(bg) ~= "dead" and love.timer.getTime() - t0 < 0.004 do
            local ok, err = coroutine.resume(bg)
            if not ok then error(err) end
        end
    end
    dt = min(dt, 1 / 30)
    if script then dt = 1 / 30 end
    if turning then
        turning.t = turning.t + dt
        if turning.t >= TURN_TIME then
            turning.old:release()
            turning = nil
        end
    end

    local k = love.keyboard.isDown
    local pan = 120 * dt
    if k("left", "a", "right", "d", "up", "w", "down", "s") then focus = nil end
    if k("left", "a") then panx = panx - pan end
    if k("right", "d") then panx = panx + pan end
    if k("up", "w") then pany = pany - pan end
    if k("down", "s") then pany = pany + pan end
    -- Something newly selected: ease the camera to put it beside its panel.
    if selected ~= focused then
        focused = selected
        focus = selected and info() and focusOn(selected) or nil
    end
    if focus then
        local e = 1 - math.exp(-dt * 9)
        panx, pany = panx + (focus.x - panx) * e, pany + (focus.y - pany) * e
        if abs(focus.x - panx) < 0.5 and abs(focus.y - pany) < 0.5 then panx, pany, focus = focus.x, focus.y, nil end
    end
    -- Zoomed in, the board is bigger than the screen: let every edge of it be
    -- reached, with a little ground to spare. With a panel open, further, so a
    -- tower at the board's edge can still come out beside it. Past the edge the
    -- camera eases back rather than stopping dead.
    local limx = max(40, (world.w - (cw - toBoard(inset.l + inset.r))) / 2 + 40)
    local limy = max(60, (world.h - (ch - toBoard(inset.t + inset.b + TOP + BOTTOM))) / 2 + 40)
    if info() then limx, limy = limx + cw / 2, limy + ch / 2 end
    local cx, cy = max(-limx, min(limx, panx)), max(-limy, min(limy, pany))
    if cx ~= panx or cy ~= pany then
        local e = min(1, dt * 12)
        panx, pany = panx + (cx - panx) * e, pany + (cy - pany) * e
    end
    centre()

    if script then script.update(game, dt) end
    findHover()
    audio.hover()
    if not paused then
        for _ = 1, speed do
            game:update(dt)
            if game.events.heart then heartFlash, flair.hurt = 0.15, 0.45 end
            if game.events.shake then shake = max(shake, game.events.shake) end
        end
    end
    audio.hear()
    -- A lot coming in at once (a body drunk, a wave's bonus): the count glows.
    if game.nutrients - flair.lastNut >= 3 and (flair.nut.t <= 0 or flair.nut.k ~= "r") then flair.nut = { t = 0.35, k = "w" } end
    flair.lastNut = game.nutrients
    -- The sprout low: a heartbeat, heard and seen at the screen's edge.
    local low = game.phase == "wave" and game.heartHp > 0 and game.heartHp < game.heartMax * 0.3
    local b = low and not paused and (game.clock % 1.2) < 0.15
    if b and not flair.beat then Sfx.play("stomp", 0, 0.6, 0.6) end
    flair.beat = b
    heartFlash = max(0, heartFlash - dt)
    shake = max(0, shake - dt)
    if game.best > (records[level.id] or 0) and not script then
        records[level.id] = game.best
        saveRecords()
    end
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
    -- A salted link never regrows, so it has no gap: it lies there whole, crusted.
    if l.state == "cut" and not l.salted then
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
                local u = under
                if l.state == "cut" and l.salted then
                    -- Crusted over: cream and grey crystals on an ash bed, a few
                    -- of them catching the light, and a rust cross on the middle
                    -- of it: dead, prune it.
                    k, u = highlight or ((s % 3 == 1) and IDX.s or IDX.w), IDX.k
                    if s % 4 == 0 and floor(t * 3 + s * 0.37) % 3 == 0 then put(IDX.w, i, j - 1) end
                    if s == floor(steps / 2) then
                        put(IDX.r, i - 2, j - 2); put(IDX.r, i - 1, j - 1); put(IDX.r, i + 1, j + 1); put(IDX.r, i + 2, j + 2)
                        put(IDX.r, i + 2, j - 2); put(IDX.r, i + 1, j - 1); put(IDX.r, i - 1, j + 1); put(IDX.r, i - 2, j + 2)
                        k = IDX.r
                    end
                elseif l.state == "cut" then
                    k = (l.hand or l.regrow > 0) and IDX.c or IDX.n
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
                -- Just cut, it flashes white then rust; just grown or regrown,
                -- white then glow, running out from the middle.
                if l.flash and not highlight then
                    local hot = l.flash > 0.15
                    if l.state == "cut" then k = hot and IDX.w or IDX.r
                    elseif abs(f - 0.5) < (0.35 - l.flash) * 1.6 + 0.1 then k = hot and IDX.w or IDX.l end
                end
                put(u, i, j + 1)
                if l.thick then put(u, i, j + 2) end
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
    local i0, i1, j0, j1 = screenBox(x0, x1, 0, 4, z0, z1)
    for j = max(0, j0), min(world.h - 1, j1) do
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
        return M.ant(turned(e.h), floor(e.anim * rate) % 2)
    elseif k == "pillbug" then
        if e.rolling then return M.pillbug(turned(e.h), true, floor(e.anim * 12) % 4) end
        return M.pillbug(turned(e.h), false)
    elseif k == "mite" then
        return M.mite(turned(e.h))
    elseif k == "gnat" then
        return M.gnat(turned(e.h), floor(e.anim * 20) % 2)
    elseif k == "slug" then
        return M.slug(turned(e.h), floor(e.anim * (e.state == "eat" and 4 or 2)) % 2)
    elseif k == "spider" then
        return M.spider(turned(e.h), floor(e.anim * 10) % 2)
    elseif k == "knight" then
        return M.knight(turned(e.h), floor(e.anim * 6) % 2)
    elseif k == "queen" then
        return M.queen(turned(e.h), floor(e.anim * 5) % 2)
    elseif k == "stag" then
        return M.stag(turned(e.h), floor(e.anim * (e.charging and 14 or 6)) % 2, e.charging ~= nil)
    elseif k == "dung" then
        -- It walks backwards, pushing: its picture faces away from the way it goes.
        return M.dung(turned(e.h + math.pi), floor(e.anim * 5) % 2)
    elseif k == "moth" then
        return M.moth(turned(e.h), floor(e.anim * 12) % 2)
    elseif k == "waterbug" then
        return M.waterbug(turned(e.h), floor(e.anim * 5) % 2, e.state == "grab" or e.state == "lunge")
    elseif k == "centipede" then
        return M.centipede(turned(e.h), floor(e.anim * 8) % 2)
    elseif k == "centseg" then
        return M.centseg(turned(e.h), floor(e.anim * 8 + (e.x + e.z) * 0.1) % 2)
    elseif k == "bombardier" then
        return M.bombardier(turned(e.h), floor(e.anim * 6) % 2, e.state == "siege")
    elseif k == "springtail" then
        return M.springtail(turned(e.h), floor(e.anim * 9) % 2, e.hopT ~= nil)
    elseif k == "click" then
        if e.state == "belly" then return M.click(turned(e.h), floor(e.anim * 8) % 2, "belly") end
        if e.state == "leap" then return M.click(turned(e.h), 0, "leap", floor((e.spin or 0) * 4) % 4) end
        return M.click(turned(e.h), floor(e.anim * 5) % 2)
    end
    return M.brine(floor(e.anim * 4) % 2)
end

local SHADOW = { ant = 4, pillbug = 4.5, brine = 3.5, gnat = 2.5, slug = 6, spider = 5, knight = 5,
    queen = 11, stag = 13, dung = 10, moth = 3.5, waterbug = 12, centipede = 6, centseg = 5.5, bombardier = 10,
    springtail = 3, click = 10 }

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
    local i0, i1, j0, j1 = screenBox(x - r, x + r, g - 1, g + 6, z - r, z + r)
    for j = max(0, j0), min(world.h - 1, j1) do
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
    local i0, i1, j0, j1 = screenBox(x - r, x + r, g - 1, g + 4, z - r, z + r)
    for j = max(0, j0), min(world.h - 1, j1) do
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

-- A sterilised pocket: a crust of salt on the ground round it, drying back to
-- nothing as the 12 s run out, and a cream bar over it for the time left.
local function saltCrust(n)
    local frac = min(1, n.salted / 12)
    local r = 3 + 5 * frac
    local g = world:groundAt(n.x, n.z)
    local i0, i1, j0, j1 = screenBox(n.x - r, n.x + r, g - 1, g + 4, n.z - r, n.z + r)
    for j = max(0, j0), min(world.h - 1, j1) do
        for i = max(0, i0), min(world.w - 1, i1) do
            local p = j * world.w + i
            local d2 = (world.wx[p] - n.x) ^ 2 + (world.wz[p] - n.z) ^ 2
            if world.up[p] == 1 and d2 <= r * r then
                if d2 < (r * 0.55) ^ 2 then
                    put((i + j) % 2 == 0 and IDX.w or IDX.s, i, j)
                elseif (i + 2 * j) % 3 == 0 then
                    put(IDX.w, i, j)
                end
            end
        end
    end
end

-- On the pocket itself, over its threads: a glinting crystal where the knot
-- would be.
local function saltKnot(n)
    local i, j = world:toImage(n.x, n.y + 0.5, n.z)
    i, j = floor(i), floor(j)
    put(IDX.k, i - 1, j + 1); put(IDX.k, i + 1, j + 1); put(IDX.k, i, j + 2)
    put(IDX.s, i - 1, j); put(IDX.s, i + 1, j); put(IDX.w, i, j - 1); put(IDX.w, i, j + 1)
    put(floor(game.clock * 4) % 2 == 0 and IDX.w or IDX.s, i, j)
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

-- A ring running out over the ground: a landing, a blast, a thing grown. It
-- thins as it goes, a pixel at a time, rather than fading.
function flair.shock(p)
    local f = 1 - p.life / p.max
    local e = 1 - (1 - f) ^ 2
    local r = max(1, p.r * e)
    local n = max(12, floor(r * 1.5))
    local k, k2 = IDX[p.k], IDX[p.k2 or p.k]
    for s = 0, n - 1 do
        if ((s * 7) % 10) / 10 >= f * 0.85 then
            local a = s / n * 2 * math.pi
            local c, sn = math.cos(a), math.sin(a)
            local x, z = p.x + c * r, p.z + sn * r
            local i, j, d = world:toImage(x, world:groundAt(x, z) + 0.4, z)
            if visible(floor(i), floor(j), d + 1) then put(k, i, j) end
            if r > 3 and s % 2 == 0 then
                x, z = p.x + c * (r - 1.5), p.z + sn * (r - 1.5)
                i, j, d = world:toImage(x, world:groundAt(x, z) + 0.4, z)
                if visible(floor(i), floor(j), d + 1) then put(k2, i, j) end
            end
        end
    end
end

-- What a kill or a blast leaves on the ground, wearing away from the edge in.
function flair.splat(p)
    local r = p.r
    local fade = min(1, p.life / p.max * 1.5)
    local g = world:groundAt(p.x, p.z)
    local i0, i1, j0, j1 = screenBox(p.x - r, p.x + r, g - 1, g + 4, p.z - r, p.z + r)
    local k = IDX[p.k]
    local dk = T.DARKER[k]
    for j = max(0, j0), min(world.h - 1, j1) do
        for i = max(0, i0), min(world.w - 1, i1) do
            local n = j * world.w + i
            if world.up[n] == 1 then
                local q = ((world.wx[n] - p.x) ^ 2 + (world.wz[n] - p.z) ^ 2) / (r * r)
                if q <= 1 then
                    local h = ((i * 73 + j * 151 + p.seed * 17) % 97) / 97
                    if h < fade * (1 - q * 0.7) then put(q < 0.25 and dk or k, i, j) end
                end
            end
        end
    end
end

local function drawBoard()
    -- A boss charging, a ball bursting: the board jumps.
    -- Drawn over the whole picture, pad and all: for the moment, it is the window.
    local cx0, cy0, cw0, ch0 = camx, camy, cw, ch
    camx, camy = floor(camx) - pad.l, floor(camy) - pad.t
    cw, ch = cw + pad.l + pad.r, ch + pad.t + pad.b
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
    for _, p in ipairs(game.fx) do if p.splat then flair.splat(p) end end
    for _, p in ipairs(game.fx) do if p.shock then flair.shock(p) end end
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
            local look = towerLook(m, m.c + m.r)
            if selected == m then outline(look, m.x, m.y, m.z, IDX.w) end
            stamp(look, m.x, m.y, m.z, fading and T.DARKER or nil)
        end
    end
    local trailMode = D.TOWER[mode] and D.TOWER[mode].onTrail
    if trailMode and hover.c and not hover.button and mode == "mat" and world:distAt(hover.c, hover.r) then
        local ok = game:canLay(mode, hover.c, hover.r)
        stamp(M.tower(mode), hover.c * 16 + 8, world:groundAt(hover.c * 16 + 8, hover.r * 16 + 8), hover.r * 16 + 8, ok and T.DARKER or T.DARKER2)
    end
    for _, n in ipairs(game.nodes) do
        if (n.salted or 0) > 0 then saltCrust(n) end
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
        if (n.salted or 0) > 0 then
            saltKnot(n)
            bar(n.x, n.y + 9, n.z, min(1, n.salted / 12), IDX.w)
        elseif not n.heart and not n.tower and #n.links > 0 then
            knot(n, n.conn and IDX.c or IDX.d)
        end
    end

    -- Fairy rings: the ground inside goes to moss, and a ring of tiny white
    -- caps comes up along the loop.
    for _, r in ipairs(game.rings) do drawRing(r) end

    -- A species in hand: every pocket it could grow on, lined in one pixel
    -- as a selected tower is.
    if D.TOWER[mode] and not D.TOWER[mode].onTrail then
        local rims = world:rims()
        for k in ipairs(world.pockets) do
            local r = rims[k]
            if r and game:canBuild(mode, game.nodes[k + 1]) then
                for q = 1, #r, 3 do
                    if visible(r[q], r[q + 1], r[q + 2]) then put(IDX.w, r[q], r[q + 1]) end
                end
            end
        end
    end

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
        local _, _, d = world:toImage(x, y, z)
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
                local look = towerLook(t, n.id)
                -- Picked up to pull a thread from, or selected: lined in one pixel.
                if mode == "grow" and drag == n then outline(look, n.x, n.y, n.z, IDX.l)
                elseif selected == t then outline(look, n.x, n.y, n.z, IDX.w) end
                stamp(look, n.x, n.y, n.z, t.flash > 0 and T.FLASH or remapFor(t))
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
                local look = towerLook(m, m.c + m.r)
                if selected == m then outline(look, m.x, m.y, m.z, IDX.w) end
                stamp(look, m.x, m.y, m.z, m.chewed and floor(game.clock * 10) % 2 == 0 and T.DARKER or nil)
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
            stamp(M.corpse(c.kind, turned(c.h or 0), c.fruit), c.x, g + (c.carried and 2.5 or 0), c.z, remap)
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
                stamp(M.ball(turned(e.h), floor((e.ballRoll or 0) * 3) % 4, cracked), bx, g, bz, e.ballFlash > 0 and T.FLASH or nil)
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
        elseif p.shock or p.splat then
            -- On the ground, drawn with it.
        elseif p.star then
            -- A needle's shot leaving: a cross of light at its tip.
            local i, j, d = world:toImage(p.x, p.y, p.z)
            i, j = floor(i), floor(j)
            if visible(i, j, d + 3) then
                local k = IDX[p.k]
                put(IDX.w, i, j)
                put(k, i - 1, j); put(k, i + 1, j); put(k, i, j - 1); put(k, i, j + 1)
                if p.life > p.max * 0.5 then put(k, i - 2, j); put(k, i + 2, j) end
            end
        elseif p.thread then
            -- A pruned thread: it drops to the soil and goes, from the middle out.
            local f = 1 - p.life / p.max
            local len = sqrt((p.bx - p.ax) ^ 2 + (p.bz - p.az) ^ 2)
            local steps = max(2, ceil(len / 0.8))
            for s = 0, steps do
                local u = s / steps
                if abs(u - 0.5) > f * 0.55 and (s * 7) % 10 >= f * 6 then
                    local x, z = p.ax + (p.bx - p.ax) * u, p.az + (p.bz - p.az) * u
                    local y = max(world:groundAt(x, z) + 0.3, p.ay + (p.by - p.ay) * u - f * 3)
                    local i, j, d = world:toImage(x, y, z)
                    if visible(floor(i), floor(j), d + 1.5) then put(f < 0.3 and IDX.t or IDX.n, i, j) end
                end
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
    camx, camy, cw, ch = cx0, cy0, cw0, ch0
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

-- Centred across the screen, or about `mid`.
local function centred(s, y, k, fill, mid)
    label(s, floor((mid or vw / 2) - Font.width(s) / 2), y, k, fill)
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
        return say("UPGRADES: CLICK ONE IN THE PANEL, OR Z / C", "UPGRADES: TAP ONE IN THE PANEL"), "l"
    end
    if game.wave == 0 then return say("SPACE TO START THE FIRST WAVE", "TAP START FOR THE FIRST WAVE"), "g" end
end

local function tooltip()
    if hover.mutation then
        local m = game.choices[hover.mutation]
        return m.name .. ": " .. m.blurb, "l"
    end
    if game.phase == "mutate" then return say("THE NETWORK MUTATES. PICK ONE (1 2 3)", "THE NETWORK MUTATES. PICK ONE"), "l" end
    if hover.up then
        local ok, why = game:canUpgrade(selected, hover.up.branch)
        return "GROW " .. hover.up.row.name .. ": " .. hover.up.row.cost .. (ok and "" or ("  (" .. why .. ")")), ok and "l" or "r"
    end
    if hover.button then
        local b = BUTTONS[hover.button]
        if b.tower and not game:unlocked(b.mode) then
            return b.name .. ": UNLOCKS AFTER WAVE " .. game:unlockAt(b.mode), "r"
        end
        if b.action then
            local list, cost = game:repairable(), 0
            for _, l in ipairs(list) do cost = cost + game:repairCost(l) end
            if #list == 0 then return "REGROW ALL: NO CUT LINKS", "s" end
            return "REGROW " .. #list .. " CUT LINK" .. (#list > 1 and "S" or "") .. ", NEAREST THE SPROUT FIRST: " .. cost,
                game.nutrients >= cost and "l" or "r"
        end
        if b.tower and b.mode == mode then return say(b.name .. ": CLICK AGAIN TO READ IT", b.name .. ": TAP AGAIN TO READ IT"), "w" end
        return b.name .. (b.cost and (" (" .. b.cost .. ")") or "") .. ": " .. b.blurb, "w"
    end
    if hover.turn == 1 then return say("TURN THE BOARD (E)", "TURN THE BOARD"), "w" end
    if hover.turn == -1 then return say("TURN THE BOARD BACK (Q)", "TURN THE BOARD BACK"), "w" end
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
    if mode == "grow" and drag then return say("LET GO OVER A GLOWING POCKET", "LET GO OVER A GLOWING POCKET"), "l" end
    if mode == "pulse" then
        if game.pulseCd > 0 then return "PULSE REGROWING: " .. math.ceil(game.pulseCd) .. "S", "r" end
        return say("CLICK A FED NODE TO SEND THE PULSE", "TAP A FED NODE TO SEND THE PULSE"), "l"
    end
end

local drawInfo -- the info panel, drawn by the HUD and the loadout (below)

-- A turn button: a ring of ground going round, an arrowhead on its end, and
-- a mark on the ring for the side the camera is on. d = -1 is the clockwise
-- one mirrored.
local function drawTurnButton(d)
    local x, y, w, h = turnRect(d)
    local going = turning and turning.d == d
    box(x, y, w, h, (hover.turn == d or going) and "n" or "u", hover.turn == d and "t" or "o")
    local cx, cy = x + floor(w / 2), y + floor(h / 2) + 1
    local spin = turning and turning.t / TURN_TIME * (turning.angle > 0 and 1 or -1) * d or 0
    local function at(a, rx, ry) return cx + floor(d * math.cos(a) * rx + 0.5), cy + floor(math.sin(a) * ry + 0.5) end
    -- The ring is the ground seen from the camera: twice as wide as it is deep.
    color("k")
    for s = 0, 23 do
        local i, j = at(s / 24 * 2 * math.pi, 7, 4)
        love.graphics.rectangle("fill", i, j, 1, 1)
    end
    color("w")
    local a0 = (spin - 0.15) * math.pi * 0.5
    for s = 0, 12 do
        local i, j = at(a0 + s / 24 * 2 * math.pi, 7, 4)
        love.graphics.rectangle("fill", i, j, 1, 1)
    end
    -- The arrowhead at the end of the arc, pointing on round.
    local ae = a0 + 12 / 24 * 2 * math.pi
    local i, j = at(ae, 7, 4)
    love.graphics.rectangle("fill", i - 1, j - 1, 3, 1)
    love.graphics.rectangle("fill", i, j - 2, 1, 1)
    love.graphics.rectangle("fill", i - d, j - 1, 1, 3)
    -- Which side: a dot per view, the one shown lit.
    for q = 0, World.TURNS - 1 do
        color(q == world.turn and "l" or "k")
        love.graphics.rectangle("fill", x + 3 + q * 2, y + 2, 1, 1)
    end
    if not touch then text(d == 1 and "E" or "Q", x + w - 4, y + 1, "s") end
end

local function drawHud()
    -- The top strip.
    color("o")
    love.graphics.rectangle("fill", 0, 0, vw, inset.t + TOP - 1)
    local ty = inset.t + 3
    local inc = game.income or 0
    local s = "NUTRIENTS " .. floor(game.nutrients)
    -- Short of them: red, and a shiver. A lot just in: bright.
    local nk, nx = "l", 0
    if flair.nut.t > 0 then
        nk = flair.nut.k
        if nk == "r" then nx = floor(flair.nut.t * 30) % 2 == 0 and 1 or -1 end
    end
    text(s, inset.l + 3 + nx, ty, nk)
    local x = inset.l + 3 + Font.width(s) + 2
    if game.phase == "wave" then
        local i = (inc >= 0 and "+" or "") .. string.format("%.1f", inc)
        text(i, x + 2, ty, inc >= 0 and "c" or "r")
        x = x + Font.width(i) + 4
    end
    s = "SPROUT " .. math.ceil(game.heartHp) .. "/" .. game.heartMax
    text(s, x + 8, ty, game.heartHp < game.heartMax * 0.4 and "r" or "g")
    local w = "WAVE " .. game.wave .. "/" .. #game.waves
    if game.endless then w = "ENDLESS WAVE " .. game.wave .. "  BEST " .. max(game.best, game.cleared) end
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
    -- Where the weather's name landed, if it is there: the whole strip's
    -- height and a little either side, to be easy to hover or tap.
    weatherBox = nil
    local sky = game.phase == "wave" and game.weather or (game.phase == "build" and nxt and nxt.weather)
    if sky and right ~= w then
        local name = D.WEATHER[sky].name
        local nx = game.phase == "build" and rx + Font.width("NEXT: ") or rx
        weatherBox = { x = nx - 3, y = 0, w = Font.width(name) + 6, h = inset.t + TOP, kind = sky, next = game.phase == "build" }
    end
    if weatherTip and not (weatherBox and weatherBox.kind == weatherTip) then weatherTip = nil end
    if weatherBox and (weatherTip or (not touch and hover.weather)) then
        local wb = weatherBox
        local nm = D.WEATHER[wb.kind].name
        text(nm, wb.x + 3, ty, "t")
    end
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
        if b.action then
            -- A thread with a gap in it, the two ends lit while there are cuts
            -- to mend; how many, and what it all costs.
            local list, cost = game:repairable(), 0
            for _, l in ipairs(list) do cost = cost + game:repairCost(l) end
            local any = #list > 0
            for s = 0, 14 do
                if s < 5 or s > 9 then
                    color("d")
                    love.graphics.rectangle("fill", bx + 8 + s, by + 15 - floor(s / 2) + 1, 1, 1)
                    color(any and ((s == 4 or s == 10) and "r" or "c") or "k")
                    love.graphics.rectangle("fill", bx + 8 + s, by + 15 - floor(s / 2), 1, 1)
                end
            end
            if any then
                local c = tostring(cost)
                text(c, bx + bw - Font.width(c) - 1, by + bh - 6, game.nutrients >= cost and "l" or "r")
                local k = tostring(#list)
                text(k, bx + bw - Font.width(k) - 1, by + 1, "w")
            end
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
    drawTurnButton(1)
    drawTurnButton(-1)

    local tipBase = barTop()

    -- A boss on the board: its name and its health across the top.
    local boss
    for _, e in ipairs(game.enemies) do if e.boss then boss = e break end end
    if boss then
        local d = D.ENEMIES[boss.kind]
        local fl, fr = freeSpan()
        local w = min(170, fr - fl - 20)
        local bx, by = floor((fl + fr - w) / 2), inset.t + TOP + 3
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
        text(name, floor(bx + (w - Font.width(name)) / 2), by + (boss.ballHp and boss.ballHp > 0 and 11 or 7), "w")
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
        local fl, fr = freeSpan()
        local room = fr - fl - 8
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
            centred(l, tipBase - 11 - (#lines - n) * 10, k, nil, floor((fl + fr) / 2))
        end
    end

    local P = info()
    if P then drawInfo(P) end

    -- What the weather does, dropped from its name in the top strip.
    local wb = weatherBox
    if wb and (weatherTip or (not touch and hover.weather)) then
        local d = D.WEATHER[wb.kind]
        local tw = min(150, vw - inset.l - inset.r - 8)
        local lines = wrapLines(d.blurb, tw - 8)
        local head = d.name .. (wb.next and " NEXT WAVE" or "")
        local th = 13 + 7 * #lines
        local tx = max(inset.l + 4, min(vw - inset.r - 4 - tw, wb.x + floor(wb.w / 2) - floor(tw / 2)))
        local ty = inset.t + TOP + 3
        box(tx, ty, tw, th, "u", "t")
        text(head, tx + 4, ty + 3, "t")
        for n, l in ipairs(lines) do text(l, tx + 4, ty + 6 + 7 * n, "w") end
        if touch then text("X", tx + tw - 7, ty + 3, "s") end
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
        local buttons = wonButtons()
        for _, b in ipairs(buttons) do
            local on = hover.won == b.id
            local endless = b.id == "endless"
            box(b.x, b.y, b.w, b.h, on and "n" or "u", endless and "r" or (on and "l" or "c"))
            text(b.text, b.x + 5, b.y + 5, endless and "r" or "w")
        end
        local y = buttons.bottom + 1
        if records[level.id] then centred("ENDLESS BEST: " .. records[level.id] .. " WAVES", y, "t"); y = y + 10 end
        if last and not game.challenge then centred("CHALLENGE MODE IS OPEN", y, "r") end
    elseif game.phase == "lost" then
        centred("THE SPROUT HAS WILTED", floor(vh / 2) - 24, "r")
        if game.endless then
            centred("ENDLESS: YOU HELD " .. game.cleared .. " WAVES", floor(vh / 2) - 12, "w")
            centred(game.record and "A NEW RECORD!" or ("BEST " .. game.best), floor(vh / 2) + 12, game.record and "g" or "t")
        else
            centred("YOU HELD " .. (game.wave - 1) .. " WAVES OF " .. #game.waves, floor(vh / 2) - 12, "w")
        end
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
    centred("GROUTE", cards[1].y - 30, "g", "o")
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
            -- The endless record, bottom left, once there is one.
            if records[l.id] then text("BEST " .. records[l.id], c.x + 4, c.y + c.h - 8, "r") end
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
    local sw = audio.switch()
    local lv = Sfx.level >= 1 and "LOUD" or (Sfx.level > 0 and "QUIET" or "OFF")
    box(sw.x, sw.y, sw.w, sw.h, hover.sound and "n" or "u", Sfx.level > 0 and "c" or "k")
    local st = "SOUND " .. lv
    text(st, sw.x + floor((sw.w - Font.width(st)) / 2), sw.y + 3, Sfx.level > 0 and "l" or "k")
    local hintY = vh - inset.b - 12
    centred(say("1-" .. #D.LEVELS .. " OR CLICK A LEVEL", "TAP A LEVEL") .. (challengeOpen() and say("   C: CHALLENGE", "") or ""), hintY, "s", "o")
end

-- The info panel, its lines kept inside it (a short screen cuts the end).
function drawInfo(P)
    box(P.x, P.y, P.w, P.h, "u", "c")
    love.graphics.setScissor(P.x, P.y, P.w, P.h)
    local clock = love.timer.getTime()
    local t = P.t
    local pic = icon(P.kind, t and t.branch, t and t.tier or 0, (clock * 0.7) % 1)
    love.graphics.setScissor(P.x, P.y, 22, 24)
    blit(pic, P.x + 12, P.kind == "mat" and P.y + 16 or P.y + 22)
    love.graphics.setScissor(P.x, P.y, P.w, P.h - (P.button and 20 or 0))
    for _, l in ipairs(P.lines) do
        local y = l.y
        if l.up then
            -- An upgrade it can grow now: a button, its key beside the cost.
            local can = game:canUpgrade(P.t, l.up.branch)
            local on = hover.up and hover.up.branch == l.up.branch
            local bx, bw = P.x + 3, P.w - 6
            box(bx, y, bw, l.h - 3, on and "n" or (can and "d" or "o"), can and "l" or "k")
            text((l.up.tier == 1 and "I  " or "II ") .. l.row.name, bx + 2, y + 2, "w")
            local cost = tostring(l.row.cost)
            if not touch then
                local ups = game:upgrades(P.t)
                cost = (#ups == 1 and "Z/C" or (l.up.branch == ups[1].branch and "Z" or "C")) .. " " .. cost
            end
            text(cost, bx + bw - Font.width(cost) - 2, y + 2, can and "l" or "r")
            for n, s in ipairs(l.blurb) do text(s, bx + 2, y + 2 + 2 + 7 * n, can and "s" or "k") end
        elseif l.s then
            text(l.s, P.x + 4 + l.x, y, l.k)
        end
    end
    love.graphics.setScissor()
    local b = P.button
    if b then
        local inn = pick.set[P.kind]
        local full = not inn and #picked() >= D.LOADOUT
        local s = inn and "LEAVE IT AT HOME" or (full and "SIX ALREADY: DROP ONE" or "BRING IT")
        box(b.x, b.y, b.w, b.h, hover.bring and "n" or (inn and "u" or "d"), full and "k" or (inn and "t" or "g"))
        text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 4, full and "k" or (inn and "w" or "g"))
    end
end

local function drawLoadout()
    color("o")
    love.graphics.rectangle("fill", 0, 0, vw, vh)
    local lv = D.LEVELS[pick.n]
    local L = loadoutLayout()
    local list = picked()
    local clock = love.timer.getTime()
    centred(lv.name .. (challenge and " (CHALLENGE)" or ""), L.top, "g", "o", L.mid)
    local count = #list .. "/" .. D.LOADOUT
    centred("PICK THE SPECIES TO BRING  " .. count, L.top + 11, #list == D.LOADOUT and "l" or "t", "o", L.mid)
    text("COMING", floor(L.mid - Font.width("COMING") / 2), L.chipsY - 9, "s")

    -- The enemy pointed at (or pinned) lights up what answers it.
    local enemy = hover.enemy or pick.enemy
    local answers = {}
    for _, id in ipairs(enemy and D.COUNTERS[enemy] or {}) do answers[id] = true end
    for _, c in ipairs(L.chips) do
        local boss = D.ENEMIES[c.kind].boss
        local on = enemy == c.kind
        box(c.x, c.y, c.w, c.h, on and "n" or "u", on and "w" or (boss and "r" or "k"))
        text(c.name, c.x + 3, c.y + 2, boss and "r" or "w")
    end

    for _, c in ipairs(L.cards) do
        local t = c.t
        local inn, on, ans = pick.set[t.id], hover.species == t.id, answers[t.id]
        local edge = inn and "l" or "k"
        if ans and floor(clock * 4) % 2 == 0 then edge = "w" end
        if on or pick.info == t.id then edge = inn and "w" or "t" end
        box(c.x, c.y, c.w, c.h, (inn or on) and "n" or "u", edge)
        -- The picture kept to its corner of the card: a shelf or the giant is wider.
        local pic = icon(t.id, nil, 0, inn and (clock * 0.7) % 1 or 0)
        love.graphics.setScissor(c.x, c.y, 21, c.h)
        blit(pic, c.x + 11, t.id == "mat" and c.y + c.h - 8 or c.y + c.h - 3, not inn and T.DARKER2 or nil)
        love.graphics.setScissor()
        wrap(t.name, c.x + 22, c.y + 3, c.w - 24, inn and "w" or "s")
        text(tostring(t.cost), c.x + 22, c.y + c.h - 7, inn and "l" or "k")
        -- On the Crack a species still comes when its wave is cleared.
        local at = lv.unlock and lv.unlock[t.id] or (not lv.open and t.unlock) or 0
        if at > 0 then
            local s = "W" .. at
            text(s, c.x + c.w - Font.width(s) - 2, c.y + c.h - 7, "k")
        end
        if not touch then text(t.key, c.x + 1, c.y + 1, "s") end
        if ans then text("!", c.x + c.w - 4, c.y + 2, "w") end
    end

    local b, g = L.back, L.go
    box(b.x, b.y, b.w, b.h, hover.back and "n" or "u", hover.back and "t" or "k")
    text("BACK", b.x + floor((b.w - Font.width("BACK")) / 2), b.y + 5, "w")
    local ready = #list > 0
    box(g.x, g.y, g.w, g.h, ready and (hover.go and "m" or "d") or "u", ready and "g" or "k")
    text("GROW", g.x + floor((g.w - Font.width("GROW")) / 2), g.y + 5, ready and "g" or "k")

    local P = info()
    if P then
        drawInfo(P)
        if pick.full > 0 then centred("ONLY " .. D.LOADOUT .. " COME. DROP ONE FIRST", g.y + g.h + 6, "r", "o", L.mid) end
        return
    end

    -- One line under it all: what is pointed at, or how it works.
    local tip, k
    if pick.full > 0 then
        tip, k = "ONLY " .. D.LOADOUT .. " COME. DROP ONE FIRST", "r"
    elseif hover.species then
        local t = D.TOWER[hover.species]
        tip, k = t.name .. ": " .. t.blurb, "w"
    elseif enemy then
        local names = {}
        for _, id in ipairs(D.COUNTERS[enemy] or {}) do names[#names + 1] = D.TOWER[id].name end
        tip, k = D.ENEMIES[enemy].name .. ": " .. D.ENEMIES[enemy].blurb:gsub("%.?$", ".") .. " ANSWER: " .. table.concat(names, ", "), "t"
    elseif not ready then
        tip, k = "BRING AT LEAST ONE", "r"
    else
        tip, k = say("CLICK A SPECIES TO READ IT, AGAIN TO BRING OR LEAVE IT. POINT AT AN ENEMY FOR ITS ANSWER",
            "TAP A SPECIES TO READ IT, AGAIN TO BRING OR LEAVE IT. TAP AN ENEMY FOR ITS ANSWER"), "s"
    end
    local room = vw - inset.l - inset.r - 8
    local y = g.y + g.h + 6
    -- Too long for one line: broken at words, as many lines as it takes.
    local line = ""
    for word in tip:gmatch("%S+") do
        local try = line == "" and word or line .. " " .. word
        if Font.width(try) > room then
            centred(line, y, k, "o")
            line, y = word, y + 9
        else
            line = try
        end
    end
    centred(line, y, k, "o")
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

-- Over whatever screen is up: the thing just pressed lit, the screen's edge
-- red when the sprout is hit (and on each heartbeat when it is low), a word
-- when a wave comes or goes, and how loud the sound is when V changes it.
function flair.draw()
    if painter then return end
    local function px(x, y, w, h) love.graphics.rectangle("fill", x, y, w or 1, h or 1) end
    if not menu and game and (flair.hurt > 0 or flair.beat) then
        local deep = flair.hurt > 0.2 and 4 or 2
        color("r")
        for d = 0, deep - 1 do
            local step = d + 1
            for x = (d % step), vw - 1, step do px(x, d); px(x, vh - 1 - d) end
            for y = (d % step), vh - 1, step do px(d, y); px(vw - 1 - d, y) end
        end
    end
    if flair.banner and not menu then
        local age = flair.banner.max - flair.banner.t
        if flair.banner.t > 0.3 or floor(flair.banner.t * 12) % 2 == 0 then
            local y = floor(vh * 0.28) - floor(max(0, 0.15 - age) / 0.15 * 8)
            centred(flair.banner.text, y, flair.banner.k, "o")
            local w = floor(min(1, age / 0.3) * (Font.width(flair.banner.text) + 4))
            color(flair.banner.k)
            px(floor(vw / 2 - w / 2), y + 8, w, 1)
            local sub = flair.banner.sub
            if sub and Font.width(sub) > vw - inset.l - inset.r - 12 then sub = sub:match("^[^:]+") end
            if sub then centred(sub, y + 12, "w", "o") end
        end
    end
    if flair.note > 0 then
        local lv = Sfx.level >= 1 and "LOUD" or (Sfx.level > 0 and "QUIET" or "OFF")
        centred("SOUND " .. lv .. "  (V)", inset.t + TOP + 46, Sfx.level > 0 and "l" or "k", "o")
    end
    if flair.pressed and flair.pressed.t > 0 then
        local ok, x, y, w, h = pcall(flair.pressed.rect)
        if ok and x then
            local hot = flair.pressed.t > 0.09
            color(hot and "w" or "l")
            px(x - 2, y - 2, w + 4, 1); px(x - 2, y + h + 1, w + 4, 1)
            px(x - 2, y - 2, 1, h + 4); px(x + w + 1, y - 2, 1, h + 4)
            if hot then
                px(x - 1, y - 1, w + 2, 1); px(x - 1, y + h, w + 2, 1)
                px(x - 1, y - 1, 1, h + 2); px(x + w, y - 1, 1, h + 2)
            end
        end
    end
end

function love.draw()
    -- The HUD's picture starts empty each frame (nothing where the board shows
    -- through) and everything on it is drawn solid, so laying it over the board
    -- covers a pixel fully or not at all.
    love.graphics.setCanvas(ui)
    love.graphics.clear(0, 0, 0, 0)
    if painter then
        drawLoading()
    elseif menu == "loadout" then
        drawLoadout()
    elseif menu then
        drawMenu()
    else
        drawHud()
        love.graphics.setCanvas(canvas)
        drawBoard()
    end
    love.graphics.setCanvas(ui)
    flair.draw()
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    if painter or menu then
        -- Nothing to stretch: the loading bar or the picker is the whole screen.
    elseif turning and not (pinch and not pinch.done) then
        -- Going round: the frame that was left turns half way, then the new
        -- one comes in from the other half, the ground unsquashed for the turn
        -- (so a square stays a square going round) and the whole board lifting
        -- a little off the table and back.
        love.graphics.clear(unpack(T.RGB[IDX.o]))
        local f = turning.t / TURN_TIME
        local e = f * f * (3 - 2 * f)
        local a, pic
        if e < 0.5 then a, pic = turning.angle * e, turning.old
        else a, pic = -turning.angle * (1 - e), canvas end
        local lift = 1 - 0.06 * math.sin(math.pi * e)
        love.graphics.push()
        love.graphics.scale(zoom, zoom)
        love.graphics.translate(turning.px, turning.py)
        love.graphics.scale(lift, lift * 0.5)
        love.graphics.rotate(a)
        love.graphics.scale(1, 2)
        love.graphics.translate(-turning.px, -turning.py)
        love.graphics.draw(pic, 0, 0)
        love.graphics.pop()
    elseif pinch and not pinch.done then
        -- Mid-pinch: the frame stretched about where the fingers started and
        -- moved to where they are (see love.touchpressed).
        love.graphics.clear(unpack(T.RGB[IDX.o]))
        local z = zoom * pinch.s
        love.graphics.draw(canvas, pinch.x - (pinch.x0 + pad.l * zoom) * pinch.s,
            pinch.y - (pinch.y0 + pad.t * zoom) * pinch.s, 0, z, z)
    else
        love.graphics.draw(canvas, -pad.l * zoom, -pad.t * zoom, 0, zoom, zoom)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(ui, 0, 0, 0, uz, uz)
end
