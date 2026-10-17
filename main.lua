-- Mycelio TD: a tower defense where you are the mycelium under a sprout.
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
-- What is kept between runs: wins, records, loadouts, the Spore Bank, the enemies met.
local Profile = require "src.profile"
-- The sound's glue to the screen (the sounds themselves are src/sfx.lua).
local audio = {}

local floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt
local IDX = T.IDX

local S = require "src.ui.state"
local SHORT, TOP, BOTTOM, UI_STEP, ZOOM_STEPS, TURN_TIME = S.SHORT, S.TOP, S.BOTTOM, S.UI_STEP, S.ZOOM_STEPS, S.TURN_TIME
local Draw = require "src.ui.draw"
local color, box, text, label, centred, wrap, wrapLines, number, say, inside, wide =
    Draw.color, Draw.box, Draw.text, Draw.label, Draw.centred, Draw.wrap, Draw.wrapLines, Draw.number, Draw.say, Draw.inside, Draw.wide
local Pixels = require "src.ui.pixels"
local putS, put, putGround, visible, screenBox, turned, stamp, outline, blit, icon, shadow, line3, ring, CUT =
    Pixels.putS, Pixels.put, Pixels.putGround, Pixels.visible, Pixels.screenBox, Pixels.turned, Pixels.stamp,
    Pixels.outline, Pixels.blit, Pixels.icon, Pixels.shadow, Pixels.line3, Pixels.ring, Pixels.CUT
-- The HUD's flourishes, the weather coming and going, and the HUD's own sounds.
local flair = require "src.ui.flair"
local sound, deny = flair.sound, flair.deny
local Toolbar = require "src.ui.toolbar"
local BUTTONS, layTools, buttonRect, waveRect, barTop, turnRect =
    Toolbar.BUTTONS, Toolbar.layTools, Toolbar.buttonRect, Toolbar.waveRect, Toolbar.barTop, Toolbar.turnRect
local Panel = require "src.ui.panel"
local info, freeSpan = Panel.info, Panel.freeSpan
-- The Spore Bank's screen (what it has and sells is src/profile.lua). `offer` is the
-- species a first win put up for sale, shown on the way on: { kind, after = button, bought }.
local bank = {}
-- The encyclopedia (see "the encyclopedia", near the end): its screen.
local codex = {}

-- How loud: 1, 0.5 or 0 (the V key goes round them), kept between runs.
function audio.save() Profile.sound = Sfx.level; Profile.save() end


--- the screen ----------------------------------------------------------------------

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

function love.resize() fit() end
function love.displayrotated() fit() end

-- Sent to the background (a call, the home button, the phone locked): stop
-- the clock rather than let a wave run on unwatched, and the sound with it,
-- until the game is back in front.
audio.shown = { focus = true, visible = true }
function love.focus(f)
    if not f and not S.script and S.game then S.paused = true end
    audio.shown.focus = f
    Sfx.hide(not (audio.shown.focus and audio.shown.visible))
end
function love.visible(v)
    audio.shown.visible = v
    Sfx.hide(not (audio.shown.focus and audio.shown.visible))
end

local function members(set)
    local k = 0
    for _ in pairs(set or {}) do k = k + 1 end
    return k
end

--- the board's camera ----------------------------------------------------------------

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

--- what the mouse is over ------------------------------------------------------------

-- The mutation picker: three cards across the middle, or down it on a narrow screen.
local MW, MH = 118, 40
local function mutationCards()
    local list = S.game.choices or {}
    local n = #list
    local cards = {}
    if S.vw - S.inset.l - S.inset.r >= n * MW + (n - 1) * 6 + 8 then
        local x0 = floor((S.vw - (n * MW + (n - 1) * 6)) / 2)
        for k = 1, n do cards[k] = { x = x0 + (k - 1) * (MW + 6), y = floor(S.vh / 2) - 18, w = MW, h = MH, m = list[k] } end
    else
        local y0 = floor(S.vh / 2 - (n * MH + (n - 1) * 4) / 2)
        for k = 1, n do cards[k] = { x = floor((S.vw - MW) / 2), y = y0 + (k - 1) * (MH + 4), w = MW, h = MH, m = list[k] } end
    end
    return cards
end

-- The level picker: a card a level, in rows of as many as fit across (three
-- on a wide screen, two rows of them; down the middle on a narrow one), and
-- the challenge switch under them once it is open.
local LW, LH = 124, 50
local function levelCards()
    local n = #D.LEVELS
    local cols = max(1, min(3, floor((S.vw - S.inset.l - S.inset.r - 8 + 6) / (LW + 6))))
    local rows = ceil(n / cols)
    local gap = cols == 1 and 4 or 6
    local cards = {}
    local y0 = floor(S.vh / 2 - (rows * LH + (rows - 1) * gap) / 2) - 8
    for k = 1, n do
        local row, col = floor((k - 1) / cols), (k - 1) % cols
        local across = min(cols, n - row * cols)
        local x0 = floor((S.vw - (across * LW + (across - 1) * 6)) / 2)
        cards[k] = { x = x0 + col * (LW + 6), y = y0 + row * (LH + gap), w = LW, h = LH, n = k }
    end
    y0 = y0 + rows * (LH + gap) + 4
    local switch = { x = floor((S.vw - LW) / 2), y = y0, w = LW, h = 16, challenge = true }
    return cards, switch
end

-- What a won level offers, a button each across the middle under the words:
-- the next level (if there is one), endless, again, the levels. Two rows if
-- one does not fit across.
local function wonButtons()
    local list = {}
    local last = S.level == D.LEVELS[#D.LEVELS]
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
        if not S.touch then b.text = b.key .. ": " .. b.text end
        b.w, b.h = Font.width(b.text) + 10, 15
    end
    local rows = { { 1, #list } }
    if width(1, #list) > S.vw - S.inset.l - S.inset.r - 8 then
        local half = ceil(#list / 2)
        rows = { { 1, half }, { half + 1, #list } }
    end
    local y = floor(S.vh / 2) - 1
    for _, row in ipairs(rows) do
        local x = floor((S.vw - width(row[1], row[2])) / 2)
        for k = row[1], row[2] do list[k].x, list[k].y = x, y; x = x + list[k].w + gap end
        y = y + 15 + gap
    end
    list.bottom = y
    return list
end

-- The level picker's sound switch, top right: a finger has no V key.
function audio.switch() return { x = S.vw - S.inset.r - 62, y = S.inset.t + 4, w = 58, h = 12 } end

-- The loadout picker: what the level sends (a chip an enemy, bosses last),
-- a card a species under it, and BACK and GO under those, all centred
-- down the screen. A narrow screen takes fewer cards a row.
local SW, SH = 62, 26
local function enemiesOf(lv)
    local seen = {}
    for _, w in ipairs(lv.waves) do for _, g in ipairs(w) do seen[g[1]] = true end end
    if S.challenge then for _, g in ipairs(D.CHALLENGE) do seen[g[1]] = true end end
    local list = {}
    for _, kind in ipairs(D.ENEMY_ORDER) do if seen[kind] then list[#list + 1] = kind end end
    return list
end

local function loadoutLayout()
    local lv = D.LEVELS[S.pick.n]
    -- With the panel open the picker keeps to the room it leaves: the left on a
    -- wide screen, the top on a narrow one.
    local open = S.pick.info ~= nil or S.pick.seedInfo ~= nil
    local left, right = S.inset.l, S.vw - S.inset.r
    if open and wide() then right = S.vw - S.inset.r - Panel.infoWidth() - 6 end
    local mid = floor((left + right) / 2)
    local avail = right - left - 8
    local cols = 6
    while cols > 2 and cols * SW + (cols - 1) * 4 > avail do cols = cols == 6 and 4 or cols - 1 end
    local rows = ceil(#D.TOWERS / cols)

    -- The chips, flowed into rows as wide as the cards.
    local width = max(cols * SW + (cols - 1) * 4, min(avail, 300))
    local chips, lines, x, line = {}, 1, 0, {}
    -- One not met yet has no name until it is faced.
    local function name(kind) return Profile.seen[kind] and D.ENEMIES[kind].name or "???" end
    for _, kind in ipairs(enemiesOf(lv)) do
        local w = Font.width(name(kind)) + 6
        if x > 0 and x + w > width then lines, x = lines + 1, 0 end
        chips[#chips + 1] = { kind = kind, line = lines, dx = x, w = w, h = 9, name = name(kind) }
        x = x + w + 3
    end
    -- The seeds, chips too: a name each, and the price of one not had yet.
    local seeds, seedRows = {}, 1
    x = 0
    for _, sd in ipairs(D.SEEDS) do
        local s = Profile.seedKnown(sd.id) and sd.short or "???"
        if not Profile.ownsSeed(sd.id) and Profile.seedForSale(sd.id) then s = s .. " " .. sd.price end
        local w = Font.width(s) + 8
        if x > 0 and x + w > width then seedRows, x = seedRows + 1, 0 end
        seeds[#seeds + 1] = { seed = sd, line = seedRows, dx = x, w = w, h = 11, name = s }
        x = x + w + 3
    end

    local height = 22 + 10 + lines * 12 + 6 + 8 + seedRows * 14 + 8 + rows * (SH + 4) + 6 + 16
    local y = max(S.inset.t + 4, floor((S.vh - S.inset.b - 12 - height) / 2))
    if open and not wide() then y = S.inset.t + 4 end
    local top = y
    y = y + 32
    -- Each chip row centred on its own.
    local function flow(list, y0, step)
        local ends = {}
        for _, c in ipairs(list) do ends[c.line] = c.dx + c.w end
        for _, c in ipairs(list) do
            c.x = floor(mid - ends[c.line] / 2) + c.dx
            c.y = y0 + (c.line - 1) * step
        end
    end
    flow(chips, y, 12)
    y = y + lines * 12 + 6
    local seedsY = y + 8
    flow(seeds, seedsY, 14)
    y = seedsY + seedRows * 14 + 8

    local x0 = floor(mid - (cols * SW + (cols - 1) * 4) / 2)
    local cards = {}
    local cardsY = y
    for k, t in ipairs(D.TOWERS) do
        local col, row = (k - 1) % cols, floor((k - 1) / cols)
        cards[k] = { x = x0 + col * (SW + 4), y = y + row * (SH + 4), w = SW, h = SH, t = t }
    end
    y = y + rows * (SH + 4) + 6
    local back = { x = mid - 54, y = y, w = 50, h = 16 }
    local go = { x = mid + 4, y = y, w = 50, h = 16 }
    return { top = top, chips = chips, chipsY = top + 32, seeds = seeds, seedsY = seedsY, cards = cards, cardsY = cardsY,
        back = back, go = go, mid = mid }
end

local function picked()
    local list = {}
    for _, t in ipairs(D.TOWERS) do if S.pick.set[t.id] then list[#list + 1] = t.id end end
    return list
end

-- A species in or out of the loadout. Full, it says so rather than drop one.
local function toggleSpecies(id)
    -- Not had yet: its panel says how to get it.
    if not Profile.owns(id) then S.pick.info = id; deny() return end
    if S.pick.set[id] then S.pick.set[id] = nil; sound("off")
    elseif #picked() >= D.LOADOUT then S.pick.full = 1.5; sound("deny")
    else S.pick.set[id] = true; sound("on") end
end

-- The panel's button: brings or leaves what is had, buys what is for sale.
function bank.bringOrBuy(id)
    if Profile.owns(id) then toggleSpecies(id)
    elseif Profile.buy(id) then sound("unlock")
    else deny() end
end

-- A seed card or its panel's button: plants what is had, buys what is for
-- sale (and plants it).
function bank.plantOrBuy(id)
    if Profile.ownsSeed(id) then
        if S.pick.seed ~= id then S.pick.seed = id; sound("on") end
    elseif Profile.buySeed(id) then S.pick.seed = id; sound("unlock")
    else deny() end
end

-- The Spore Bank after a first win: the species it put up for sale, BUY and
-- ON (LATER until it is bought) under it, all down the middle.
function bank.layout()
    local mid = floor(S.vw / 2)
    local w = min(200, S.vw - S.inset.l - S.inset.r - 8)
    local top = floor(S.vh / 2) - 60
    local card = { x = floor(mid - w / 2), y = top + 24, w = w, h = 48 }
    local by = card.y + card.h + 20
    local L = { mid = mid, top = top, card = card }
    if bank.offer.bought then
        L.on = { x = mid - 32, y = by, w = 64, h = 16 }
    else
        L.buy = { x = mid - 68, y = by, w = 64, h = 16 }
        L.on = { x = mid + 4, y = by, w = 64, h = 16 }
    end
    return L
end

local function nodeScreen(n)
    local i, j = S.world:toImage(n.x, n.y + (n.heart and 10 or 5), n.z)
    return i, j
end

local function findHover()
    S.hover = {}
    local mx, my = S.mouse.x, S.mouse.y
    if S.menu == "bank" then
        local L = bank.layout()
        if L.buy and inside(mx, my, L.buy.x, L.buy.y, L.buy.w, L.buy.h) then S.hover.buy = true end
        if inside(mx, my, L.on.x, L.on.y, L.on.w, L.on.h) then S.hover.on = true end
        return
    end
    if S.menu == "loadout" then
        local P = info()
        if P then
            if inside(mx, my, P.button.x, P.button.y, P.button.w, P.button.h) then S.hover.bring = true return end
            if inside(mx, my, P.x, P.y, P.w, P.h) then S.hover.info = true return end
        end
        local L = loadoutLayout()
        for _, c in ipairs(L.chips) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.enemy = c.kind return end
        end
        for _, c in ipairs(L.seeds) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.seed = c.seed.id return end
        end
        for _, c in ipairs(L.cards) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.species = c.t.id return end
        end
        if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then S.hover.back = true end
        if inside(mx, my, L.go.x, L.go.y, L.go.w, L.go.h) then S.hover.go = true end
        return
    end
    if S.menu == "codex" then codex.findHover(mx, my) return end
    if S.menu == "title" then return end
    if S.menu then
        local cards, switch = levelCards()
        for k, c in ipairs(cards) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.level = k return end
        end
        local cb = codex.button()
        if inside(mx, my, cb.x, cb.y, cb.w, cb.h) then S.hover.codex = true return end
        if Profile.challengeOpen() and inside(mx, my, switch.x, switch.y, switch.w, switch.h) then S.hover.challenge = true end
        local sw = audio.switch()
        if inside(mx, my, sw.x, sw.y, sw.w, sw.h) then S.hover.sound = true end
        return
    end
    if S.game.phase == "won" then
        for _, b in ipairs(wonButtons()) do
            if inside(mx, my, b.x, b.y, b.w, b.h) then S.hover.won = b.id return end
        end
    end
    if S.game.phase == "mutate" then
        for k, c in ipairs(mutationCards()) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.mutation = k return end
        end
    end
    local P = info()
    if P and inside(mx, my, P.x, P.y, P.w, P.h) then
        S.hover.info = true
        for _, l in ipairs(P.lines) do
            if l.up and inside(mx, my, P.x + 3, l.y, P.w - 6, l.h - 3) then S.hover.up = l.up end
        end
        return
    end
    for n = 1, #BUTTONS do
        if inside(mx, my, buttonRect(n)) then S.hover.button = n return end
    end
    if inside(mx, my, waveRect()) then S.hover.wave = true return end
    if inside(mx, my, turnRect(1)) then S.hover.turn = 1 return end
    if inside(mx, my, turnRect(-1)) then S.hover.turn = -1 return end
    local wb = S.weatherBox
    if wb and inside(mx, my, wb.x, wb.y, wb.w, wb.h) then S.hover.weather = wb.kind return end
    if my < S.inset.t + TOP then S.hover.strip = true return end
    local ci, cj = cursor()
    local best, bd = nil, 9
    for _, n in ipairs(S.game.nodes) do
        local i, j = nodeScreen(n)
        local d = sqrt((i - ci) ^ 2 + (j - cj) ^ 2)
        if d < bd then best, bd = n, d end
    end
    S.hover.node = best
    local x, _, z = S.world:pick(ci, cj)
    if x then
        S.hover.x, S.hover.z = x, z
        S.hover.c, S.hover.r = floor(x / World.TILE), floor(z / World.TILE)
        S.hover.mat = S.game:matAt(S.hover.c, S.hover.r)
    end
    if not best then
        local bl, bdist = nil, 3.5
        for _, l in ipairs(S.game.links) do
            local ai, aj = S.world:toImage(l.a.x, l.a.y, l.a.z)
            local bi, bj = S.world:toImage(l.b.x, l.b.y, l.b.z)
            local d = Game.segDist(ci, cj, ai, aj, bi, bj)
            if d < bdist then bl, bdist = l, d end
        end
        S.hover.link = bl
    end
end

--- the run ---------------------------------------------------------------------------

local function start()
    S.game = Game.new(S.world, S.level, { challenge = S.challenge, loadout = S.chosen, seed = not S.script and Profile.sown[S.level.id] or nil,
        best = Profile.records[S.level.id], dice = S.script and 1 })
    layTools(S.game)
    S.mode, S.drag, S.panx, S.pany, S.selected = "grow", nil, 0, 0, nil
    S.focus, S.focused = nil, nil
    S.paused, S.speed = false, 1
    S.menu = nil
    flair.sky.change(S.game.weather or false)
    flair.sky.t = flair.sky.time
end

-- Plays level `n` with the species in `chosen`: its board if it is painted
-- already, else paint it first.
local function play(n)
    S.level = D.LEVELS[n]
    S.menu = nil
    if S.worlds[S.level.id] then
        S.world = S.worlds[S.level.id]
        start()
        return
    end
    S.world = World.new(S.level.map)
    S.worlds[S.level.id] = S.world
    S.progress = 0
    S.painter = coroutine.create(function() S.world:paint() end)
end

local function openMenu()
    S.menu = true
    S.mode, S.drag, S.selected = "grow", nil, nil
end

-- Before level `n`: pick what to bring, starting from what was brought last
-- time (or the level's own suggestion the first time).
local openLoadout

-- Won: one of the buttons, or its key.
local function afterWin(id)
    -- A first win put a species up for sale: the Spore Bank shows it first.
    if S.game.offer then
        bank.offer = { kind = S.game.offer, after = id }
        S.game.offer = nil
        S.menu = "bank"
        S.mode, S.drag, S.selected = "grow", nil, nil
        sound("offer")
        return
    end
    if id == "endless" then sound("go"); S.game:goEndless()
    elseif id == "again" then sound("go"); start()
    elseif id == "levels" then sound("back"); openMenu()
    elseif id == "next" then
        for k, l in ipairs(D.LEVELS) do
            if l == S.level and D.LEVELS[k + 1] then sound("select"); openLoadout(k + 1) return end
        end
    end
end

-- Out of the Spore Bank, on to what the won level's button was for.
function bank.leave()
    local id = bank.offer.after
    bank.offer, S.menu = nil, nil
    afterWin(id)
end

function bank.buyOffer()
    if bank.offer.bought then return end
    if Profile.buy(bank.offer.kind) then bank.offer.bought = true; sound("unlock") else deny() end
end

function openLoadout(n)
    local lv = D.LEVELS[n]
    S.menu = "loadout"
    S.mode, S.drag, S.selected = "grow", nil, nil
    -- The seed planted here last time, if it is still had; else the bean.
    local seed = Profile.sown[lv.id]
    S.pick = { n = n, set = {}, full = 0, seed = seed and Profile.ownsSeed(seed) and seed or D.SEEDS[1].id }
    local dropped = false
    for _, id in ipairs(Profile.loadouts[lv.id] or lv.loadout or {}) do
        if Profile.owns(id) then S.pick.set[id] = true else dropped = true end
    end
    -- A species not had yet stays home, and the next one had takes its place.
    for _, t in ipairs(D.TOWERS) do
        if not dropped or #picked() >= D.LOADOUT then break end
        if Profile.owns(t.id) then S.pick.set[t.id] = true end
    end
end

-- Off into the level with what was picked, remembered for next time.
local function setOff()
    local list = picked()
    if #list == 0 then sound("deny") return end
    sound("go")
    Profile.loadouts[D.LEVELS[S.pick.n].id] = list
    Profile.sown[D.LEVELS[S.pick.n].id] = S.pick.seed
    Profile.save()
    S.chosen = list
    play(S.pick.n)
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    setWindowIcon()
    fit()
    Profile.load()
    codex.init()
    for _, a in ipairs(args or {}) do
        if a == "--shots" then S.script = require("src.script") end
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
    if Profile.sound then Sfx.level = Profile.sound end
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
    if S.script then
        -- The script plays the level it is told to (--shots pond), or the first.
        local n = 1
        for _, a in ipairs(args or {}) do
            for k, l in ipairs(D.LEVELS) do if a == l.id then n = k end end
        end
        S.script.level = D.LEVELS[n].id
        for _, a in ipairs(args or {}) do if a == "challenge" then S.challenge = true end end
        play(n)
    else
        flair.title.open()
    end
end

-- A tap on nothing (no pocket, no plant, no thread, off the board) puts
-- everything down: the tool in hand, a thread being pulled, the selection.
local function letGo()
    S.mode, S.drag, S.selected, S.peek = "grow", nil, nil, nil
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

-- Whatever is under the pointer that lights up when pressed: how to find its
-- box again (the layout can move under it while it is lit).
function flair.under()
    if S.menu == "bank" then
        local L = bank.layout()
        local b = S.hover.buy and L.buy or (S.hover.on and L.on)
        if b then return function() return b.x, b.y, b.w, b.h end end
        return
    end
    if S.menu == "loadout" then
        local L = loadoutLayout()
        if S.hover.back then return function() return L.back.x, L.back.y, L.back.w, L.back.h end end
        if S.hover.go then return function() return L.go.x, L.go.y, L.go.w, L.go.h end end
        if S.hover.species then
            for _, c in ipairs(L.cards) do
                if c.t.id == S.hover.species then return function() return c.x, c.y, c.w, c.h end end
            end
        end
        if S.hover.seed then
            for _, c in ipairs(L.seeds) do
                if c.seed.id == S.hover.seed then return function() return c.x, c.y, c.w, c.h end end
            end
        end
        return
    end
    if S.menu == "codex" then return codex.under() end
    if S.menu == "title" then return end
    if S.menu then
        if S.hover.level then
            local c = levelCards()[S.hover.level]
            return function() return c.x, c.y, c.w, c.h end
        end
        if S.hover.codex then return function() local c = codex.button() return c.x, c.y, c.w, c.h end end
        if S.hover.challenge then
            local _, c = levelCards()
            return function() return c.x, c.y, c.w, c.h end
        end
        if S.hover.sound then
            local c = audio.switch()
            return function() return c.x, c.y, c.w, c.h end
        end
        return
    end
    if S.hover.mutation then
        local c = mutationCards()[S.hover.mutation]
        return function() return c.x, c.y, c.w, c.h end
    end
    if S.hover.won then
        local id = S.hover.won
        return function()
            for _, b in ipairs(wonButtons()) do if b.id == id then return b.x, b.y, b.w, b.h end end
            return 0, 0, 0, 0
        end
    end
    if S.hover.button then
        local n = S.hover.button
        return function() return buttonRect(n) end
    end
    if S.hover.wave then return waveRect end
    if S.hover.turn then
        local d = S.hover.turn
        return function() return turnRect(d) end
    end
end

local function click(b)
    local r = b == 1 and flair.under()
    if r then flair.pressed = { t = 0.18, rect = r } end
    if S.menu == "bank" then
        if S.hover.buy then bank.buyOffer()
        elseif S.hover.on or b == 2 then sound("click"); bank.leave() end
        return
    end
    if S.menu == "loadout" then
        -- A card opens its panel; the same card again (or the panel's button)
        -- brings it or leaves it, or buys it. Anywhere else shuts the panel.
        if S.hover.bring then
            if S.pick.seedInfo then bank.plantOrBuy(S.pick.seedInfo) else bank.bringOrBuy(S.pick.info) end
            return
        end
        if S.hover.info then return end
        if b == 2 then
            sound("back")
            if S.pick.info or S.pick.seedInfo then S.pick.info, S.pick.seedInfo = nil, nil else openMenu() end
            return
        elseif S.hover.species then
            S.pick.seedInfo = nil
            if S.pick.info == S.hover.species then toggleSpecies(S.hover.species) else S.pick.info = S.hover.species; sound("panel") end
            return
        elseif S.hover.seed then
            -- One had is planted at once, and its panel opens; one not had
            -- only opens its panel, whose button buys it.
            S.pick.info = nil
            local id = S.hover.seed
            if Profile.ownsSeed(id) and S.pick.seed ~= id then S.pick.seed = id; sound("on")
            elseif S.pick.seedInfo ~= id then sound("panel")
            elseif not Profile.ownsSeed(id) then deny() end
            S.pick.seedInfo = id
            return
        elseif S.hover.back then sound("back"); openMenu()
        elseif S.hover.go then setOff()
        elseif S.hover.enemy then
            -- Pinned, so a finger (which has no hover) can see the answers too.
            S.pick.enemy = S.pick.enemy ~= S.hover.enemy and S.hover.enemy or nil
            sound(S.pick.enemy and "select" or "back")
        elseif S.pick and (S.pick.info or S.pick.seedInfo) then
            sound("back")
        end
        if S.pick then S.pick.info, S.pick.seedInfo = nil, nil end
        return
    end
    if S.menu == "codex" then codex.click(b) return end
    if S.menu == "title" then flair.title.leave() return end
    if S.menu then
        if S.hover.codex then codex.open() return end
        if S.hover.level and Profile.levelOpen(S.hover.level) then sound("select"); openLoadout(S.hover.level)
        elseif S.hover.level then deny()
        elseif S.hover.challenge then S.challenge = not S.challenge; sound(S.challenge and "on" or "off")
        elseif S.hover.sound then Sfx.cycle(); audio.save(); sound("on") end
        return
    end
    if S.weatherTip and not S.hover.weather then S.weatherTip = nil end
    if b == 2 then
        if S.mode ~= "grow" or S.drag or S.selected then sound("back") end
        S.mode, S.drag, S.selected = "grow", nil, nil
        return
    end
    if S.game.phase == "mutate" then
        -- The picker holds the game until a mutation is chosen.
        if S.hover.mutation then S.game:mutate(S.hover.mutation) end
        return
    end
    if S.hover.up then
        if not S.game:upgrade(S.selected, S.hover.up.branch) then deny() end
        return
    end
    if S.hover.info then return end
    if S.hover.button then
        -- The tool already in hand, picked again, is put down: the one way to
        -- cancel there is without a right button. A species not yet unlocked
        -- stays in its slot, dark.
        local bt = BUTTONS[S.hover.button]
        if bt.action then
            if S.game:repairAll() == 0 then deny() end
            return
        end
        if bt.tower and not S.game:unlocked(bt.mode) then deny() return end
        local m = bt.mode
        S.drag = nil
        if bt.tower and m == S.mode then
            -- The species in hand, picked again: its panel opens, or shuts. It
            -- stays in hand; a tap on the ground puts it down.
            S.peek, S.selected = S.peek ~= m and m or nil, nil
            sound(S.peek and "panel" or "back")
            return
        end
        S.mode, S.peek = (m == S.mode and m ~= "grow") and "grow" or m, nil
        if S.mode ~= "grow" then S.selected = nil end
        sound(S.mode == "grow" and "back" or "select")
        return
    end
    if S.hover.wave then
        if S.game.phase == "build" then S.game:startWave() else S.speed = S.speed % 3 + 1; sound("speed", 0.8 + 0.2 * S.speed) end
        return
    end
    if S.hover.turn then turnCamera(S.hover.turn) return end
    if S.game.phase == "won" then
        if S.hover.won then afterWin(S.hover.won) end
        return
    end
    if S.game.phase == "lost" then sound("click"); openMenu() return end
    if S.hover.weather then
        -- Not the pause: on a phone a tap opens what the weather does, and
        -- another shuts it. With a mouse, hovering is enough.
        if S.touch then
            S.weatherTip = S.weatherTip ~= S.hover.weather and S.hover.weather or nil
            sound(S.weatherTip and "panel" or "back")
        end
        return
    end
    if S.hover.strip then
        -- No P key on a phone: the top strip is the pause button.
        if S.touch then S.paused = not S.paused; sound(S.paused and "pause" or "unpause") end
        return
    end
    if S.mode == "grow" then
        if S.hover.node then
            if S.drag and S.drag ~= S.hover.node then
                if not S.game:grow(S.drag, S.hover.node) then deny() end
                S.drag, S.selected = nil, nil
            else
                -- A node is picked up as the end of a thread. Its tower is only
                -- selected (and the camera only goes to it) once it is let go
                -- where it was: pulled on to another node, it was a link.
                S.drag, S.tapped = S.hover.node, S.hover.node
            end
        elseif S.hover.link and S.hover.link.state == "cut" then
            if not S.game:repair(S.hover.link) then deny() end
        elseif S.hover.mat then
            S.drag, S.selected = nil, S.hover.mat
            sound("panel")
        else
            if S.selected then sound("back") end
            S.drag, S.selected = nil, nil
        end
    elseif S.mode == "prune" then
        if S.hover.node and S.hover.node.tower then
            S.game:sell(S.hover.node)
        elseif S.hover.link then
            S.game:prune(S.hover.link)
        elseif S.hover.mat then
            S.game:liftMat(S.hover.mat)
        else
            sound("back")
            letGo()
        end
    elseif D.TOWER[S.mode] and D.TOWER[S.mode].onTrail then
        -- Off the trail (or off the board) there is nowhere to lay it.
        if S.hover.c and S.world:distAt(S.hover.c, S.hover.r) then
            local m = S.game:lay(S.mode, S.hover.c, S.hover.r)
            if m then S.selected, S.peek = m, nil else deny() end
        else
            sound("back")
            letGo()
        end
    elseif S.mode == "pulse" then
        if not S.hover.node then sound("back"); letGo()
        elseif S.game:pulse(S.hover.node) then S.mode = "grow"
        else deny() end
    else
        if S.hover.node then
            local t = S.game:build(S.mode, S.hover.node)
            -- Planted, the species is put down: back to growing, with the new
            -- tower selected.
            if t then S.selected, S.peek, S.mode = t, nil, "grow" else deny() end
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
    S.mouse.wx, S.mouse.wy = x, y
    S.mouse.x, S.mouse.y = floor(x / S.uz), floor(y / S.uz)
end

function love.mousepressed(x, y, b, istouch)
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

function love.mousereleased(x, y, b, istouch)
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

function love.mousemoved(x, y)
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

function love.wheelmoved(_, y)
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

function love.touchpressed(id, x, y)
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

function love.touchmoved(id, x, y)
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

function love.touchreleased(id)
    if S.pinch and not S.pinch.done and (id == S.pinch.a or id == S.pinch.b) then
        local bx, by = S.pinch.x0 / S.zoom + S.camx, S.pinch.y0 / S.zoom + S.camy
        local step = floor(S.zoom * S.pinch.s + 0.5) - (S.zoom - S.zoomStep)
        zoomTo(step, bx, by, S.pinch.x, S.pinch.y)
        S.pinch.done = true
    end
    S.fingers[id] = nil
    if not next(S.fingers) then S.pinch = nil end
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
    if S.painter then return end
    if S.menu == "bank" then
        if key == "b" then bank.buyOffer()
        elseif key == "return" or key == "kpenter" or key == "space" or key == "escape" then sound("click"); bank.leave() end
        return
    end
    if S.menu == "loadout" then
        if key == "escape" or key == "backspace" then
            if S.pick.info or S.pick.seedInfo then S.pick.info, S.pick.seedInfo = nil, nil else openMenu() end
            return
        end
        if key == "return" or key == "kpenter" or key == "space" then setOff() return end
        for _, t in ipairs(D.TOWERS) do
            if key == t.key:lower() then toggleSpecies(t.id) end
        end
        return
    end
    if S.menu == "codex" then codex.key(key) return end
    if S.menu == "title" then flair.title.leave() return end
    if S.menu then
        if key == "e" then codex.open() return end
        local n = tonumber(key)
        if n and D.LEVELS[n] then
            if Profile.levelOpen(n) then sound("select"); openLoadout(n) else deny() end
        end
        if key == "c" and Profile.challengeOpen() then S.challenge = not S.challenge; sound(S.challenge and "on" or "off") end
        if key == "escape" and S.game then sound("back"); S.menu = nil end
        return
    end
    if key == "=" or key == "+" or key == "kp+" then zoomBy(1) end
    if key == "-" or key == "kp-" then zoomBy(-1) end
    if S.game.phase == "mutate" then
        local n = tonumber(key)
        if n then S.game:mutate(n) end
        return
    end
    if key == "escape" then
        -- Never quits: one key too many and a run is gone. The window's close does that.
        if S.drag or S.mode ~= "grow" or S.selected then
            S.mode, S.drag, S.selected = "grow", nil, nil
            sound("back")
        else
            S.paused = not S.paused
            sound(S.paused and "pause" or "unpause")
        end
    end
    for n, b in ipairs(BUTTONS) do
        if key == b.key:lower() then
            flair.pressed = { t = 0.18, rect = function() return buttonRect(n) end }
            if b.action then
                if S.game:repairAll() == 0 then deny() end
            elseif not (b.tower and not S.game:unlocked(b.mode)) then
                S.mode, S.drag, S.selected, S.peek = b.mode, nil, nil, nil
                sound("select")
            else
                deny()
            end
        end
    end
    if (key == "z" or key == "c") and S.selected then
        local ups = S.game:upgrades(S.selected)
        local u = ups[key == "z" and 1 or #ups]
        if not (u and S.game:upgrade(S.selected, u.branch)) then deny() end
    end
    if key == "space" then
        if S.game.phase == "build" then
            flair.pressed = { t = 0.18, rect = waveRect }
            S.game:startWave()
        end
    end
    if key == "f" then S.speed = S.speed % 3 + 1; sound("speed", 0.8 + 0.2 * S.speed) end
    if key == "e" and S.game.phase == "won" then afterWin("endless") return end
    if key == "e" then turnCamera(love.keyboard.isDown("lshift", "rshift") and -1 or 1) end
    if key == "q" then turnCamera(-1) end
    if key == "p" then S.paused = not S.paused; sound(S.paused and "pause" or "unpause") end
    if key == "r" and S.game.phase == "won" then afterWin("again")
    elseif key == "r" and (S.game.phase == "lost" or love.keyboard.isDown("lshift")) then sound("go"); start() end
    if key == "m" then
        if S.game.phase == "won" then afterWin("levels") else sound("back"); openMenu() end
    end
    -- Won: on to the next level.
    if key == "n" and S.game.phase == "won" then afterWin("next") end
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
        local P = info()
        wx = floor(S.vw / 2)
        wy = floor((P.y + P.h + barTop() - 30) / 2)
    end
    return { x = S.panx + toBoard(hx - wx), y = S.pany + toBoard(hy - wy) }
end

-- A tick when the pointer comes onto something that can be pressed (never
-- for a finger, which has no hover).
function audio.hover()
    local k = S.hover.button or S.hover.wave or S.hover.turn or (S.hover.up and S.hover.up.branch + 100) or S.hover.mutation
        or S.hover.level or S.hover.challenge or S.hover.sound or S.hover.species or S.hover.back or S.hover.go or S.hover.enemy
        or S.hover.bring or S.hover.weather or S.hover.won or (S.hover.buy and "buy") or (S.hover.on and "on")
    if k ~= nil then k = tostring(k) .. (S.hover.up and "u" or S.hover.mutation and "m" or S.hover.level and "l" or "") end
    if k and k ~= flair.lastHover and not S.touch then sound("hover") end
    flair.lastHover = k
end

-- What the game cued this frame, played from where on the screen it happened:
-- panned across, and quieter off the edge.
function audio.hear()
    for _, c in ipairs(S.game.cues) do
        local pan, vol = 0, c.vol or 1
        if c.x then
            local i, j = S.world:toImage(c.x, S.world:groundAt(c.x, c.z), c.z)
            local sx, sy = (i - floor(S.camx)) / S.cw, (j - floor(S.camy)) / S.ch
            pan = sx * 2 - 1
            if sx < -0.05 or sx > 1.05 or sy < -0.05 or sy > 1.05 then vol = vol * 0.35 end
        end
        Sfx.play(c.name, pan, vol)
        -- Some say so in words too.
        local n = c.name
        if n == "wave" then
            local w = S.game.weather and D.WEATHER[S.game.weather]
            flair.banner = { text = "WAVE " .. S.game.wave, sub = w and w.name .. ": " .. w.blurb, k = "r", t = 2.2, max = 2.2 }
        elseif n == "clear" then
            flair.banner = { text = "WAVE " .. S.game.cleared .. " CLEARED", k = "g", t = 1.8, max = 1.8 }
        elseif n == "unlock" and S.game.newSpecies then
            flair.banner = { text = "NEW SPECIES: " .. D.TOWER[S.game.newSpecies].name, k = "l", t = 2.4, max = 2.4 }
        elseif n == "ring" then
            flair.banner = { text = "A FAIRY RING CLOSES", sub = "TOWERS IN IT HIT HARDER. ENEMIES IN IT WADE", k = "l", t = 2.2, max = 2.2 }
        end
    end
    S.game.cues = {}
end

-- The loops under it all: the soil always, the network's hum as loud as it is
-- alive (and higher the more it carries), the weather's own.
function audio.ambience(dt)
    local want = { soil = 0.35 }
    local pitch
    if S.menu == "title" then
        -- The night over the title, and the network's hum swelling as it grows.
        local age = flair.now() - (flair.title.t0 or 0)
        want.night, want.hum = 0.3, 0.35 * min(1, age / 4)
        pitch = 0.9 + 0.2 * min(1, age / 6)
    elseif S.game and not S.menu and not S.painter then
        local living, surge = 0, false
        for _, l in ipairs(S.game.links) do
            if l.state == "alive" and l.a.conn then living = living + 1 end
            if l.surge then surge = true end
        end
        want.hum = min(0.5, living * 0.035) * (S.game.phase == "wave" and 1 or 0.6)
        pitch = 0.9 + 0.2 * min(1, living / 24) + (surge and 0.15 or 0)
        local w = S.game.weather
        if w == "rain" then want.rain = 0.5
        elseif w == "drought" then want.wind = 0.5
        elseif w == "night" then want.night = 0.4
        elseif w == "frost" then want.frost = 0.45; want.wind = 0.2 end
        if S.paused then for k, v in pairs(want) do want[k] = v * 0.4 end end
    end
    Sfx.update(dt, want, pitch)
end

-- The title's own sounds: a patter as the network reaches out under the
-- sprout, then a drink each time the nutrients running up it get there.
function audio.title()
    local T0 = flair.title
    local age = flair.now() - (T0.t0 or 0)
    if age < 3 then
        local k = floor(age / 0.22)
        if k ~= T0.grew then T0.grew = k; Sfx.play("grow", 0, 0.35, 0.8 + age * 0.15) end
    else
        -- A nutrient is lit at the sprout when (d + age * 30) % 48 < 2 at d = 0.
        local k = floor(age * 30 / 48)
        if k ~= T0.drank then T0.drank = k; Sfx.play("drink", 0, 0.6) end
    end
end

function love.update(dt)
    -- The script runs on its own clock, the HUD's flourishes too.
    if S.script then dt = 1 / 30 end
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
    if S.painter then
        local t0 = love.timer.getTime()
        -- Paint in slices, so the window keeps answering while the board goes down.
        while coroutine.status(S.painter) ~= "dead" and love.timer.getTime() - t0 < 1 / 30 do
            local ok, p = coroutine.resume(S.painter)
            if not ok then error(p) end
            S.progress = p or 1
        end
        if coroutine.status(S.painter) == "dead" then
            S.painter = nil
            -- The other three sides of the board are painted in the background,
            -- a slice a frame, so the camera can go round at once.
            if not S.script and not S.world.backPainter then
                local w = S.world
                w.backPainter = coroutine.create(function()
                    for q = 0, World.TURNS - 1 do
                        if not w:painted(q) then w:paint(q) end
                    end
                end)
            end
            start()
            if S.script then
                -- The script clicks like a player: it is told where things are
                -- in window pixels.
                S.script.begin(S.game, {
                    at = function(x, y, z)
                        local i, j = S.world:toImage(x, y, z)
                        return (floor(i) - floor(S.camx) + 0.5) * S.zoom, (floor(j) - floor(S.camy) + 0.5) * S.zoom
                    end,
                    select = function(t) S.selected = t end,
                    selection = function() return S.selected end,
                    menu = function(on) if on then openMenu() else S.menu = nil end end,
                    loadout = function(n) if n then openLoadout(n) else S.menu, S.pick = nil, nil end end,
                    button = function(name)
                        for n, b in ipairs(BUTTONS) do
                            if b.mode == name then
                                local x, y, w, h = buttonRect(n)
                                return (x + w / 2) * S.uz, (y + h / 2) * S.uz
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
        if not S.shot or S.shot:getWidth() ~= S.cw or S.shot:getHeight() ~= S.ch then S.shot = love.graphics.newCanvas(S.cw, S.ch) end
        love.graphics.setCanvas(S.shot)
        love.graphics.setColor(1, 1, 1)
        if not S.menu then love.graphics.draw(S.canvas) end
        love.graphics.draw(S.ui)
        love.graphics.setCanvas()
        S.script.after(S.game, S.shot)
    end
    if S.menu then
        if S.pick then S.pick.full = max(0, (S.pick.full or 0) - dt) end
        findHover()
        audio.hover()
        if S.menu == "title" then audio.title() end
        if S.script then
            S.script.update(S.game, 1 / 30)
            photograph()
        end
        return
    end
    local bg = S.world.backPainter
    if bg and coroutine.status(bg) ~= "dead" then
        local t0 = love.timer.getTime()
        while coroutine.status(bg) ~= "dead" and love.timer.getTime() - t0 < 0.004 do
            local ok, err = coroutine.resume(bg)
            if not ok then error(err) end
        end
    end
    dt = min(dt, 1 / 30)
    if S.script then dt = 1 / 30 end
    if S.turning then
        S.turning.t = S.turning.t + dt
        if S.turning.t >= TURN_TIME then
            S.turning.old:release()
            S.turning = nil
        end
    end

    local k = love.keyboard.isDown
    local pan = 120 * dt
    if k("left", "a", "right", "d", "up", "w", "down", "s") then S.focus = nil end
    if k("left", "a") then S.panx = S.panx - pan end
    if k("right", "d") then S.panx = S.panx + pan end
    if k("up", "w") then S.pany = S.pany - pan end
    if k("down", "s") then S.pany = S.pany + pan end
    -- Something newly selected: ease the camera to put it beside its panel.
    if S.selected ~= S.focused then
        S.focused = S.selected
        S.focus = S.selected and info() and focusOn(S.selected) or nil
    end
    if S.focus then
        local e = 1 - math.exp(-dt * 9)
        S.panx, S.pany = S.panx + (S.focus.x - S.panx) * e, S.pany + (S.focus.y - S.pany) * e
        if abs(S.focus.x - S.panx) < 0.5 and abs(S.focus.y - S.pany) < 0.5 then S.panx, S.pany, S.focus = S.focus.x, S.focus.y, nil end
    end
    -- Zoomed in, the board is bigger than the screen: let every edge of it be
    -- reached, with a little ground to spare. With a panel open, further, so a
    -- tower at the board's edge can still come out beside it. Past the edge the
    -- camera eases back rather than stopping dead.
    local limx = max(40, (S.world.w - (S.cw - toBoard(S.inset.l + S.inset.r))) / 2 + 40)
    local limy = max(60, (S.world.h - (S.ch - toBoard(S.inset.t + S.inset.b + TOP + BOTTOM))) / 2 + 40)
    if info() then limx, limy = limx + S.cw / 2, limy + S.ch / 2 end
    local cx, cy = max(-limx, min(limx, S.panx)), max(-limy, min(limy, S.pany))
    if cx ~= S.panx or cy ~= S.pany then
        local e = min(1, dt * 12)
        S.panx, S.pany = S.panx + (cx - S.panx) * e, S.pany + (cy - S.pany) * e
    end
    centre()

    -- The sky changed: the new picture dithers in over the old. Changed again
    -- before it was done, the picture mostly showing is the one it leaves.
    local sky = S.game.weather or false
    if sky ~= flair.sky.to then flair.sky.change(sky) end
    flair.sky.t = min(flair.sky.time, flair.sky.t + dt)

    if S.script then S.script.update(S.game, dt) end
    findHover()
    audio.hover()
    if not S.paused then
        for _ = 1, S.speed do
            S.game:update(dt)
            if S.game.events.heart then S.heartFlash, flair.hurt = 0.15, 0.45 end
            if S.game.events.shake then S.shake = max(S.shake, S.game.events.shake) end
        end
        if not S.script then codex.watch(S.game) end
    end
    audio.hear()
    -- A lot coming in at once (a body drunk, a wave's bonus): the count glows.
    if S.game.nutrients - flair.lastNut >= 3 and (flair.nut.t <= 0 or flair.nut.k ~= "r") then flair.nut = { t = 0.35, k = "w" } end
    flair.lastNut = S.game.nutrients
    -- The sprout low: a heartbeat, heard and seen at the screen's edge.
    local low = S.game.phase == "wave" and S.game.heartHp > 0 and S.game.heartHp < S.game.heartMax * 0.3
    local b = low and not S.paused and (S.game.clock % 1.2) < 0.15
    if b and not flair.beat then Sfx.play("stomp", 0, 0.6, 0.6) end
    flair.beat = b
    S.heartFlash = max(0, S.heartFlash - dt)
    S.shake = max(0, S.shake - dt)
    if S.game.best > (Profile.records[S.level.id] or 0) and not S.script then
        Profile.records[S.level.id] = S.game.best
        Profile.save()
    end
    -- Spores go into the bank as they are earned, so a run left half way keeps them.
    if S.game.spores > (S.game.banked or 0) and not S.script then
        Profile.spores = Profile.spores + S.game.spores - (S.game.banked or 0)
        S.game.banked = S.game.spores
        Profile.save()
    end
    if S.game.phase == "won" and not S.game.recorded then
        S.game.recorded = true
        if not S.script then
            -- The first win puts the level's species up for sale, shown on the way on.
            if not Profile.won[S.level.id] and S.level.prize and not Profile.owns(S.level.prize) then S.game.offer = S.level.prize end
            -- And any seed waiting on it.
            for _, sd in ipairs(D.SEEDS) do
                if not Profile.won[S.level.id] and sd.after == S.level.id and not Profile.ownsSeed(sd.id) then S.game.newSeed = sd.id end
            end
            Profile.won[S.level.id] = true
            Profile.save()
        end
    end
    -- What was selected may have been eaten, sterilised, sold or flattened.
    if S.selected then
        local gone
        if S.selected.node then gone = S.selected.node.tower ~= S.selected
        else
            gone = true
            for _, m in ipairs(S.game.mats) do if m == S.selected then gone = false end end
        end
        if gone then S.selected = nil end
    end
    if S.script then photograph() end
end

--- drawing the world -------------------------------------------------------------------

-- It never sags below the lower of its two ends' ground, so a thread between
-- two pockets on the field bridges a sunken trail or the pond rather than
-- dropping into it; one to a lily pad still comes down to the water.
local function linkY(l, f, x, z)
    local g = max(S.world:groundAt(x, z), min(0, l.a.y, l.b.y)) + 0.4
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
    local t = S.game.clock
    local core, under = IDX.c, IDX.d
    if l.state == "alive" and not fed then core, under = IDX.d, IDX.u end
    if highlight then core = highlight end
    local surge = l.surge and l.state == "alive"
    if surge then core, under = IDX.l, IDX.c end
    local hurt = l.state == "alive" and l.hp < S.game:linkHp() * 0.5
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
            local i, j, d = S.world:toImage(x, linkY(l, f, x, z), z)
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
    for j = max(0, j0), min(S.world.h - 1, j1) do
        for i = max(0, i0), min(S.world.w - 1, i1) do
            local n = j * S.world.w + i
            if S.world.up[n] == 1 and S.world.wy[n] < 1 and Game.inPoly(poly, S.world.wx[n], S.world.wz[n]) then
                local k = S.world.key[n]
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
            local i, j, d = S.world:toImage(cx, S.world:groundAt(cx, cz) + 1, cz)
            i, j = floor(i), floor(j) - 2
            if visible(i, j, d + 2) then put(IDX.t, i, j + 1); put(IDX.w, i, j) end
        end
    end
end

local function knot(n, k)
    local i, j = S.world:toImage(n.x, n.y + 0.5, n.z)
    i, j = floor(i), floor(j)
    put(IDX.d, i - 1, j + 1); put(IDX.d, i + 1, j + 1); put(IDX.d, i, j + 2)
    put(k, i - 1, j); put(k, i + 1, j); put(k, i, j - 1); put(k, i, j + 1); put(IDX.l, i, j)
end

local function bar(x, y, z, frac, k)
    local i, j = S.world:toImage(x, y, z)
    i, j = floor(i) - 4, floor(j)
    for n = -1, 8 do put(IDX.o, i + n, j - 1); put(IDX.o, i + n, j + 1) end
    put(IDX.o, i - 1, j); put(IDX.o, i + 8, j)
    for n = 0, 7 do put(n < floor(frac * 8 + 0.5) and k or IDX.u, i + n, j) end
end

-- A fruiting body's picture this frame: its look, breathing on its own beat,
-- kicking when it fires, coming up out of the ground when new.
local function towerLook(t, seed)
    local idle = (S.game.clock * 0.7 + seed * 0.37) % 1
    return M.tower(t.kind, t.branch, t.tier, idle, t.squash, t.grown)
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
    elseif k == "centi" then
        return M.centipede(turned(e.h), floor(e.anim * 10) % 2, 0.9)
    elseif k == "centiseg" then
        return M.centseg(turned(e.h), floor(e.anim * 10 + (e.x + e.z) * 0.1) % 2, 0.85)
    elseif k == "cricket" then
        local dig = e.state == "sink" or e.state == "up"
        return M.mole(turned(e.h), floor(e.anim * (dig and 7 or 6)) % 2, dig, 1.35)
    elseif k == "bombardier" then
        return M.bombardier(turned(e.h), floor(e.anim * 6) % 2, e.state == "siege")
    elseif k == "springtail" then
        return M.springtail(turned(e.h), floor(e.anim * 9) % 2, e.hopT ~= nil)
    elseif k == "click" then
        if e.state == "belly" then return M.click(turned(e.h), floor(e.anim * 8) % 2, "belly") end
        if e.state == "leap" then return M.click(turned(e.h), 0, "leap", floor((e.spin or 0) * 4) % 4) end
        return M.click(turned(e.h), floor(e.anim * 5) % 2)
    elseif k == "mole" then
        local dig = e.state == "dig" or e.state == "surface"
        return M.mole(turned(e.h), floor(e.anim * (dig and 7 or 5)) % 2, dig)
    end
    return M.brine(floor(e.anim * 4) % 2)
end

local SHADOW = { ant = 4, pillbug = 4.5, brine = 3.5, gnat = 2.5, slug = 6, spider = 5, knight = 5,
    queen = 11, stag = 13, dung = 10, moth = 3.5, waterbug = 12, centipede = 6, centseg = 5.5, bombardier = 10,
    springtail = 3, click = 10, mole = 10, cricket = 5.5, centi = 3.5, centiseg = 3 }

-- Something under the water: rings spreading on the surface where it is.
local function ripples(x, z, t)
    for ring = 0, 1 do
        local r = 5 + ((t * 6 + ring * 5) % 10)
        local n = floor(r * 2.4)
        for s = 0, n - 1 do
            if (s + ring) % 2 == 0 then
                local a = s / n * 2 * math.pi
                local px, pz = x + math.cos(a) * r, z + math.sin(a) * r * 0.9
                local i, j, d = S.world:toImage(px, S.world:groundAt(px, pz) + 0.2, pz)
                if visible(floor(i), floor(j), d + 1) then put(r < 9 and IDX.w or IDX.s, i, j) end
            end
        end
    end
end

-- Something burrowing: the soil heaving up over it, a ridge of loose crumbs.
-- `k` scales it for something smaller.
function flair.heave(x, z, t, k)
    k = k or 1
    for s = 0, floor(13 * k) do
        local a = s * 2.39996 + t * 3
        local r = ((s % 4) * 1.6 + math.sin(t * 9 + s) * 0.8) * k
        local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
        local i, j, d = S.world:toImage(px, S.world:groundAt(px, pz) + 0.5 + (s % 3) * 0.6, pz)
        if visible(floor(i), floor(j), d + 1) then put(s % 3 == 0 and IDX.u or (s % 3 == 1 and IDX.n or IDX.t), i, j) end
    end
end

-- A tunnel's mouth: a dark hole in a rim of thrown-up soil. While the tunnel
-- is open, a line of loose soil over where it runs between its two ends.
function flair.hole(x, z, r)
    local g = S.world:groundAt(x, z)
    local R = r + 2.5
    local i0, i1, j0, j1 = screenBox(x - R, x + R, g - 1, g + 4, z - R, z + R)
    for j = max(0, j0), min(S.world.h - 1, j1) do
        for i = max(0, i0), min(S.world.w - 1, i1) do
            local n = j * S.world.w + i
            local d2 = (S.world.wx[n] - x) ^ 2 + (S.world.wz[n] - z) ^ 2
            if S.world.up[n] == 1 and d2 <= R * R then
                if d2 <= (r * 0.6) ^ 2 then put(IDX.o, i, j)
                elseif d2 <= r * r then put(IDX.u, i, j)
                elseif (i + j) % 2 == 0 then put(IDX.t, i, j) end
            end
        end
    end
end
function flair.tunnelLine(a, b)
    local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
    for s = 4, len - 4, 3 do
        local f = s / len
        local x, z = a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
        local i, j, d = S.world:toImage(x, S.world:groundAt(x, z) + 0.2, z)
        if visible(floor(i), floor(j), d + 1) then put(floor(s / 3) % 2 == 0 and IDX.n or IDX.u, i, j) end
    end
end

-- A pool of a lamp's light at night: the ground in it is its daytime self again.
local function lightPool(x, z, r)
    local g = S.world:groundAt(x, z)
    local i0, i1, j0, j1 = screenBox(x - r, x + r, g - 1, g + 6, z - r, z + r)
    for j = max(0, j0), min(S.world.h - 1, j1) do
        for i = max(0, i0), min(S.world.w - 1, i1) do
            local n = j * S.world.w + i
            local d2 = (S.world.wx[n] - x) ^ 2 + (S.world.wz[n] - z) ^ 2
            if S.world.up[n] == 1 and d2 <= r * r and (d2 < (r * 0.6) ^ 2 or (i + j) % 2 == 0) then putGround(i, j) end
        end
    end
end

-- The weather, drawn over everything on the board in screen pixels: rain in
-- streaks, frost as drifting flakes, drought as dust in the heat. `amount`, 0
-- to 1, is how much of it there is while it comes in or goes.
local function drawWeather(kind, amount)
    local t = S.game.clock
    amount = amount or 1
    if kind == "rain" then
        for k = 1, floor(S.cw * S.ch / 260 * amount) do
            local x = floor((k * 7919 + floor(t * 50) * 31) % S.cw)
            local y = floor((k * 104729 + t * 260) % (S.ch + 8)) - 4
            for s = 0, 2 do putS(IDX.s, x, y + s) end
        end
    elseif kind == "frost" then
        for k = 1, floor(S.cw * S.ch / 900 * amount) do
            local y = floor((k * 104729 + t * 14) % S.ch)
            local x = floor((k * 7919 + math.sin(t * 0.8 + k) * 6) % S.cw)
            putS(IDX.w, x, y)
            if k % 4 == 0 then putS(IDX.w, x + 1, y); putS(IDX.w, x, y + 1) end
        end
    elseif kind == "drought" then
        for k = 1, floor(S.cw * S.ch / 1800 * amount) do
            local x = floor((k * 7919 + t * 9) % S.cw)
            local y = floor((k * 104729 + math.sin(t + k) * 3) % S.ch)
            putS(IDX.t, x, y)
        end
    end
end

-- Ink on the ground: the board under it goes dark, in a checker so the soil shows.
local function stain(x, z, r, life)
    local g = S.world:groundAt(x, z)
    local i0, i1, j0, j1 = screenBox(x - r, x + r, g - 1, g + 4, z - r, z + r)
    for j = max(0, j0), min(S.world.h - 1, j1) do
        for i = max(0, i0), min(S.world.w - 1, i1) do
            local n = j * S.world.w + i
            local d2 = (S.world.wx[n] - x) ^ 2 + (S.world.wz[n] - z) ^ 2
            if S.world.up[n] == 1 and d2 <= r * r then
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
    local g = S.world:groundAt(n.x, n.z)
    local i0, i1, j0, j1 = screenBox(n.x - r, n.x + r, g - 1, g + 4, n.z - r, n.z + r)
    for j = max(0, j0), min(S.world.h - 1, j1) do
        for i = max(0, i0), min(S.world.w - 1, i1) do
            local p = j * S.world.w + i
            local d2 = (S.world.wx[p] - n.x) ^ 2 + (S.world.wz[p] - n.z) ^ 2
            if S.world.up[p] == 1 and d2 <= r * r then
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
    local i, j = S.world:toImage(n.x, n.y + 0.5, n.z)
    i, j = floor(i), floor(j)
    put(IDX.k, i - 1, j + 1); put(IDX.k, i + 1, j + 1); put(IDX.k, i, j + 2)
    put(IDX.s, i - 1, j); put(IDX.s, i + 1, j); put(IDX.w, i, j - 1); put(IDX.w, i, j + 1)
    put(floor(S.game.clock * 4) % 2 == 0 and IDX.w or IDX.s, i, j)
end

-- A web thrown over a tower.
local function web(x, y, z)
    local i, j = S.world:toImage(x, y, z)
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
        local a = S.game.clock * 5 + s * 2 * math.pi / n
        local i, j = S.world:toImage(x + math.cos(a) * r, y + math.sin(S.game.clock * 7 + s) * 2, z + math.sin(a) * r)
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
    local i, j, d = S.world:toImage(x, y, z)
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
            local i, j, d = S.world:toImage(x, S.world:groundAt(x, z) + 0.4, z)
            if visible(floor(i), floor(j), d + 1) then put(k, i, j) end
            if r > 3 and s % 2 == 0 then
                x, z = p.x + c * (r - 1.5), p.z + sn * (r - 1.5)
                i, j, d = S.world:toImage(x, S.world:groundAt(x, z) + 0.4, z)
                if visible(floor(i), floor(j), d + 1) then put(k2, i, j) end
            end
        end
    end
end

-- What a kill or a blast leaves on the ground, wearing away from the edge in.
function flair.splat(p)
    local r = p.r
    local fade = min(1, p.life / p.max * 1.5)
    local g = S.world:groundAt(p.x, p.z)
    local i0, i1, j0, j1 = screenBox(p.x - r, p.x + r, g - 1, g + 4, p.z - r, p.z + r)
    local k = IDX[p.k]
    local dk = T.DARKER[k]
    for j = max(0, j0), min(S.world.h - 1, j1) do
        for i = max(0, i0), min(S.world.w - 1, i1) do
            local n = j * S.world.w + i
            if S.world.up[n] == 1 then
                local q = ((S.world.wx[n] - p.x) ^ 2 + (S.world.wz[n] - p.z) ^ 2) / (r * r)
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
    local cx0, cy0, cw0, ch0 = S.camx, S.camy, S.cw, S.ch
    S.camx, S.camy = floor(S.camx) - S.pad.l, floor(S.camy) - S.pad.t
    S.cw, S.ch = S.cw + S.pad.l + S.pad.r, S.ch + S.pad.t + S.pad.b
    if S.shake > 0 then
        S.camx = S.camx + flair.dice:random(-2, 2)
        S.camy = S.camy + flair.dice:random(-1, 1)
    end
    love.graphics.clear(unpack(T.RGB[IDX.o]))
    love.graphics.setColor(1, 1, 1)
    -- The sky's picture of the board, or two dithering between them while the
    -- weather turns.
    local function skyImage(kind) return kind and S.world:variant(kind) or S.world.image end
    local fade = flair.sky.t / flair.sky.time
    local sky = S.game.weather
    local bx, by = -floor(S.camx), -floor(S.camy)
    if fade < 1 and flair.sky.from ~= flair.sky.to then
        -- Coming in, the ground waits a moment for the rain or snow to start.
        local lag = flair.sky.out and 0 or flair.sky.STYLE[flair.sky.w].lag
        local ground = max(0, (fade - lag) / (1 - lag))
        love.graphics.draw(skyImage(flair.sky.from), bx, by)
        if not flair.sky.draw(skyImage(flair.sky.to), bx, by, ground) then fade = 1; love.graphics.draw(skyImage(sky), bx, by) end
    else
        fade = 1
        love.graphics.draw(skyImage(sky), bx, by)
    end
    ffi.fill(S.opx, S.cw * S.ch * 4, 0)
    -- Bugs go dark once the night is mostly in, and are themselves again once
    -- it is mostly gone. A lamp's pool is the daytime ground, which is right
    -- both ways, so it shows all the while night comes or goes.
    local shown = fade >= 0.5 and flair.sky.to or (fade < 1 and flair.sky.from) or sky
    local night = shown == "night"
    local nightPools = night or (fade < 1 and (flair.sky.from == "night" or flair.sky.to == "night"))
    -- At night a lamp lights the ground round it.
    local lamps = {}
    for _, n in ipairs(S.game.nodes) do
        local t = n.tower
        if t and t.kind == "lamp" and (t.glow or 0) > 0 then
            lamps[#lamps + 1] = n
            if nightPools then lightPool(n.x, n.z, min(34, t.glow * 0.45)) end
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
    for _, p in ipairs(S.game.inks) do
        local r = p.r * min(1, (p.max - p.life) * 6) * min(1, p.life * 2)
        stain(p.x, p.z, r)
    end
    for _, p in ipairs(S.game.fx) do if p.splat then flair.splat(p) end end
    for _, p in ipairs(S.game.fx) do if p.shock then flair.shock(p) end end
    for _, t in ipairs(S.game.tunnels) do
        if t.open then flair.tunnelLine(t.a, t.b); flair.hole(t.b.x, t.b.z, 6) end
        flair.hole(t.a.x, t.a.z, 6)
    end
    for _, e in ipairs(S.game.enemies) do
        if e.under and (e.kind == "mole" or e.kind == "cricket") then flair.heave(e.x, e.z, S.game.clock, e.kind == "cricket" and 0.5)
        elseif e.under then ripples(e.x, e.z, S.game.clock)
        elseif SHADOW[e.kind] and not e.hidden then shadow(e.x, e.z, SHADOW[e.kind]) end
        if e.ballHp and e.ballHp > 0 then
            local bx, bz = S.game:ballAt(e)
            shadow(bx, bz, 8)
        end
    end
    for _, m in ipairs(S.game.mats) do
        if m.kind == "mat" then
            local fading = not m.fed and m.life < 8 and floor(S.game.clock * 4) % 2 == 0
            local look = towerLook(m, m.c + m.r)
            if S.selected == m then outline(look, m.x, m.y, m.z, IDX.w) end
            stamp(look, m.x, m.y, m.z, fading and T.DARKER or nil)
        end
    end
    local trailMode = D.TOWER[S.mode] and D.TOWER[S.mode].onTrail
    if trailMode and S.hover.c and not S.hover.button and S.mode == "mat" and S.world:distAt(S.hover.c, S.hover.r) then
        local ok = S.game:canLay(S.mode, S.hover.c, S.hover.r)
        stamp(M.tower(S.mode), S.hover.c * 16 + 8, S.world:groundAt(S.hover.c * 16 + 8, S.hover.r * 16 + 8), S.hover.r * 16 + 8, ok and T.DARKER or T.DARKER2)
    end
    for _, n in ipairs(S.game.nodes) do
        if (n.salted or 0) > 0 then saltCrust(n) end
    end
    for _, l in ipairs(S.game.links) do
        local hl
        if S.hover.link == l then
            if S.mode == "prune" then hl = IDX.r
            elseif l.state == "cut" and not l.hand and not l.salted then hl = IDX.l end
        end
        drawLink(l, hl)
    end
    for _, n in ipairs(S.game.nodes) do
        if (n.salted or 0) > 0 then
            saltKnot(n)
            bar(n.x, n.y + 9, n.z, min(1, n.salted / 12), IDX.w)
        elseif not n.heart and not n.tower and #n.links > 0 then
            knot(n, n.conn and IDX.c or IDX.d)
        end
    end

    -- Fairy rings: the ground inside goes to moss, and a ring of tiny white
    -- caps comes up along the loop.
    for _, r in ipairs(S.game.rings) do drawRing(r) end

    -- A species in hand: every pocket it could grow on, lined in one pixel
    -- as a selected tower is.
    if D.TOWER[S.mode] and not D.TOWER[S.mode].onTrail then
        local rims = S.world:rims()
        for k in ipairs(S.world.pockets) do
            local r = rims[k]
            if r and S.game:canBuild(S.mode, S.game.nodes[k + 1]) then
                for q = 1, #r, 3 do
                    if visible(r[q], r[q + 1], r[q + 2]) then put(IDX.w, r[q], r[q + 1]) end
                end
            end
        end
    end

    -- While a thread is being pulled, every pocket it could reach shows it.
    if S.mode == "grow" and S.drag then
        for _, n in ipairs(S.game.nodes) do
            if n ~= S.drag and S.game:canLink(S.drag, n) then
                local i, j = S.world:toImage(n.x, n.y + 1, n.z)
                local k = floor(S.game.clock * 4) % 2 == 0 and IDX.l or IDX.c
                put(k, i, j - 1); put(k, i - 1, j); put(k, i + 1, j); put(k, i, j + 1)
            end
        end
    end

    -- Reach: whatever is hovered or selected, or what is about to be grown.
    local towerMode = D.TOWER[S.mode] and not trailMode
    local shown = S.hover.node and S.hover.node.tower or S.selected
    -- The rules that work through the network show the nodes they work on.
    local touched = shown and shown.node and S.game:touches(shown)
    if touched then
        for o in pairs(touched) do ring(o.x, o.z, 7, IDX.l, true) end
    end
    if shown and shown.kind == "stink" and shown.node then
        local lane = S.game:stat(shown, "lane")
        for _, l in ipairs(shown.node.links) do
            if S.game.alive(l) then
                local dx, dz = l.b.x - l.a.x, l.b.z - l.a.z
                local len = max(1, math.sqrt(dx * dx + dz * dz))
                local nx, nz = -dz / len * lane, dx / len * lane
                for s = 0, floor(len / 3) do
                    local f = s * 3 / len
                    for side = -1, 1, 2 do
                        local px, pz = l.a.x + dx * f + nx * side, l.a.z + dz * f + nz * side
                        local i, j, d = S.world:toImage(px, S.world:groundAt(px, pz) + 0.3, pz)
                        if visible(floor(i), floor(j), d + 1) then put(IDX.d, i, j) end
                    end
                end
            end
        end
    end
    if shown and S.game:stat(shown, "range") and shown.kind ~= "shelf" then
        local x, z = shown.node and shown.node.x or shown.x, shown.node and shown.node.z or shown.z
        local r = shown.node and S.game:towerRange(shown) or S.game:stat(shown, "range")
        if r > 0 then ring(x, z, r, IDX.l, true) end
        local bait = S.game:stat(shown, "bait")
        if bait then ring(x, z, bait, IDX.d, true) end
        local mr = S.game:stat(shown, "minRange")
        if mr then ring(x, z, mr, IDX.r, true) end
    elseif shown and shown.kind == "shelf" then
        ring(shown.x, shown.z, D.TOWER.shelf.shield, IDX.t, true)
    elseif towerMode and S.hover.node and not S.hover.node.heart then
        local q = World.QUALITY[S.hover.node.quality].power
        if D.TOWER[S.mode].range then ring(S.hover.node.x, S.hover.node.z, D.TOWER[S.mode].range * q, IDX.l, true) end
    end
    if S.selected then
        local x, z = S.selected.node and S.selected.node.x or S.selected.x, S.selected.node and S.selected.node.z or S.selected.z
        ring(x, z, 9 + floor(S.game.clock * 4) % 2, IDX.w)
    end
    if S.mode == "grow" and (S.drag or S.hover.node) then
        local from = S.drag or S.hover.node
        ring(from.x, from.z, S.game:linkReach(), from.conn and IDX.c or IDX.r, true)
    end

    -- The thread being pulled.
    if S.mode == "grow" and S.drag then
        local tx, tz, ty = S.hover.x, S.hover.z, 0.5
        if S.hover.node then tx, tz, ty = S.hover.node.x, S.hover.node.z, S.hover.node.y end
        if tx then
            local ok = S.hover.node and S.game:canLink(S.drag, S.hover.node)
            local k = ok and IDX.l or IDX.r
            local steps = max(2, ceil(sqrt((tx - S.drag.x) ^ 2 + (tz - S.drag.z) ^ 2) / 0.6))
            for s = 0, steps do
                if s % 4 < 3 then
                    local f = s / steps
                    local x, z = S.drag.x + (tx - S.drag.x) * f, S.drag.z + (tz - S.drag.z) * f
                    local i, j, d = S.world:toImage(x, max(S.world:groundAt(x, z) + 0.4, S.drag.y + (ty - S.drag.y) * f), z)
                    if visible(floor(i), floor(j), d + 1.5) then put(k, i, j) end
                end
            end
        end
    end

    -- Then everything standing up, furthest first.
    local movers = {}
    local function add(x, y, z, draw)
        local _, _, d = S.world:toImage(x, y, z)
        movers[#movers + 1] = { d = d, draw = draw }
    end
    local wilt = 1 - S.game.heartHp / S.game.heartMax
    -- The seed's own pose: a dandelion's spent life, a sunflower's night, a
    -- flytrap's bite.
    local sd, pose = S.game.seed, nil
    if sd.regrow and S.game.regrows < sd.regrow then pose = "bald"
    elseif sd.sun and S.game.weather == "night" and not S.game.mods.helio then pose = "night"
    elseif sd.trap and S.game.snapped and S.game.clock - S.game.snapped < 0.3 then pose = "shut" end
    add(S.game.heart.x, S.game.heart.y, S.game.heart.z, function()
        stamp(M.sprout(wilt, sd.id, pose), S.game.heart.x, S.game.heart.y - 1, S.game.heart.z, S.heartFlash > 0 and T.FLASH or nil)
    end)
    for _, n in ipairs(S.game.nodes) do
        local t = n.tower
        if t then
            add(n.x, n.y, n.z, function()
                local look = towerLook(t, n.id)
                -- Picked up to pull a thread from, or selected: lined in one pixel.
                if S.mode == "grow" and S.drag == n then outline(look, n.x, n.y, n.z, IDX.l)
                elseif S.selected == t then outline(look, n.x, n.y, n.z, IDX.w) end
                stamp(look, n.x, n.y, n.z, t.flash > 0 and T.FLASH or remapFor(t))
                if t.boost then circling(n.x, n.y + 7, n.z, IDX.w, 4, 6) end
                -- A stinkhorn always has a fly or two about it.
                if t.kind == "stink" and t.hunger ~= "dormant" and t.branch ~= 2 then circling(n.x, n.y + 17, n.z, IDX.o, 2, 4) end
                if t.webbed > 0 then web(n.x, n.y + 7, n.z) end
                if t.stun > 0 then circling(n.x, n.y + 15, n.z, IDX.t, 3, 4) end
                local cap = S.game:reserveMax(t)
                if cap > 0 and (t.reserve < cap - 0.05 or not n.conn) then
                    bar(n.x, n.y + 17, n.z, t.reserve / cap, n.conn and IDX.l or IDX.r)
                end
                local hp = S.game:maxHp(t)
                if t.hp < hp - 0.5 then bar(n.x, n.y + 21, n.z, t.hp / hp, IDX.r) end
            end)
        elseif towerMode and S.hover.node == n and not n.heart then
            add(n.x, n.y, n.z, function()
                local ok = S.game:canBuild(S.mode, n)
                stamp(M.tower(S.mode), n.x, n.y, n.z, ok and T.DARKER or T.DARKER2)
            end)
        end
    end
    for _, m in ipairs(S.game.mats) do
        if m.kind == "shelf" then
            add(m.x, m.y, m.z, function()
                local look = towerLook(m, m.c + m.r)
                if S.selected == m then outline(look, m.x, m.y, m.z, IDX.w) end
                stamp(look, m.x, m.y, m.z, m.chewed and floor(S.game.clock * 10) % 2 == 0 and T.DARKER or nil)
                local hp = S.game:maxHp(m)
                if m.hp < hp - 0.5 then bar(m.x, m.y + 20, m.z, m.hp / hp, IDX.t) end
            end)
        end
    end
    if trailMode and S.mode == "shelf" and S.hover.c and not S.hover.button and S.world:distAt(S.hover.c, S.hover.r) then
        local x, z = S.hover.c * 16 + 8, S.hover.r * 16 + 8
        local y = S.world:groundAt(x, z)
        add(x, y, z, function()
            local ok = S.game:canLay(S.mode, S.hover.c, S.hover.r)
            stamp(M.tower(S.mode), x, y, z, ok and T.DARKER or T.DARKER2)
        end)
    end
    for _, c in ipairs(S.game.corpses) do
        local g = S.world:groundAt(c.x, c.z)
        -- Carried down a tunnel, it is out of sight with its ant.
        if not (c.carried and c.carried.hidden) then add(c.x, g, c.z, function()
            local remap = T.DARKER
            if c.absorb then remap = floor(S.game.clock * 10) % 2 == 0 and T.DARKER2 or T.DARKER end
            stamp(M.corpse(c.kind, turned(c.h or 0), c.fruit), c.x, g + (c.carried and 2.5 or 0), c.z, remap)
        end) end
    end
    for _, e in ipairs(S.game.enemies) do
        local size = D.ENEMIES[e.kind].size or 1
        if not e.under and not e.hidden then add(e.x, e.y, e.z, function()
            local remap = e.flash > 0 and T.FLASH or nil
            local host = e.infected and e.infected > 0
            if host and not remap then remap = INFECT end
            -- At night what is not in a lamp's light is hard to see.
            if night and not remap and not lit(e.x, e.z) then remap = T.DARKER end
            stamp(enemyPicture(e), e.x, e.y, e.z, remap)
            if host and floor(S.game.clock * 6) % 2 == 0 then circling(e.x, e.y + 6, e.z, IDX.t, 2, 3) end
            if e.stun > 0 then circling(e.x, e.y + 8 * size, e.z, IDX.s, 3, 3) end
            if e.mark > 0 then
                local i, j = S.world:toImage(e.x, e.y + 9 * size + 3, e.z)
                put(IDX.l, i, j - 1); put(IDX.l, i - 1, j); put(IDX.l, i + 1, j); put(IDX.w, i, j)
            end
            if e.hp < e.maxHp and e.kind ~= "mite" and not e.boss then
                bar(e.x, e.y + (e.kind == "brine" and 12 or 10), e.z, e.hp / e.maxHp, IDX.r)
            end
        end) end
        if e.ballHp and e.ballHp > 0 then
            local bx, bz = S.game:ballAt(e)
            local g = S.world:groundAt(bx, bz)
            add(bx, g, bz, function()
                local cracked = e.ballHp < e.ballMax * 0.4
                stamp(M.ball(turned(e.h), floor((e.ballRoll or 0) * 3) % 4, cracked), bx, g, bz, e.ballFlash > 0 and T.FLASH or nil)
            end)
        end
    end
    for _, s in ipairs(S.game.shots) do
        if s.kind == "spore" then
            local x, y, z = arc(s, 16)
            add(x, y, z, function() dot(x, y, z, IDX.w, IDX.t) end)
        elseif s.kind == "shell" then
            local x, y, z = arc(s, 46)
            add(x, y, z, function()
                local i, j, d = S.world:toImage(x, y, z)
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
    for _, c in ipairs(S.game.clouds) do
        local fade = min(1, c.life / 0.6)
        for s = 0, 21 do
            if (s * 7) % 10 < fade * 10 then
                local a = s / 22 * 2 * math.pi + S.game.clock * 0.6
                local rr = c.r * (0.25 + 0.75 * ((s * 7) % 5) / 4)
                local x, z = c.x + math.cos(a) * rr, c.z + math.sin(a) * rr
                local i, j, d = S.world:toImage(x, S.world:groundAt(x, z) + 1.5 + (s % 3) + math.sin(S.game.clock * 2 + s) * 0.8, z)
                if visible(floor(i), floor(j), d + 2) then put(s % 3 == 0 and IDX.d or IDX.m, i, j) end
            end
        end
    end

    for _, p in ipairs(S.game.fx) do
        if p.cloud then
            local f = 1 - p.life / p.max
            local r = p.r * (0.5 + 0.5 * f)
            local n = p.r > 14 and 44 or 30
            for s = 0, n - 1 do
                if flair.dice:random() > f * 0.8 then
                    local a = s / n * 2 * math.pi + f
                    local rr = r * (0.4 + 0.6 * ((s * 7) % 5) / 4)
                    local x, z = p.x + math.cos(a) * rr, p.z + math.sin(a) * rr
                    local i, j, d = S.world:toImage(x, S.world:groundAt(x, z) + 1 + f * 4 + (s % 3), z)
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
                    local i, j, d = S.world:toImage(x, S.world:groundAt(x, z) + 0.5, z)
                    local k = p.honey and (s % 2 == 0 and IDX.t or IDX.w) or (s % 2 == 0 and IDX.n or IDX.t)
                    if visible(floor(i), floor(j), d + 1) then put(k, i, j); put(IDX.u, i, j + 1) end
                end
            end
        elseif p.streak then
            if p.t >= 0 then
                local f = min(1, p.t / p.max)
                local x, z = p.x + (p.tx - p.x) * f, p.z + (p.tz - p.z) * f
                local i, j, d = S.world:toImage(x, p.y + math.sin(f * math.pi) * 6, z)
                if visible(floor(i), floor(j), d + 2) then put(IDX[p.k], i, j); put(IDX[p.k], i + 1, j) end
            end
        elseif p.shock or p.splat then
            -- On the ground, drawn with it.
        elseif p.star then
            -- A needle's shot leaving: a cross of light at its tip.
            local i, j, d = S.world:toImage(p.x, p.y, p.z)
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
                    local y = max(S.world:groundAt(x, z) + 0.3, p.ay + (p.by - p.ay) * u - f * 3)
                    local i, j, d = S.world:toImage(x, y, z)
                    if visible(floor(i), floor(j), d + 1.5) then put(f < 0.3 and IDX.t or IDX.n, i, j) end
                end
            end
        elseif p.glow then
            local f = p.t / p.max
            local x, z = p.x + (p.tx - p.x) * f, p.z + (p.tz - p.z) * f
            local i, j, d = S.world:toImage(x, S.world:groundAt(x, z) + 1 + math.sin(f * math.pi) * 4, z)
            if visible(floor(i), floor(j), d + 2) then put(IDX.l, i, j) end
        else
            local i, j, d = S.world:toImage(p.x, p.y, p.z)
            if visible(floor(i), floor(j), d + 1) then put(IDX[p.k], i, j) end
        end
    end

    if fade < 1 then
        -- What falls leads the ground: the rain or snow starts in the first
        -- part of the change, and stops in the first part of its going while
        -- the ground is still drying or melting.
        if flair.sky.from then drawWeather(flair.sky.from, max(0, 1 - fade / 0.3)) end
        if flair.sky.to then drawWeather(flair.sky.to, min(1, fade / 0.3)) end
    elseif sky then
        drawWeather(sky)
    end

    S.overlayImage:replacePixels(S.overlay)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(S.overlayImage, 0, 0)
    S.camx, S.camy, S.cw, S.ch = cx0, cy0, cw0, ch0
end

--- lettering and the HUD -----------------------------------------------------------------

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
            local name = D.ENEMIES[kind].boss and D.ENEMIES[kind].name or D.ENEMIES[kind].short or kind:upper()
            parts[#parts + 1] = (D.ENEMIES[kind].boss and "" or (count[kind] .. " ")) .. name
        end
    end
    return table.concat(parts, "  ")
end

-- A tower's name at its tier: the upgrade's, once it has one.
local function towerName(t)
    if t.branch then return D.TOWER[t.kind].up[t.branch][t.tier].name end
    return D.TOWER[t.kind].name
end

-- What to say at the bottom when nothing is hovered: the next thing to learn.
local function hint()
    if S.game.phase ~= "build" then
        local brine = false
        for _, e in ipairs(S.game.enemies) do if e.kind == "brine" and e.slide then brine = true end end
        if brine then return say("BRINE IN THE NETWORK! PRUNE (X) THE LINK IT IS ON", "BRINE IN THE NETWORK! PRUNE THE LINK IT IS ON"), "r" end
        return nil
    end
    local living = 0
    for _, l in ipairs(S.game.links) do if l.state ~= "cut" then living = living + 1 end end
    local towers = 0
    for _, n in ipairs(S.game.nodes) do if n.tower then towers = towers + 1 end end
    if living == 0 then return "DRAG FROM THE SPROUT TO A POCKET TO GROW A LINK", "g" end
    if towers == 0 then return say("PICK A FRUITING BODY BELOW, THEN CLICK A LINKED POCKET", "PICK A FRUITING BODY BELOW, THEN TAP A LINKED POCKET"), "g" end
    local nxt = S.game:nextWave()
    if nxt then
        for _, g in ipairs(nxt) do
            local e = D.ENEMIES[g[1]]
            if e.boss then return "BOSS NEXT: " .. e.name .. ". " .. e.blurb, "r" end
        end
    end
    if S.game.newSpecies then
        local kind = S.game.newSpecies
        local grown = false
        for _, n in ipairs(S.game.nodes) do if n.tower and n.tower.kind == kind then grown = true end end
        for _, m in ipairs(S.game.mats) do if m.kind == kind then grown = true end end
        if not grown then return "NEW SPECIES: " .. D.TOWER[kind].name .. ". " .. D.TOWER[kind].blurb, "l" end
    end
    if nxt then
        for _, g in ipairs(nxt) do
            if not S.game.seen[g[1]] then return "NEW: " .. D.ENEMIES[g[1]].name .. ". " .. D.ENEMIES[g[1]].blurb, "t" end
        end
        if nxt.weather then
            local wx = D.WEATHER[nxt.weather]
            return wx.name .. " NEXT WAVE: " .. wx.blurb, "s"
        end
    end
    if S.selected and S.game:upgrades(S.selected)[1] and S.game.wave <= 2 then
        return say("UPGRADES: CLICK ONE IN THE PANEL, OR Z / C", "UPGRADES: TAP ONE IN THE PANEL"), "l"
    end
    if S.game.wave == 0 then return say("SPACE TO START THE FIRST WAVE", "TAP START FOR THE FIRST WAVE"), "g" end
end

local function tooltip()
    if S.hover.mutation then
        local m = S.game.choices[S.hover.mutation]
        return (m.seed and (S.game.seed.short .. " ") or "") .. m.name .. ": " .. m.blurb, m.seed and "g" or "l"
    end
    if S.game.phase == "mutate" then return say("THE NETWORK MUTATES. PICK ONE (1 2 3)", "THE NETWORK MUTATES. PICK ONE"), "l" end
    if S.hover.up then
        local ok, why = S.game:canUpgrade(S.selected, S.hover.up.branch)
        return "GROW " .. S.hover.up.row.name .. ": " .. S.hover.up.row.cost .. (ok and "" or ("  (" .. why .. ")")), ok and "l" or "r"
    end
    if S.hover.button then
        local b = BUTTONS[S.hover.button]
        if b.tower and not S.game:unlocked(b.mode) then
            return b.name .. ": UNLOCKS AFTER WAVE " .. S.game:unlockAt(b.mode), "r"
        end
        if b.action then
            local list, cost = S.game:repairable(), 0
            for _, l in ipairs(list) do cost = cost + S.game:repairCost(l) end
            if #list == 0 then return "REGROW ALL: NO CUT LINKS", "s" end
            return "REGROW " .. #list .. " CUT LINK" .. (#list > 1 and "S" or "") .. ", NEAREST THE SPROUT FIRST: " .. cost,
                S.game.nutrients >= cost and "l" or "r"
        end
        if b.tower and b.mode == S.mode then return say(b.name .. ": CLICK AGAIN TO READ IT", b.name .. ": TAP AGAIN TO READ IT"), "w" end
        return b.name .. (b.cost and (" (" .. b.cost .. ")") or "") .. ": " .. b.blurb, "w"
    end
    if S.hover.turn == 1 then return say("TURN THE BOARD (E)", "TURN THE BOARD"), "w" end
    if S.hover.turn == -1 then return say("TURN THE BOARD BACK (Q)", "TURN THE BOARD BACK"), "w" end
    if S.hover.wave then
        return S.game.phase == "build" and say("START THE NEXT WAVE (SPACE)", "START THE NEXT WAVE") or say("GAME SPEED (F)", "GAME SPEED"), "w"
    end
    if S.mode == "grow" and S.drag and S.hover.node and S.hover.node ~= S.drag then
        local ok, cost, why = S.game:canLink(S.drag, S.hover.node)
        if ok then return "GROW LINK: " .. cost, "l" end
        return (why or "") .. (cost and ("  (" .. cost .. ")") or ""), "r"
    end
    if S.mode == "pulse" and S.hover.node then
        if S.game.pulseCd > 0 then return "PULSE REGROWING: " .. math.ceil(S.game.pulseCd) .. "S", "r" end
        if not S.hover.node.conn then return "NOT FED: THE PULSE CANNOT REACH IT", "r" end
        return "SEND THE PULSE HERE", "l"
    end
    if S.hover.node and S.hover.node.tower then
        local t = S.hover.node.tower
        local s = towerName(t)
        if S.mode == "prune" then return "CLEAR " .. s .. ": +" .. floor(t.spent * D.SELL), "r" end
        if t.webbed > 0 then s = s .. ": WEBBED SHUT"
        elseif t.stun > 0 then s = s .. ": STUNNED"
        elseif t.hunger == "dormant" then s = s .. ": DORMANT, NO NUTRIENTS"
        elseif not S.hover.node.conn then s = s .. ": CUT OFF, ON ITS RESERVE"
        elseif t.thirsty then s = s .. ": THIRSTY, NEEDS A RELAY BESIDE IT"
        elseif t.hunger == "starved" then s = s .. ": STARVED" end
        if t.hp < S.game:maxHp(t) then s = s .. "  HP " .. math.ceil(t.hp) end
        if t.kind == "puffer" then s = s .. "  PUFFS " .. max(1, min(4, S.game:degree(S.hover.node))) end
        if t.kind == "needle" and S.game:degree(S.hover.node) == 1 then s = s .. "  DEAD END X1.8" end
        if t.kind == "lamp" then s = s .. "  GLOW " .. floor(t.glow or 0) end
        if t.kind == "mane" then s = s .. "  TENDS " .. members(t.care) .. " NODES" end
        if t.kind == "relay" then s = s .. "  PUMPS INTO " .. #S.game:neighbours(S.hover.node) end
        if t.kind == "inky" then s = s .. "  FEEDS " .. #S.game:neighbours(S.hover.node) .. " FIRST" end
        if t.kind == "cordyceps" then s = s .. "  HOLD X" .. string.format("%.1f", S.game:deepHold(t)) end
        if t.kind == "stink" then s = s .. "  REEKS DOWN " .. S.game:degree(S.hover.node) .. " LINKS" end
        if t.kind == "mortar" and S.hover.node.pocket.high then s = s .. "  HIGH: NO MIN RANGE" end
        if t.kind == "giant" then
            local k = S.game:rooted(t)
            if t.grown < 1 then s = s .. "  GROWING " .. floor(t.grown * 100) .. "%"
            else s = s .. "  " .. k .. " NODES: HITS " .. floor(S.game:stat(t, "damage") + S.game:stat(t, "perNode") * k) end
        end
        if S.hover.node.ringed then s = s .. "  RING" end
        if (t.amp or 1) > 1 then s = s .. "  AMPED" end
        return s .. "  " .. S.hover.node.quality:upper() .. " POCKET", "w"
    end
    if S.hover.node then
        local n = S.hover.node
        if n.heart then
            -- The seed it grew from, and what it has left to give.
            local sd = S.game.seed
            local s = sd.name .. ": " .. (sd.price and sd.blurb or "IF IT DIES, YOU LOSE")
            if S.game.regrows > 0 then s = s .. ". REGROWS " .. S.game.regrows .. " MORE" end
            if S.game.pods > 0 then s = s .. ". " .. S.game.pods .. " FREE LINKS" end
            return s, "g"
        end
        local s = n.pocket.kind:upper() .. ": " .. n.quality:upper() .. " POCKET"
        if (n.salted or 0) > 0 then s = s .. ", SALTED" end
        if n.quality == "rich" then s = s .. ". +30% POWER, PAYS SUGAR" elseif n.quality == "poor" then s = s .. ". -25% POWER" end
        if n.pocket.high then s = s .. ". HIGH GROUND" elseif n.pocket.low then s = s .. ". LOW: RAIN WASHES IT" end
        if D.TOWER[S.mode] and not D.TOWER[S.mode].onTrail then
            local ok, why = S.game:canBuild(S.mode, n)
            if ok then return "GROW " .. D.TOWER[S.mode].name .. " HERE: " .. D.TOWER[S.mode].cost, "l" end
            if why then return why, "r" end
        end
        return s, "w"
    end
    if S.hover.link then
        local l = S.hover.link
        if S.mode == "prune" then
            return "PRUNE LINK: +" .. floor(l.cost * (l.state == "alive" and D.LINK.prune or D.LINK.prune * 0.5)), "r"
        end
        if l.state == "cut" then
            if l.salted then return "SALTED LINK. IT WILL NOT REGROW: PRUNE IT", "w" end
            if l.hand then return "REGROWING", "l" end
            return say("CUT LINK. CLICK TO REGROW: ", "CUT LINK. TAP TO REGROW: ") .. S.game:repairCost(l), "l"
        end
        if l.state == "grow" then return "GROWING", "l" end
        local s = "LINK " .. floor(l.hp) .. "/" .. floor(S.game:linkHp()) .. "  FLOW " .. (l.cap or D.LINK.cap)
        if l.thick then s = s .. " (RELAY)" end
        if not l.a.conn then s = s .. "  NOT FED" end
        return s, "w"
    end
    if D.TOWER[S.mode] and D.TOWER[S.mode].onTrail and S.hover.c then
        local d = D.TOWER[S.mode]
        local ok, why = S.game:canLay(S.mode, S.hover.c, S.hover.r)
        if ok then return "GROW " .. d.name .. ": " .. d.cost, "l" end
        if not S.world:distAt(S.hover.c, S.hover.r) then return d.name .. " GOES ON THE TRAIL", "r" end
        return why or "", "r"
    end
    if S.mode == "prune" and S.hover.mat then return "LIFT " .. D.TOWER[S.hover.mat.kind].name .. ": +" .. S.game:liftValue(S.hover.mat), "r" end
    if S.hover.mat and S.mode == "grow" then
        local m = S.hover.mat
        local s = towerName(m)
        if m.kind == "mat" then
            s = s .. (m.fed and (": " .. m.draped .. " LINK" .. (m.draped > 1 and "S" or "") .. " OVER IT")
                or ": WITHERING " .. math.ceil(m.life) .. "S")
            s = s .. "  SLOW " .. floor((1 - S.game:matSlow(m)) * 100) .. "%"
        else s = s .. "  HP " .. math.ceil(m.hp) .. "/" .. S.game:maxHp(m) end
        return s, "w"
    end
    if S.mode == "grow" and S.drag then return say("LET GO OVER A GLOWING POCKET", "LET GO OVER A GLOWING POCKET"), "l" end
    if S.mode == "pulse" then
        if S.game.pulseCd > 0 then return "PULSE REGROWING: " .. math.ceil(S.game.pulseCd) .. "S", "r" end
        return say("CLICK A FED NODE TO SEND THE PULSE", "TAP A FED NODE TO SEND THE PULSE"), "l"
    end
end

-- A turn button: a ring of ground going round, an arrowhead on its end, and
-- a mark on the ring for the side the camera is on. d = -1 is the clockwise
-- one mirrored.
local function drawTurnButton(d)
    local x, y, w, h = turnRect(d)
    local going = S.turning and S.turning.d == d
    box(x, y, w, h, (S.hover.turn == d or going) and "n" or "u", S.hover.turn == d and "t" or "o")
    local cx, cy = x + floor(w / 2), y + floor(h / 2) + 1
    local spin = S.turning and S.turning.t / TURN_TIME * (S.turning.angle > 0 and 1 or -1) * d or 0
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
        color(q == S.world.turn and "l" or "k")
        love.graphics.rectangle("fill", x + 3 + q * 2, y + 2, 1, 1)
    end
    if not S.touch then text(d == 1 and "E" or "Q", x + w - 4, y + 1, "s") end
end

local function drawHud()
    -- The top strip.
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.inset.t + TOP - 1)
    local ty = S.inset.t + 3
    local inc = S.game.income or 0
    local s = "NUTRIENTS " .. floor(S.game.nutrients)
    -- Short of them: red, and a shiver. A lot just in: bright.
    local nk, nx = "l", 0
    if flair.nut.t > 0 then
        nk = flair.nut.k
        if nk == "r" then nx = floor(flair.nut.t * 30) % 2 == 0 and 1 or -1 end
    end
    text(s, S.inset.l + 3 + nx, ty, nk)
    local x = S.inset.l + 3 + Font.width(s) + 2
    if S.game.phase == "wave" then
        local i = (inc >= 0 and "+" or "") .. string.format("%.1f", inc)
        text(i, x + 2, ty, inc >= 0 and "c" or "r")
        x = x + Font.width(i) + 4
    end
    s = "SPROUT " .. math.ceil(S.game.heartHp) .. "/" .. S.game.heartMax
    text(s, x + 8, ty, S.game.heartHp < S.game.heartMax * 0.4 and "r" or "g")
    local w = "WAVE " .. S.game.wave .. "/" .. #S.game.waves
    if S.game.endless then w = "ENDLESS WAVE " .. S.game.wave .. "  BEST " .. max(S.game.best, S.game.cleared) end
    local nxt = S.game:nextWave()
    local right = w
    if nxt and S.game.phase == "build" then right = "NEXT: " .. waveSummary(nxt) .. "   " .. w end
    if S.game.phase == "wave" then
        local left = #S.game.queue
        for _, e in ipairs(S.game.enemies) do left = left + 1 end
        right = left .. " LEFT   " .. w
        if S.game.weather then right = D.WEATHER[S.game.weather].name .. "   " .. right end
    end
    local leftEnd = x + 8 + Font.width(s) + 8
    local rx = S.vw - S.inset.r - Font.width(right) - 3
    -- A narrow screen keeps the wave count and lets the forecast go: the
    -- gates still say how many come in at each.
    if rx < leftEnd and right ~= w then right = w; rx = S.vw - S.inset.r - Font.width(w) - 3 end
    text(right, rx, ty, "w")
    -- Where the weather's name landed, if it is there: the whole strip's
    -- height and a little either side, to be easy to hover or tap.
    S.weatherBox = nil
    local sky = S.game.phase == "wave" and S.game.weather or (S.game.phase == "build" and nxt and nxt.weather)
    if sky and right ~= w then
        local name = D.WEATHER[sky].name
        local nx = S.game.phase == "build" and rx + Font.width("NEXT: ") or rx
        S.weatherBox = { x = nx - 3, y = 0, w = Font.width(name) + 6, h = S.inset.t + TOP, kind = sky, next = S.game.phase == "build" }
    end
    if S.weatherTip and not (S.weatherBox and S.weatherBox.kind == S.weatherTip) then S.weatherTip = nil end
    if S.weatherBox and (S.weatherTip or (not S.touch and S.hover.weather)) then
        local wb = S.weatherBox
        local nm = D.WEATHER[wb.kind].name
        text(nm, wb.x + 3, ty, "t")
    end
    if S.paused then
        if S.touch then centred("PAUSED. TAP THE TOP BAR TO GO ON", floor(S.vh / 2) - 40, "r")
        else text("PAUSED", floor((S.vw - Font.width("PAUSED")) / 2), ty, "r") end
    end

    -- Gates: where the next wave comes in.
    if nxt and S.game.phase == "build" then
        local per = {}
        for _, g in ipairs(nxt) do per[g[4]] = (per[g[4]] or 0) + g[2] * (g[1] == "mite" and D.ENEMIES.mite.swarm or 1) end
        for gate, n in pairs(per) do
            local e = S.world.entrances[gate]
            if e then
                local i, j = S.world:toImage(e.x - 6, S.world:groundAt(e.x, e.z) + 6, e.z)
                local sx, sy = toHud(i, j)
                if floor(S.game.clock * 2) % 2 == 0 then label(n .. " IN", sx - 6, sy - 10, "w", "r") end
            end
        end
    end

    -- The sprout pointed at (or tapped): the seed it grew from, over it.
    if S.hover.node == S.game.heart then
        local h = S.game.heart
        local sx, sy = toHud(S.world:toImage(h.x, h.y + 30, h.z))
        local name = S.game.seed.name
        label(name, sx - floor(Font.width(name) / 2), sy - 4, "g", "o")
    end

    -- Words in the world.
    for _, t in ipairs(S.game.texts) do
        local i, j = S.world:toImage(t.x, t.y, t.z)
        local sx, sy = toHud(i, j)
        sx = sx - floor(Font.width(t.text) / 2)
        text(t.text, sx, sy + 1, "o")
        text(t.text, sx, sy, t.k)
    end

    -- The toolbar.
    for n, b in ipairs(BUTTONS) do
        local bx, by, bw, bh = buttonRect(n)
        local on = S.mode == b.mode
        box(bx, by, bw, bh, on and "n" or "u", on and "l" or (S.hover.button == n and "t" or "o"))
        local cx, cy = bx + floor(bw / 2), by + bh - 9
        if b.action then
            -- A thread with a gap in it, the two ends lit while there are cuts
            -- to mend; how many, and what it all costs.
            local list, cost = S.game:repairable(), 0
            for _, l in ipairs(list) do cost = cost + S.game:repairCost(l) end
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
                text(c, bx + bw - Font.width(c) - 1, by + bh - 6, S.game.nutrients >= cost and "l" or "r")
                local k = tostring(#list)
                text(k, bx + bw - Font.width(k) - 1, by + 1, "w")
            end
        elseif b.mode == "prune" then
            text("X", cx - 1, by + 9, "r")
        elseif b.mode == "pulse" then
            local ready = S.game.pulseCd <= 0
            local k = ready and (floor(S.game.clock * 3) % 2 == 0 and "w" or "l") or "d"
            color(k)
            for s = -4, 4 do love.graphics.rectangle("fill", cx + s, by + 12 - floor(abs(s) / 2) * ((s % 2 == 0) and 1 or -1), 1, 1) end
            love.graphics.rectangle("fill", cx - 1, by + 10, 3, 3)
            if not ready then
                local c = tostring(math.ceil(S.game.pulseCd))
                text(c, bx + bw - Font.width(c) - 1, by + bh - 6, "r")
            end
        else
            local open = S.game:unlocked(b.mode)
            local pic = icon(b.mode, nil, 0, on and (S.game.clock * 0.7) % 1 or 0)
            local afford = S.game.nutrients >= (b.cost or 0)
            blit(pic, cx, b.mode == "mat" and by + 14 or by + 21, (not afford or not open) and T.DARKER2 or nil)
        end
        if not S.touch then text(b.key, bx + 1, by + 1, "s") end
        if b.tower and not S.game:unlocked(b.mode) then
            local c = "W" .. S.game:unlockAt(b.mode)
            text(c, bx + bw - Font.width(c) - 1, by + bh - 6, "k")
        elseif b.cost then
            local c = tostring(b.cost)
            text(c, bx + bw - Font.width(c) - 1, by + bh - 6, S.game.nutrients >= b.cost and "l" or "r")
        end
    end
    local wx, wy, ww, wh = waveRect()
    if S.game.phase == "build" then
        box(wx, wy, ww, wh, S.hover.wave and "m" or "d", "g")
        text("START", wx + floor((ww - Font.width("START")) / 2), wy + 5, "g")
        local s2 = "WAVE " .. (S.game.wave + 1)
        text(s2, wx + floor((ww - Font.width(s2)) / 2), wy + 13, "w")
        if not S.touch then text("SPACE", wx + floor((ww - Font.width("SPACE")) / 2), wy + 20, "s") end
    else
        box(wx, wy, ww, wh, "u", S.hover.wave and "t" or "o")
        local s2 = "SPEED X" .. S.speed
        text(s2, wx + floor((ww - Font.width(s2)) / 2), wy + 9, "w")
        if not S.touch then text("F", wx + floor((ww - 3) / 2), wy + 18, "s") end
    end
    drawTurnButton(1)
    drawTurnButton(-1)

    local tipBase = barTop()

    -- A boss on the board: its name and its health across the top.
    local boss
    for _, e in ipairs(S.game.enemies) do if e.boss then boss = e break end end
    if boss then
        local d = D.ENEMIES[boss.kind]
        local fl, fr = freeSpan()
        local w = min(170, fr - fl - 20)
        local bx, by = floor((fl + fr - w) / 2), S.inset.t + TOP + 3
        -- A train's health is all of its segments'.
        local hp, top = boss.hp, boss.maxHp
        if boss.train then
            hp, top = 0, boss.train.max
            for _, e in ipairs(S.game.enemies) do if e.train == boss.train and not e.dead then hp = hp + e.hp end end
        end
        box(bx, by, w, 4, "u", "o")
        color("r")
        love.graphics.rectangle("fill", bx, by, floor(w * max(0, hp / top)), 4)
        if boss.ballHp and boss.ballHp > 0 then
            box(bx, by + 6, w, 2, "u", "o")
            color("t")
            love.graphics.rectangle("fill", bx, by + 6, floor(w * boss.ballHp / boss.ballMax), 2)
        end
        local name = d.name .. (boss.under and (boss.kind == "mole" and " (UNDERGROUND)" or " (UNDER WATER)") or "")
        text(name, floor(bx + (w - Font.width(name)) / 2), by + (boss.ballHp and boss.ballHp > 0 and 11 or 7), "w")
    end
    if S.game.bossIntro then
        local d = D.ENEMIES[S.game.bossIntro.kind]
        if floor(S.game.bossIntro.t * 4) % 4 ~= 0 or S.game.bossIntro.t < 2.5 then
            centred(d.name, S.inset.t + TOP + 22, "r", "o")
        end
        centred(d.blurb, S.inset.t + TOP + 33, "w", "o")
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
    if P then Panel.draw(P) end

    -- What the weather does, dropped from its name in the top strip.
    local wb = S.weatherBox
    if wb and (S.weatherTip or (not S.touch and S.hover.weather)) then
        local d = D.WEATHER[wb.kind]
        local tw = min(150, S.vw - S.inset.l - S.inset.r - 8)
        local lines = wrapLines(d.blurb, tw - 8)
        local head = d.name .. (wb.next and " NEXT WAVE" or "")
        local th = 13 + 7 * #lines
        local tx = max(S.inset.l + 4, min(S.vw - S.inset.r - 4 - tw, wb.x + floor(wb.w / 2) - floor(tw / 2)))
        local ty = S.inset.t + TOP + 3
        box(tx, ty, tw, th, "u", "t")
        text(head, tx + 4, ty + 3, "t")
        for n, l in ipairs(lines) do text(l, tx + 4, ty + 6 + 7 * n, "w") end
        if S.touch then text("X", tx + tw - 7, ty + 3, "s") end
    end

    if S.game.phase == "mutate" then
        local cs = mutationCards()
        centred("THE NETWORK MUTATES", cs[1].y - 14, "l", "o")
        for k, c in ipairs(cs) do
            -- The seed's own is in its green.
            local own = c.m.seed ~= nil
            box(c.x, c.y, c.w, c.h, S.hover.mutation == k and "n" or "u", S.hover.mutation == k and "l" or (own and "g" or "c"))
            text(c.m.name, c.x + 4, c.y + 4, own and "g" or "l")
            if not S.touch then text(tostring(k), c.x + c.w - 6, c.y + 4, "s") end
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

    if S.game.phase == "won" then
        local last = S.level == D.LEVELS[#D.LEVELS]
        centred(S.level.name .. (S.game.challenge and " (CHALLENGE)" or "") .. ": THE SPROUT LIVES", floor(S.vh / 2) - 24, "g")
        centred("KILLS " .. S.game.stats.kills .. "   BOSSES " .. S.game.stats.bosses .. "   DRUNK " .. floor(S.game.stats.drunk) .. "   CUTS " .. S.game.stats.cuts, floor(S.vh / 2) - 12, "w")
        local buttons = wonButtons()
        for _, b in ipairs(buttons) do
            local on = S.hover.won == b.id
            local endless = b.id == "endless"
            box(b.x, b.y, b.w, b.h, on and "n" or "u", endless and "r" or (on and "l" or "c"))
            text(b.text, b.x + 5, b.y + 5, endless and "r" or "w")
        end
        local y = buttons.bottom + 1
        if Profile.records[S.level.id] then centred("ENDLESS BEST: " .. Profile.records[S.level.id] .. " WAVES", y, "t"); y = y + 10 end
        centred("+" .. S.game.spores .. " SPORES   " .. Profile.spores .. " IN THE BANK", y, "t"); y = y + 10
        if S.game.offer then centred("NEW IN THE SPORE BANK: " .. D.TOWER[S.game.offer].name, y, "g"); y = y + 10 end
        if S.game.newSeed then centred("NEW SEED FOR SALE: " .. D.SEED[S.game.newSeed].name, y, "g"); y = y + 10 end
        if last and not S.game.challenge then centred("CHALLENGE MODE IS OPEN", y, "r") end
    elseif S.game.phase == "lost" then
        centred("THE SPROUT HAS WILTED", floor(S.vh / 2) - 24, "r")
        if S.game.endless then
            centred("ENDLESS: YOU HELD " .. S.game.cleared .. " WAVES", floor(S.vh / 2) - 12, "w")
            centred(S.game.record and "A NEW RECORD!" or ("BEST " .. S.game.best), floor(S.vh / 2) + 12, S.game.record and "g" or "t")
        else
            centred("YOU HELD " .. (S.game.wave - 1) .. " WAVES OF " .. #S.game.waves, floor(S.vh / 2) - 12, "w")
        end
        centred(say("R: TRY AGAIN   M: LEVELS", "TAP FOR THE LEVELS"), floor(S.vh / 2), "l")
        centred("+" .. S.game.spores .. " SPORES   " .. Profile.spores .. " IN THE BANK", floor(S.vh / 2) + 24, "t")
    end
end

local function drawMenu()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local cards, switch = levelCards()
    centred("MYCELIO TD", cards[1].y - 30, "g", "o")
    centred("WHERE DOES THE SPROUT COME UP?", cards[1].y - 18, "t", "o")
    for k, c in ipairs(cards) do
        local l = D.LEVELS[k]
        local open, on = Profile.levelOpen(k), S.hover.level == k
        box(c.x, c.y, c.w, c.h, on and open and "n" or "u", Profile.won[l.id] and "g" or (open and (on and "l" or "c") or "k"))
        text(k .. "  " .. l.name, c.x + 4, c.y + 4, open and "w" or "k")
        if not open then
            text("WIN " .. D.LEVELS[k - 1].name, c.x + 4, c.y + 14, "r")
            text("TO OPEN IT", c.x + 4, c.y + 21, "r")
        else
            local y = wrap(l.idea, c.x + 4, c.y + 14, c.w - 8, "t")
            wrap("BOSS: " .. l.boss, c.x + 4, y + 1, c.w - 8, "r")
            local tag = Profile.won[l.id] and "WON" or (#l.waves .. " WAVES")
            text(tag, c.x + c.w - Font.width(tag) - 4, c.y + c.h - 8, Profile.won[l.id] and "g" or "s")
            -- The endless record, bottom left, once there is one.
            if Profile.records[l.id] then text("BEST " .. Profile.records[l.id], c.x + 4, c.y + c.h - 8, "r") end
        end
    end
    if Profile.challengeOpen() then
        local c = switch
        box(c.x, c.y, c.w, c.h, S.hover.challenge and "n" or "u", S.challenge and "r" or "k")
        local s = "CHALLENGE: " .. (S.challenge and "ON" or "OFF")
        text(s, c.x + floor((c.w - Font.width(s)) / 2), c.y + 5, S.challenge and "r" or "w")
        if S.hover.challenge or S.challenge then
            centred("A LAST WAVE ON ANY LEVEL: THE BOMBARDIER BEETLE", c.y + c.h + 6, "r", "o")
        end
    end
    local cb = codex.button()
    box(cb.x, cb.y, cb.w, cb.h, S.hover.codex and "n" or "u", S.hover.codex and "t" or "c")
    text("ENCYCLOPEDIA", cb.x + 4, cb.y + 4, "w")
    text("SPORES " .. Profile.spores, cb.x + cb.w + 6, S.inset.t + 7, "t")
    local sw = audio.switch()
    local lv = Sfx.level >= 1 and "LOUD" or (Sfx.level > 0 and "QUIET" or "OFF")
    box(sw.x, sw.y, sw.w, sw.h, S.hover.sound and "n" or "u", Sfx.level > 0 and "c" or "k")
    local st = "SOUND " .. lv
    text(st, sw.x + floor((sw.w - Font.width(st)) / 2), sw.y + 3, Sfx.level > 0 and "l" or "k")
    local hintY = S.vh - S.inset.b - 12
    centred(say("1-" .. #D.LEVELS .. " OR CLICK A LEVEL", "TAP A LEVEL") .. (Profile.challengeOpen() and say("   C: CHALLENGE", "") or "")
        .. say("   E: ENCYCLOPEDIA", ""), hintY, "s", "o")
end

-- The panel's button in the loadout: plant or buy a seed, bring, leave or buy a species.
local function drawPanelButton(P)
    local b = P.button
    if b and P.seed then
        -- A seed: planted, plantable, for sale, or waiting on a win.
        local sd = D.SEED[P.seed]
        local s, fill, edge, k
        if Profile.ownsSeed(sd.id) then
            local on = S.pick.seed == sd.id
            s, fill, edge, k = on and "PLANTED" or "PLANT IT", on and "u" or "d", on and "t" or "g", on and "w" or "g"
        elseif Profile.seedForSale(sd.id) then
            local can = Profile.spores >= sd.price
            s = can and ("BUY IT: " .. sd.price .. " SPORES") or (sd.price .. " SPORES. YOU HAVE " .. Profile.spores)
            fill, edge, k = "u", can and "t" or "k", can and "t" or "r"
        else
            s, fill, edge, k = "WIN " .. D.LEVEL[sd.after].name .. " FOR IT", "u", "k", "k"
        end
        box(b.x, b.y, b.w, b.h, S.hover.bring and "n" or fill, edge)
        text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 4, k)
    elseif b and not Profile.owns(P.kind) then
        -- Not had yet: bought here once a win has put it up for sale.
        local price = D.TOWER[P.kind].price
        local s, edge, k
        if Profile.forSale(P.kind) then
            local can = Profile.spores >= price
            s = can and ("BUY IT: " .. price .. " SPORES") or (price .. " SPORES. YOU HAVE " .. Profile.spores)
            edge, k = can and "t" or "k", can and "t" or "r"
        else
            s, edge, k = "WIN " .. Profile.prizeOf(P.kind).name .. " FOR IT", "k", "k"
        end
        box(b.x, b.y, b.w, b.h, S.hover.bring and "n" or "u", edge)
        text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 4, k)
    elseif b then
        local inn = S.pick.set[P.kind]
        local full = not inn and #picked() >= D.LOADOUT
        local s = inn and "LEAVE IT AT HOME" or (full and "SIX ALREADY: DROP ONE" or "BRING IT")
        box(b.x, b.y, b.w, b.h, S.hover.bring and "n" or (inn and "u" or "d"), full and "k" or (inn and "t" or "g"))
        text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 4, full and "k" or (inn and "w" or "g"))
    end
end

local function drawLoadout()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local lv = D.LEVELS[S.pick.n]
    local L = loadoutLayout()
    local list = picked()
    local clock = flair.now()
    centred(lv.name .. (S.challenge and " (CHALLENGE)" or ""), L.top, "g", "o", L.mid)
    text("SPORES " .. Profile.spores, S.inset.l + 4, S.inset.t + 7, "t")
    local count = #list .. "/" .. D.LOADOUT
    centred("PICK A SEED AND THE SPECIES TO BRING  " .. count, L.top + 11, #list == D.LOADOUT and "l" or "t", "o", L.mid)
    text("COMING", floor(L.mid - Font.width("COMING") / 2), L.chipsY - 9, "s")
    text("SEED", floor(L.mid - Font.width("SEED") / 2), L.seedsY - 7, "s")
    text("SPECIES", floor(L.mid - Font.width("SPECIES") / 2), L.cardsY - 7, "s")

    -- The seeds: the planted one lit green, one had in white, one for sale
    -- with its price, one still locked dark.
    for _, c in ipairs(L.seeds) do
        local sd = c.seed
        local own, inn, on = Profile.ownsSeed(sd.id), S.pick.seed == sd.id, S.hover.seed == sd.id
        local sale = not own and Profile.seedForSale(sd.id)
        local edge = inn and "g" or "k"
        if on or S.pick.seedInfo == sd.id then edge = inn and "w" or "t" end
        box(c.x, c.y, c.w, c.h, inn and "d" or (on and "n" or "u"), edge)
        text(c.name, c.x + 4, c.y + 3, inn and "g" or (own and "w" or (sale and "t" or "k")))
    end

    -- The enemy pointed at (or pinned) lights up what answers it.
    local enemy = S.hover.enemy or S.pick.enemy
    local met = enemy and Profile.seen[enemy]
    local answers = {}
    for _, id in ipairs(met and D.COUNTERS[enemy] or {}) do answers[id] = true end
    for _, c in ipairs(L.chips) do
        local boss = D.ENEMIES[c.kind].boss and Profile.seen[c.kind]
        local on = enemy == c.kind
        box(c.x, c.y, c.w, c.h, on and "n" or "u", on and "w" or (boss and "r" or "k"))
        text(c.name, c.x + 3, c.y + 2, boss and "r" or (Profile.seen[c.kind] and "w" or "k"))
    end

    for _, c in ipairs(L.cards) do
        local t = c.t
        local inn, on, ans = S.pick.set[t.id], S.hover.species == t.id, answers[t.id]
        local edge = inn and "l" or "k"
        if ans and floor(clock * 4) % 2 == 0 then edge = "w" end
        if on or S.pick.info == t.id then edge = inn and "w" or "t" end
        box(c.x, c.y, c.w, c.h, (inn or on) and "n" or "u", edge)
        -- The picture kept to its corner of the card: a shelf or the giant is wider.
        local pic = icon(t.id, nil, 0, inn and (clock * 0.7) % 1 or 0)
        love.graphics.setScissor(c.x, c.y, 21, c.h)
        local known = Profile.known(t.id)
        blit(pic, c.x + 11, t.id == "mat" and c.y + c.h - 8 or c.y + c.h - 3, not known and CUT or (not inn and T.DARKER2 or nil))
        love.graphics.setScissor()
        local own = Profile.owns(t.id)
        wrap(known and t.name or "???", c.x + 22, c.y + 3, c.w - 24, inn and "w" or (own and "s" or "k"))
        -- Not had yet: its price once it is for sale, else locked.
        if not own then
            local sale = Profile.forSale(t.id)
            text(sale and (t.price .. " SPORES") or "LOCKED", c.x + 22, c.y + c.h - 7, sale and "t" or "k")
        else
            text(tostring(t.cost), c.x + 22, c.y + c.h - 7, inn and "l" or "k")
        end
        -- The wave it comes in, given what else is brought.
        local at = D.unlockAt(lv, t.id, S.pick.set)
        if own and at > 0 then
            local s = "W" .. at
            text(s, c.x + c.w - Font.width(s) - 2, c.y + c.h - 7, "k")
        end
        if not S.touch then text(t.key, c.x + 1, c.y + 1, "s") end
        if ans then text("!", c.x + c.w - 4, c.y + 2, "w") end
    end

    local b, g = L.back, L.go
    box(b.x, b.y, b.w, b.h, S.hover.back and "n" or "u", S.hover.back and "t" or "k")
    text("BACK", b.x + floor((b.w - Font.width("BACK")) / 2), b.y + 5, "w")
    local ready = #list > 0
    box(g.x, g.y, g.w, g.h, ready and (S.hover.go and "m" or "d") or "u", ready and "g" or "k")
    text("GROW", g.x + floor((g.w - Font.width("GROW")) / 2), g.y + 5, ready and "g" or "k")

    local P = info()
    if P then
        Panel.draw(P)
        drawPanelButton(P)
        if S.pick.full > 0 then centred("ONLY " .. D.LOADOUT .. " COME. DROP ONE FIRST", g.y + g.h + 6, "r", "o", L.mid) end
        return
    end

    -- One line under it all: what is pointed at, or how it works.
    local tip, k
    if S.pick.full > 0 then
        tip, k = "ONLY " .. D.LOADOUT .. " COME. DROP ONE FIRST", "r"
    elseif S.hover.seed then
        local sd = D.SEED[S.hover.seed]
        if Profile.ownsSeed(sd.id) then tip, k = sd.name .. ": " .. sd.blurb, "w"
        elseif Profile.seedForSale(sd.id) then tip, k = sd.name .. ": FOR SALE, " .. sd.price .. " SPORES. YOU HAVE " .. Profile.spores, "t"
        else tip, k = "???: WIN " .. D.LEVEL[sd.after].name .. " TO PUT IT UP FOR SALE", "k" end
    elseif S.hover.species and not Profile.owns(S.hover.species) then
        local t = D.TOWER[S.hover.species]
        if Profile.forSale(t.id) then tip, k = t.name .. ": FOR SALE, " .. t.price .. " SPORES. YOU HAVE " .. Profile.spores, "t"
        else tip, k = "???: WIN " .. Profile.prizeOf(t.id).name .. " TO PUT IT UP FOR SALE", "k" end
    elseif S.hover.species then
        local t = D.TOWER[S.hover.species]
        tip, k = t.name .. ": " .. t.blurb, "w"
    elseif enemy and not met then
        tip, k = "???: NOT MET YET. FACE IT TO LEARN WHAT ANSWERS IT", "k"
    elseif enemy then
        local names = {}
        for _, id in ipairs(D.COUNTERS[enemy] or {}) do names[#names + 1] = D.TOWER[id].name end
        tip, k = D.ENEMIES[enemy].name .. ": " .. D.ENEMIES[enemy].blurb:gsub("%.?$", ".") .. " ANSWER: " .. table.concat(names, ", "), "t"
    elseif not ready then
        tip, k = "BRING AT LEAST ONE", "r"
    else
        tip, k = say("CLICK A SEED TO PLANT IT. CLICK A SPECIES TO READ IT, AGAIN TO BRING OR LEAVE IT. POINT AT AN ENEMY FOR ITS ANSWER",
            "TAP A SEED TO PLANT IT. TAP A SPECIES TO READ IT, AGAIN TO BRING OR LEAVE IT. TAP AN ENEMY FOR ITS ANSWER"), "s"
    end
    local room = S.vw - S.inset.l - S.inset.r - 8
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

-- The title, the first thing up when the game opens: the name over the
-- night, the sprout on the ground and the network growing out under it, lit
-- by nutrients on their way up. Any key, click or tap goes on to the levels.
flair.title = {}

function flair.title.open()
    S.menu, flair.title.t0 = "title", flair.now()
    S.mode, S.drag, S.selected = "grow", nil, nil
end

function flair.title.leave()
    sound("select")
    openMenu()
end

-- The threads under the sprout, grown once for a screen size: each a list of
-- pixels { x, y, d }, d how far it is along the network from the sprout.
function flair.title.grow(cx, gy)
    local rng = love.math.newRandomGenerator(7)
    local threads = {}
    local function thread(x, y, a, d, len, depth)
        local t = {}
        threads[#threads + 1] = t
        for _ = 1, len do
            a = a + (rng:random() - 0.5) * 0.5
            -- Down, never back up through the ground.
            a = max(0.15, min(math.pi - 0.15, a))
            x, y, d = x + math.cos(a), y + math.sin(a) * 0.7, d + 1
            if y >= S.vh - 1 or x < 0 or x >= S.vw then break end
            t[#t + 1] = { x = floor(x), y = floor(y), d = d }
            if depth < 3 and rng:random() < 0.035 then
                thread(x, y, a + (rng:random() < 0.5 and -1 or 1) * (0.5 + rng:random() * 0.6), d,
                    floor(len * (0.4 + rng:random() * 0.3)), depth + 1)
            end
        end
    end
    local reach = max(S.vw, S.vh)
    for k = 0, 6 do
        thread(cx, gy + 1, 0.3 + k * (math.pi - 0.6) / 6, 0, floor(reach * (0.3 + rng:random() * 0.25)), 0)
    end
    return threads
end

function flair.title.draw()
    local T0 = flair.title
    local age = flair.now() - (T0.t0 or 0)
    local cx, gy = floor(S.vw / 2), floor(S.vh * 0.6)
    if T0.w ~= S.vw or T0.h ~= S.vh then T0.w, T0.h, T0.threads = S.vw, S.vh, T0.grow(cx, gy) end
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    -- A few stars, each blinking on its own beat.
    local rng = love.math.newRandomGenerator(3)
    for _ = 1, floor(S.vw * gy / 900) do
        local x, y, beat = rng:random(0, S.vw - 1), rng:random(0, gy - 4), rng:random() * 6
        if (age + beat) % 6 > 0.4 then
            color(rng:random() < 0.3 and "s" or "k")
            love.graphics.rectangle("fill", x, y, 1, 1)
        end
    end
    -- The ground: a lip of lit soil, then deep soil to the bottom.
    color("u")
    love.graphics.rectangle("fill", 0, gy, S.vw, S.vh - gy)
    color("n")
    love.graphics.rectangle("fill", 0, gy, S.vw, 2)
    color("m")
    love.graphics.rectangle("fill", 0, gy - 1, S.vw, 1)
    -- The network, reaching further every frame for its first few seconds, and
    -- nutrients running up it toward the sprout.
    local reach = age * 45
    for _, t in ipairs(T0.threads) do
        for _, p in ipairs(t) do
            if p.d > reach then break end
            local lit = (p.d + age * 30) % 48 < 2
            color(lit and "l" or (p.d > reach - 3 and "l" or "c"))
            love.graphics.rectangle("fill", p.x, p.y, 1, 1)
        end
    end
    blit(M.sprout(0), cx, gy)
    -- The name, as big as the screen's width allows, on a teal shadow.
    local name = "MYCELIO TD"
    local s = max(1, min(5, floor((S.vw - 24) / Font.width(name))))
    local x, y = floor((S.vw - Font.width(name) * s) / 2), max(S.inset.t + 8, floor(gy * 0.3) - 3 * s)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(s, s)
    color("c")
    Font.print(name, 0, 1)
    color("l")
    Font.print(name, 0, 0)
    love.graphics.pop()
    local sub = "A TOWER DEFENSE UNDER A SPROUT"
    text(sub, floor((S.vw - Font.width(sub)) / 2), y + 6 * s + 6, "t")
    if age % 1.2 < 0.8 then
        centred(say("PRESS ANY KEY", "TAP TO BEGIN"), S.vh - S.inset.b - 14, "w", "o")
    end
end

-- The Spore Bank after a first win: the species it put up for sale, and BUY.
function bank.draw()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local L = bank.layout()
    local t = D.TOWER[bank.offer.kind]
    centred("THE SPORE BANK", L.top, "g", "o", L.mid)
    centred(S.level.name .. " WON: A NEW SPECIES FOR SALE", L.top + 11, "t", "o", L.mid)
    local c = L.card
    box(c.x, c.y, c.w, c.h, "u", bank.offer.bought and "g" or "t")
    local pic = icon(t.id, nil, 0, (flair.now() * 0.7) % 1)
    love.graphics.setScissor(c.x, c.y, 24, c.h)
    blit(pic, c.x + 12, t.id == "mat" and c.y + c.h - 8 or c.y + c.h - 6)
    love.graphics.setScissor()
    text(t.name, c.x + 26, c.y + 4, "w")
    text(t.role, c.x + 26, c.y + 12, "t")
    love.graphics.setScissor(c.x, c.y, c.w, c.h - 2)
    wrap(t.about, c.x + 26, c.y + 21, c.w - 30, "s")
    love.graphics.setScissor()
    local y = c.y + c.h + 6
    if bank.offer.bought then
        centred(t.name .. " IS YOURS. BRING IT FROM THE LOADOUT", y, "g", "o", L.mid)
    else
        local can = Profile.spores >= t.price
        centred("PRICE " .. t.price .. " SPORES   YOU HAVE " .. Profile.spores, y, can and "w" or "r", "o", L.mid)
        local b = L.buy
        box(b.x, b.y, b.w, b.h, S.hover.buy and "n" or (can and "d" or "u"), can and "t" or "k")
        local s = say("B: BUY IT", "BUY IT")
        text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 5, can and "t" or "k")
        centred(can and "OR BUY IT LATER, BEFORE ANY LEVEL" or "NOT ENOUGH YET: IT WAITS IN THE LOADOUT",
            b.y + b.h + 6, "s", "o", L.mid)
    end
    local b = L.on
    box(b.x, b.y, b.w, b.h, S.hover.on and "n" or "u", "c")
    local s = bank.offer.bought and say("ENTER: ON", "ON") or say("ENTER: LATER", "LATER")
    text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 5, "w")
end

--- the encyclopedia ---------------------------------------------------------------------

-- Every enemy met, every species grown and every seed had, each with its model
-- painted big and all there is to know about it; one not found yet is a dark
-- cutout. Opened from the level picker's top left corner. A page footnotes
-- every status it names (D.GLOSSARY), and the last tab is the glossary itself.
codex.TABS = {
    { id = "enemies", name = "ENEMIES" },
    { id = "species", name = "SPECIES" },
    { id = "seeds", name = "SEEDS" },
    { id = "words", name = "STATUSES" },
}
-- The tab open, how far each tab's grid is scrolled, the entry whose page is
-- open (its place in the tab's list) and how far that page is scrolled.
codex.tab, codex.scroll, codex.page, codex.pageScroll = 1, { 0, 0, 0, 0 }, nil, 0
-- The way a model faces in its tile: a little to the right of towards you.
codex.FACE = 0.35
codex.TW, codex.TH = 60, 62

-- Its tables, made once at load (in a function: the main chunk is out of locals).
function codex.init()
    codex.ids = { enemies = D.ENEMY_ORDER, species = {}, seeds = {} }
    for _, t in ipairs(D.TOWERS) do codex.ids.species[#codex.ids.species + 1] = t.id end
    for _, sd in ipairs(D.SEEDS) do codex.ids.seeds[#codex.ids.seeds + 1] = sd.id end
    -- A centipede's segments are enemies of their own: met, they are the centipede.
    codex.whole = {}
    for kind, d in pairs(D.ENEMIES) do if d.seg then codex.whole[d.seg] = kind end end
    -- Every glossary word's forms, longest first (CUT OFF before CUT), and the
    -- phrases that only look like one.
    codex.forms, codex.skips = {}, {}
    for n, g in ipairs(D.GLOSSARY) do
        for _, f in ipairs(g.forms) do codex.forms[#codex.forms + 1] = { f, n } end
        for _, sk in ipairs(g.skip or {}) do codex.skips[#codex.skips + 1] = sk end
    end
    table.sort(codex.forms, function(a, b) return #a[1] > #b[1] end)
end
-- Whatever is out on the board now has been met.
function codex.watch(g)
    local new = false
    for _, e in ipairs(g.enemies) do
        local k = codex.whole[e.kind] or e.kind
        if not e.hidden and not Profile.seen[k] then Profile.seen[k], new = true, true end
    end
    if new then Profile.save() end
end

function codex.list(tab) return codex.ids[codex.TABS[tab].id] end

function codex.found(tab, id)
    local t = codex.TABS[tab].id
    if t == "enemies" then return Profile.seen[id] == true end
    if t == "species" then return Profile.owns(id) end
    return Profile.ownsSeed(id)
end

function codex.name(tab, id)
    local t = codex.TABS[tab].id
    if t == "enemies" then return D.ENEMIES[id].name end
    if t == "species" then return D.TOWER[id].name end
    return D.SEED[id].name
end

-- How many of the three lists are found, and of how many.
function codex.count()
    local n, all = 0, 0
    for tab = 1, 3 do
        for _, id in ipairs(codex.list(tab)) do
            all = all + 1
            if codex.found(tab, id) then n = n + 1 end
        end
    end
    return n, all
end

-- Each enemy's model by heading and leg, as the board draws it walking.
codex.POSE = {
    ant = M.ant, gnat = M.gnat, moth = M.moth, slug = M.slug, spider = M.spider, knight = M.knight,
    springtail = M.springtail, queen = M.queen, stag = M.stag, waterbug = M.waterbug, click = M.click,
    bombardier = M.bombardier, mole = M.mole, centipede = M.centipede,
    pillbug = function(h) return M.pillbug(h, false) end,
    mite = function(h) return M.mite(h) end,
    brine = function(_, leg) return M.brine(leg) end,
    cricket = function(h, leg) return M.mole(h, leg, false, 1.35) end,
    centi = function(h, leg) return M.centipede(h, leg, 0.9) end,
    -- It walks backwards, pushing its ball.
    dung = function(h, leg) return M.dung(h + math.pi, leg) end,
}

-- An entry's model as layers { picture, i, j, depth } about its foot, painted
-- `s` times its size on the board, facing `h`, `a` (0..1) through its walk or
-- breath. A centipede brings some of its train, the dung beetle its ball and
-- the mites are a swarm.
function codex.figure(tab, id, s, h, a)
    local t = codex.TABS[tab].id
    if t == "species" then return { { M.scaled(s, M.tower, id, nil, 0, a), 0, 0, 0 } } end
    if t == "seeds" then return { { M.scaled(s, M.sprout, 0, id), 0, 0, 0 } } end
    local leg = floor(a * 4) % 2
    local layers = {}
    -- `back` room units behind it and `side` to its left.
    local function at(pic, back, side)
        local c, sn = math.cos(h), math.sin(h)
        local i, j, d = T.project((-back * c - side * sn) * s, 0, (-back * sn + side * c) * s)
        layers[#layers + 1] = { pic, floor(i + 0.5), floor(j + 0.5), d }
    end
    at(M.scaled(s, codex.POSE[id], h, leg), 0, 0)
    if id == "centi" or id == "centipede" then
        local d = D.ENEMIES[id]
        for k = 1, 3 do at(M.scaled(s, M.centseg, h, (leg + k) % 2, id == "centi" and 0.85 or nil), d.gap * k, 0) end
    elseif id == "dung" then
        at(M.scaled(s, M.ball, h, 0, false), -D.ENEMIES.dung.ballAhead, 0)
    elseif id == "mite" then
        at(M.scaled(s, M.mite, h + 0.9), 4, 4)
        at(M.scaled(s, M.mite, h - 0.6), 5, -4)
    end
    table.sort(layers, function(p, q) return p[4] < q[4] end)
    return layers
end

-- How big an entry's model is painted to fill a w x h box (no more than
-- `most` times its board size), and where its middle is then. `spin`: it goes
-- round, so it must fit facing any way.
codex.fits = {}
function codex.fit(tab, id, w, h, most, spin)
    local key = tab .. id .. ":" .. w .. "x" .. h .. ":" .. most .. (spin and "s" or "")
    local f = codex.fits[key]
    if f then return f end
    local i0, j0, i1, j1 = math.huge, math.huge, -math.huge, -math.huge
    for q = 0, spin and 7 or 0 do
        for _, l in ipairs(codex.figure(tab, id, 1, codex.FACE + q * math.pi / 4, 0)) do
            local pic = l[1]
            i0, j0 = min(i0, l[2] - pic.oi), min(j0, l[3] - pic.oj)
            i1, j1 = max(i1, l[2] - pic.oi + pic.w), max(j1, l[3] - pic.oj + pic.h)
        end
    end
    local s = min(most, w / (i1 - i0), h / (j1 - j0))
    -- In quarter steps, so a handful of sizes are ever painted.
    s = max(0.5, floor(s * 4) / 4)
    f = { s = s, ci = (i0 + i1) / 2 * s, cj = (j0 + j1) / 2 * s }
    codex.fits[key] = f
    return f
end

-- The model in the middle of a box, kept inside it.
function codex.drawFigure(tab, id, x, y, w, h, most, spin, heading, a, dark)
    local f = codex.fit(tab, id, w - 2, h - 2, most, spin)
    local px, py = floor(x + w / 2 - f.ci), floor(y + h / 2 - f.cj)
    local sx, sy, sw, sh = love.graphics.getScissor()
    love.graphics.intersectScissor(x, y, w, h)
    for _, l in ipairs(codex.figure(tab, id, f.s, heading, a)) do
        blit(l[1], px + l[2], py + l[3], dark and CUT or nil)
    end
    love.graphics.setScissor(sx, sy, sw, sh)
end

-- `str` with every glossary word in it footnoted, "STUNNED(2)": numbered in
-- the order the page first meets them, kept in `notes` ({ list, at }). What is
-- matched is held out of the string meanwhile, so nothing is matched twice.
function codex.footnote(str, notes)
    local held = {}
    local function hold(s)
        held[#held + 1] = s
        return "\1" .. #held .. "\2"
    end
    local function plain(s) return (s:gsub("%p", "%%%0")) end
    for _, s in ipairs(codex.skips) do str = str:gsub(plain(s), hold) end
    for _, f in ipairs(codex.forms) do
        str = str:gsub("%f[%w]" .. plain(f[1]) .. "%f[^%w]", function(m) return hold("\3" .. f[2] .. "\4" .. m) end)
    end
    return (str:gsub("\1(%d+)\2", function(k)
        local s = held[tonumber(k)]
        local e, m = s:match("^\3(%d+)\4(.*)$")
        if not e then return s end
        e = tonumber(e)
        if not notes.at[e] then
            notes.list[#notes.list + 1] = e
            notes.at[e] = #notes.list
        end
        return m .. "(" .. notes.at[e] .. ")"
    end))
end

-- Where an entry not found yet is found.
function codex.where(tab, id)
    local t = codex.TABS[tab].id
    if t == "enemies" then
        for _, l in ipairs(D.LEVELS) do
            for _, w in ipairs(l.waves) do
                for _, g in ipairs(w) do if g[1] == id then return "IT COMES ON " .. l.name end end
            end
        end
        return "IT COMES IN CHALLENGE MODE, ON ANY LEVEL"
    elseif t == "species" then
        local d = D.TOWER[id]
        if Profile.forSale(id) then return "FOR SALE IN THE LOADOUT: " .. d.price .. " SPORES" end
        return "WIN " .. Profile.prizeOf(id).name .. " TO PUT IT UP FOR SALE, THEN BUY IT WITH SPORES"
    end
    local sd = D.SEED[id]
    if Profile.seedForSale(id) then return "FOR SALE IN THE LOADOUT: " .. sd.price .. " SPORES" end
    return "WIN " .. D.LEVEL[sd.after].name .. " TO PUT IT UP FOR SALE, THEN BUY IT WITH SPORES"
end

-- A page's lines, `w` wide, each { s, k, x, h } as the info panel's, or
-- { icon } for an upgrade's picture beside the lines after it. The notes for
-- every glossary word on it come last.
codex.pages = {}
function codex.lines(tab, id, w)
    local found = codex.found(tab, id)
    local key = tab .. id .. ":" .. w .. (found and "f" or "") .. Profile.spores
    if codex.pages[key] then return codex.pages[key] end
    local out, notes = {}, { list = {}, at = {} }
    local function add(str, k, x, h)
        x = x or 0
        for _, l in ipairs(wrapLines(str, w - x)) do out[#out + 1] = { s = l, k = k, x = x, h = h or 7 } end
    end
    local function note(str, k, x) add(codex.footnote(str, notes), k, x) end
    local function gap(h) out[#out + 1] = { h = h } end
    local function head(str) gap(4); add(str, "t") end
    local function names(list, of)
        local s = {}
        for _, n in ipairs(list) do s[#s + 1] = of(n) end
        return table.concat(s, ", ")
    end

    local t = codex.TABS[tab].id
    add(found and codex.name(tab, id) or "???", found and "g" or "k", 0, 9)
    if not found then
        add(t == "enemies" and "NOT MET YET" or (t == "species" and "NOT GROWN YET" or "NOT PLANTED YET"), "r")
        gap(3)
        add(codex.where(tab, id), "s")
    elseif t == "enemies" then
        local d = D.ENEMIES[id]
        note(d.boss and "BOSS" or (d.fly and "FLIER" or "WALKER"), d.boss and "r" or "t")
        gap(3)
        note(d.about, "w")
        head("NUMBERS")
        local parts = { "HP " .. number(d.hp), "SPEED " .. number(d.speed), "ARMOR " .. number(d.armor) }
        if d.swarm then parts[#parts + 1] = d.swarm .. " TO A SWARM" end
        add(table.concat(parts, "  "), "l")
        add("HITS THE SPROUT FOR " .. number(d.heart) .. "  CORPSE WORTH " .. number(d.corpse), "l")
        local met = {}
        for _, l in ipairs(D.LEVELS) do
            local here = false
            for _, wave in ipairs(l.waves) do for _, g in ipairs(wave) do if g[1] == id then here = true end end end
            if here then met[#met + 1] = l.name end
        end
        for _, g in ipairs(D.CHALLENGE) do if g[1] == id then met[#met + 1] = "CHALLENGE MODE" end end
        head("COMES ON")
        add(#met > 0 and table.concat(met, ", ") or "NOWHERE YET", "w")
        if D.COUNTERS[id] then
            head("ANSWERED BY")
            add(names(D.COUNTERS[id], function(k) return D.TOWER[k].name end), "w")
        end
    elseif t == "species" then
        local d = D.TOWER[id]
        local at = (d.unlock or 0) > 0 and ("   FROM WAVE " .. d.unlock) or ""
        add(d.role .. "   COST " .. d.cost .. at, "t")
        gap(3)
        note(d.blurb, "w")
        gap(3)
        note(d.about, "s")
        head("NUMBERS")
        local parts = {}
        if d.damage then parts[#parts + 1] = "DAMAGE " .. number(d.damage) end
        if d.every then parts[#parts + 1] = "EVERY " .. number(d.every) .. "S" end
        if d.range then parts[#parts + 1] = "RANGE " .. number(d.range) end
        if d.splash then parts[#parts + 1] = "SPLASH " .. number(d.splash) end
        if d.slow then parts[#parts + 1] = "SLOW " .. floor((1 - d.slow) * 100 + 0.5) .. "%" end
        if d.hp then parts[#parts + 1] = "HP " .. d.hp end
        if d.reserve then parts[#parts + 1] = "RESERVE " .. number(d.reserve) end
        add(table.concat(parts, "  "), "l")
        -- What it answers, of the enemies met; the rest only counted.
        local good, unmet = {}, 0
        for _, kind in ipairs(D.ENEMY_ORDER) do
            for _, k in ipairs(D.COUNTERS[kind] or {}) do
                if k == id and Profile.seen[kind] then good[#good + 1] = D.ENEMIES[kind].name
                elseif k == id then unmet = unmet + 1 end
            end
        end
        if unmet > 0 then good[#good + 1] = unmet .. (#good > 0 and " MORE" or "") .. " NOT MET YET" end
        if #good > 0 then head("GOOD AGAINST"); add(table.concat(good, ", "), "w") end
        head("UPGRADES")
        for b = 1, 2 do
            if b == 2 then add("OR", "s") end
            for tier = 1, 2 do
                local row = d.up[b][tier]
                local from = #out
                out[#out + 1] = { icon = { id, b, tier }, h = 0 }
                add((tier == 1 and "I  " or "II ") .. row.name .. "  " .. row.cost, "w", 24)
                note(row.blurb, "s", 24)
                local h = 0
                for k = from + 1, #out do h = h + out[k].h end
                gap(max(2, 30 - h))
            end
        end
    else
        local sd = D.SEED[id]
        add("SEED   " .. (sd.price and ("PRICE " .. sd.price) or "FREE"), "t")
        gap(3)
        note(sd.blurb, "w")
        gap(3)
        note(sd.about, "s")
        head("ITS MUTATIONS")
        for _, m in ipairs(D.MUTATIONS) do
            if m.seed == id then
                add(m.name, "w")
                note(m.blurb, "s", 8)
            end
        end
    end
    if #notes.list > 0 then
        gap(6)
        add("NOTES", "t")
        for n, e in ipairs(notes.list) do
            local g = D.GLOSSARY[e]
            gap(1)
            add("(" .. n .. ") " .. g.name, "l")
            add(g.about, "s", 8)
        end
    end
    codex.pages[key] = out
    return out
end

-- The glossary tab: every word and what it means.
function codex.words(w)
    if codex.wordLines and codex.wordLines.w == w then return codex.wordLines end
    local out = { w = w }
    for _, g in ipairs(D.GLOSSARY) do
        out[#out + 1] = { s = g.name, k = "l", x = 0, h = 7 }
        for _, l in ipairs(wrapLines(g.about, w - 8)) do out[#out + 1] = { s = l, k = "s", x = 8, h = 7 } end
        out[#out + 1] = { h = 4 }
    end
    codex.wordLines = out
    return out
end

function codex.height(lines)
    local h = 0
    for _, l in ipairs(lines) do h = h + l.h end
    return h
end

-- The level picker's button for it, top left.
function codex.button() return { x = S.inset.l + 4, y = S.inset.t + 4, w = Font.width("ENCYCLOPEDIA") + 8, h = 12 } end

-- The grid: BACK, the tabs, and a tile an entry, as many across as fit,
-- scrolled under the tabs. `scroll` is kept in reach.
function codex.layout()
    local L = { back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 }, tabs = {} }
    local gap, total = 3, 0
    for k, tb in ipairs(codex.TABS) do
        L.tabs[k] = { w = Font.width(tb.name) + 8, h = 11, y = S.inset.t + 21, tab = k }
        total = total + L.tabs[k].w + (k > 1 and gap or 0)
    end
    local x = floor((S.vw - total) / 2)
    for _, c in ipairs(L.tabs) do c.x = x; x = x + c.w + gap end
    L.top, L.bottom = S.inset.t + 37, S.vh - S.inset.b - 3
    L.left, L.right = S.inset.l + 4, S.vw - S.inset.r - 4
    local view = L.bottom - L.top
    local content
    if codex.TABS[codex.tab].id == "words" then
        L.words = codex.words(L.right - L.left - 8)
        content = codex.height(L.words) + 8
    else
        local TW, TH = codex.TW, codex.TH
        local cols = max(2, floor((L.right - L.left + 4) / (TW + 4)))
        local list = codex.list(codex.tab)
        local x0 = floor((S.vw - (cols * TW + (cols - 1) * 4)) / 2)
        content = ceil(#list / cols) * (TH + 4) + 1
        L.tiles = {}
        for k = 1, #list do
            local col, row = (k - 1) % cols, floor((k - 1) / cols)
            L.tiles[k] = { x = x0 + col * (TW + 4), dy = row * (TH + 4), w = TW, h = TH, n = k, id = list[k] }
        end
    end
    L.most = max(0, content - view)
    codex.scroll[codex.tab] = max(0, min(L.most, codex.scroll[codex.tab]))
    for _, c in ipairs(L.tiles or {}) do c.y = L.top + 1 + c.dy - codex.scroll[codex.tab] end
    return L
end

-- An entry's page: BACK and the arrows to the ones either side of it, the
-- model on the left and the words on the right on a wide screen; on a narrow
-- one the model heads the words and goes up with them.
function codex.pageLayout()
    local P = { back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 } }
    P.next = { x = S.vw - S.inset.r - 4 - 16, y = S.inset.t + 4, w = 16, h = 12, step = 1 }
    P.prev = { x = P.next.x - 19, y = S.inset.t + 4, w = 16, h = 12, step = -1 }
    local top, bottom = S.inset.t + 21, S.vh - S.inset.b - 3
    if wide() then
        local mw = min(170, floor((S.vw - S.inset.l - S.inset.r) * 0.42))
        P.model = { x = S.inset.l + 4, y = top, w = mw, h = bottom - top }
        P.text = { x = P.model.x + mw + 5, y = top, h = bottom - top }
        P.text.w = S.vw - S.inset.r - 4 - P.text.x
    else
        P.text = { x = S.inset.l + 4, y = top, w = S.vw - S.inset.l - S.inset.r - 8, h = bottom - top }
        P.model = { w = P.text.w - 4, h = min(130, floor(S.vh * 0.3)), inline = true }
    end
    P.id = codex.list(codex.tab)[codex.page]
    P.lines = codex.lines(codex.tab, P.id, P.text.w - 8)
    local content = codex.height(P.lines) + 8 + (P.model.inline and P.model.h + 4 or 0)
    P.most = max(0, content - P.text.h)
    codex.pageScroll = max(0, min(P.most, codex.pageScroll))
    return P
end

function codex.open()
    S.menu = "codex"
    codex.page = nil
    sound("panel")
end

function codex.back()
    sound("back")
    if codex.page then codex.page = nil else openMenu() end
end

-- To the entry `d` along from the one open, round the ends.
function codex.step(d)
    local n = #codex.list(codex.tab)
    codex.page = (codex.page - 1 + d) % n + 1
    codex.pageScroll = 0
    sound("select")
end

function codex.toTab(k)
    if codex.tab == k and not codex.page then return end
    codex.tab, codex.page = k, nil
    sound("select")
end

-- What is pointed at: hover.cback, hover.ctab (a tab), hover.ctile (an entry)
-- or hover.cstep (an arrow, -1 or 1).
function codex.findHover(mx, my)
    if codex.page then
        local P = codex.pageLayout()
        if inside(mx, my, P.back.x, P.back.y, P.back.w, P.back.h) then S.hover.cback = true end
        for _, b in ipairs({ P.prev, P.next }) do
            if inside(mx, my, b.x, b.y, b.w, b.h) then S.hover.cstep = b.step end
        end
        return
    end
    local L = codex.layout()
    if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then S.hover.cback = true return end
    for k, c in ipairs(L.tabs) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.ctab = k return end
    end
    if my < L.top or my >= L.bottom then return end
    for _, c in ipairs(L.tiles or {}) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.ctile = c.n return end
    end
end

-- The box of whatever is pointed at, to light up when it is pressed.
function codex.under()
    if S.hover.cback then return function() local b = codex.layout().back return b.x, b.y, b.w, b.h end end
    if S.hover.cstep then
        local d = S.hover.cstep
        return function()
            local P = codex.pageLayout()
            local b = d < 0 and P.prev or P.next
            return b.x, b.y, b.w, b.h
        end
    end
    if S.hover.ctab then
        local k = S.hover.ctab
        return function() local c = codex.layout().tabs[k] return c.x, c.y, c.w, c.h end
    end
end

function codex.click(b)
    if b == 2 or S.hover.cback then codex.back()
    elseif S.hover.ctab then codex.toTab(S.hover.ctab)
    elseif S.hover.cstep then codex.step(S.hover.cstep)
    elseif S.hover.ctile then
        codex.page, codex.pageScroll = S.hover.ctile, 0
        sound("panel")
    end
end

function codex.key(key)
    if key == "escape" or key == "backspace" then codex.back() return end
    if codex.page then
        if key == "left" or key == "a" then codex.step(-1)
        elseif key == "right" or key == "d" then codex.step(1) end
    else
        local n = tonumber(key)
        if n and codex.TABS[n] then codex.toTab(n) end
        if key == "left" or key == "a" then codex.toTab((codex.tab - 2) % #codex.TABS + 1)
        elseif key == "right" or key == "d" then codex.toTab(codex.tab % #codex.TABS + 1) end
    end
    if key == "up" or key == "w" then codex.scrollBy(-21) end
    if key == "down" or key == "s" then codex.scrollBy(21) end
    if key == "pageup" then codex.scrollBy(-floor(S.vh * 0.7)) end
    if key == "pagedown" or key == "space" then codex.scrollBy(floor(S.vh * 0.7)) end
end

-- Scrolling: whichever is open, the page or the grid. Each draw keeps it in reach.
function codex.getScroll() return codex.page and codex.pageScroll or codex.scroll[codex.tab] end
function codex.setScroll(v)
    if codex.page then codex.pageScroll = max(0, v) else codex.scroll[codex.tab] = max(0, v) end
end
function codex.scrollBy(d) codex.setScroll(codex.getScroll() + d) end

-- A button with its word in the middle.
function codex.btn(b, s, on, edge, k)
    box(b.x, b.y, b.w, b.h, on and "n" or "u", edge)
    text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + floor((b.h - 5) / 2), k or "w")
end

-- How far down a scrolled box is, as a thumb in its right edge.
function codex.thumb(x, y, h, at, most)
    if most <= 0 then return end
    local th = max(6, floor(h * h / (h + most)))
    color("k")
    love.graphics.rectangle("fill", x, y, 1, h)
    color("t")
    love.graphics.rectangle("fill", x, y + floor((h - th) * at / most), 1, th)
end

function codex.drawLines(lines, x, y)
    for _, l in ipairs(lines) do
        if l.s then text(l.s, x + l.x, y, l.k) end
        y = y + l.h
    end
end

function codex.draw()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local clock = flair.now()
    local n, all = codex.count()
    centred("ENCYCLOPEDIA", S.inset.t + 7, "g", "o")
    local found = "FOUND " .. n .. "/" .. all
    if codex.page then
        local P = codex.pageLayout()
        codex.btn(P.back, "BACK", S.hover.cback, S.hover.cback and "t" or "k")
        codex.btn(P.prev, "<", S.hover.cstep == -1, S.hover.cstep == -1 and "t" or "k")
        codex.btn(P.next, ">", S.hover.cstep == 1, S.hover.cstep == 1 and "t" or "k")
        local where = codex.page .. "/" .. #codex.list(codex.tab)
        text(where, P.prev.x - Font.width(where) - 4, P.prev.y + 3, "s")
        codex.drawPage(P, clock)
        return
    end
    local L = codex.layout()
    codex.btn(L.back, "BACK", S.hover.cback, S.hover.cback and "t" or "k")
    text(found, S.vw - S.inset.r - 4 - Font.width(found), S.inset.t + 7, "t")
    for k, c in ipairs(L.tabs) do
        local on = codex.tab == k
        codex.btn(c, codex.TABS[k].name, S.hover.ctab == k or on, on and "g" or (S.hover.ctab == k and "t" or "k"), on and "g" or "w")
    end
    love.graphics.setScissor(0, L.top, S.vw, L.bottom - L.top)
    local sc = codex.scroll[codex.tab]
    if L.words then
        box(L.left, L.top - sc, L.right - L.left, codex.height(L.words) + 8, "u", "c")
        codex.drawLines(L.words, L.left + 4, L.top + 4 - sc)
    else
        for _, c in ipairs(L.tiles) do
            if c.y + c.h > L.top and c.y < L.bottom then
                local own = codex.found(codex.tab, c.id)
                local on = S.hover.ctile == c.n
                local boss = codex.TABS[codex.tab].id == "enemies" and D.ENEMIES[c.id].boss
                box(c.x, c.y, c.w, c.h, on and "n" or "u", on and "w" or (own and (boss and "r" or "c") or "k"))
                -- Pointed at, it walks or breathes; the rest hold still.
                local name = own and codex.name(codex.tab, c.id) or "???"
                local lines = wrapLines(name, c.w - 4)
                codex.drawFigure(codex.tab, c.id, c.x, c.y + 1, c.w, c.h - 3 - 7 * #lines, 3, false, codex.FACE,
                    (own and on) and (clock * 0.7) % 1 or 0, not own)
                local y = c.y + c.h - 1 - 7 * #lines
                for _, l in ipairs(lines) do
                    text(l, c.x + floor((c.w - Font.width(l)) / 2), y, own and (boss and "r" or "w") or "k")
                    y = y + 7
                end
            end
        end
    end
    love.graphics.setScissor()
    codex.thumb(S.vw - S.inset.r - 2, L.top, L.bottom - L.top, sc, L.most)
end

function codex.drawPage(P, clock)
    local tab, id = codex.tab, P.id
    local own = codex.found(tab, id)
    local enemy = codex.TABS[tab].id == "enemies"
    -- Found, an enemy turns slowly round and walks on the spot; a species breathes.
    local heading = (own and enemy) and (codex.FACE - clock * 0.5) or codex.FACE
    local a = own and (enemy and clock * 1.2 or clock * 0.7) % 1 or 0
    local most = 4
    local B = P.text
    local sc = codex.pageScroll
    if not P.model.inline then
        local m = P.model
        box(m.x, m.y, m.w, m.h, "u", own and "c" or "k")
        codex.drawFigure(tab, id, m.x, m.y, m.w, m.h, most, enemy, heading, a, not own)
    end
    box(B.x, B.y, B.w, B.h, "u", "c")
    love.graphics.setScissor(B.x, B.y, B.w, B.h)
    local y = B.y + 4 - sc
    if P.model.inline then
        codex.drawFigure(tab, id, B.x + 2, y, P.model.w, P.model.h, most, enemy, heading, a, not own)
        y = y + P.model.h + 4
    end
    for _, l in ipairs(P.lines) do
        if l.icon then
            local sx, sy, sw, sh = love.graphics.getScissor()
            love.graphics.intersectScissor(B.x + 4, y, 22, 30)
            local kind, b, tier = l.icon[1], l.icon[2], l.icon[3]
            blit(icon(kind, b, tier, (clock * 0.7) % 1), B.x + 15, kind == "mat" and y + 20 or y + 27)
            love.graphics.setScissor(sx, sy, sw, sh)
        elseif l.s then
            text(l.s, B.x + 4 + l.x, y, l.k)
        end
        y = y + l.h
    end
    love.graphics.setScissor()
    codex.thumb(B.x + B.w - 2, B.y + 1, B.h - 2, sc, P.most)
end

function love.draw()
    -- The HUD's picture starts empty each frame (nothing where the board shows
    -- through) and everything on it is drawn solid, so laying it over the board
    -- covers a pixel fully or not at all.
    love.graphics.setCanvas(S.ui)
    love.graphics.clear(0, 0, 0, 0)
    if S.painter then
        flair.loading()
    elseif S.menu == "loadout" then
        drawLoadout()
    elseif S.menu == "bank" then
        bank.draw()
    elseif S.menu == "codex" then
        codex.draw()
    elseif S.menu == "title" then
        flair.title.draw()
    elseif S.menu then
        drawMenu()
    else
        drawHud()
        love.graphics.setCanvas(S.canvas)
        drawBoard()
    end
    love.graphics.setCanvas(S.ui)
    flair.draw()
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    if S.painter or S.menu then
        -- Nothing to stretch: the loading bar or the picker is the whole screen.
    elseif S.turning and not (S.pinch and not S.pinch.done) then
        -- Going round: the frame that was left turns half way, then the new
        -- one comes in from the other half, the ground unsquashed for the turn
        -- (so a square stays a square going round) and the whole board lifting
        -- a little off the table and back.
        love.graphics.clear(unpack(T.RGB[IDX.o]))
        local f = S.turning.t / TURN_TIME
        local e = f * f * (3 - 2 * f)
        local a, pic
        if e < 0.5 then a, pic = S.turning.angle * e, S.turning.old
        else a, pic = -S.turning.angle * (1 - e), S.canvas end
        local lift = 1 - 0.06 * math.sin(math.pi * e)
        love.graphics.push()
        love.graphics.scale(S.zoom, S.zoom)
        love.graphics.translate(S.turning.px, S.turning.py)
        love.graphics.scale(lift, lift * 0.5)
        love.graphics.rotate(a)
        love.graphics.scale(1, 2)
        love.graphics.translate(-S.turning.px, -S.turning.py)
        love.graphics.draw(pic, 0, 0)
        love.graphics.pop()
    elseif S.pinch and not S.pinch.done then
        -- Mid-pinch: the frame stretched about where the fingers started and
        -- moved to where they are (see love.touchpressed).
        love.graphics.clear(unpack(T.RGB[IDX.o]))
        local z = S.zoom * S.pinch.s
        love.graphics.draw(S.canvas, S.pinch.x - (S.pinch.x0 + S.pad.l * S.zoom) * S.pinch.s,
            S.pinch.y - (S.pinch.y0 + S.pad.t * S.zoom) * S.pinch.s, 0, z, z)
    else
        love.graphics.draw(S.canvas, -S.pad.l * S.zoom, -S.pad.t * S.zoom, 0, S.zoom, S.zoom)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(S.ui, 0, 0, 0, S.uz, S.uz)
end
