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
-- This file starts the game, runs each frame and lays the two pictures on
-- the window. The screen's parts are in src/ui/ (what they share is
-- src/ui/state.lua), the rules in src/game.lua and the numbers in src/defs.lua.

local T = require "src.tracer"
local World = require "src.world"
local D = require "src.defs"
local Sfx = require "src.sfx"
local Profile = require "src.profile"
local S = require "src.ui.state"
local flair = require "src.ui.flair"
local Toolbar = require "src.ui.toolbar"
local View = require "src.ui.view"
local Board = require "src.ui.board"
local codex = require "src.ui.codex"
local Title = require "src.ui.title"
local audio = require "src.ui.audio"
local Run = require "src.ui.run"
local Loadout = require "src.ui.loadout"
local Hud = require "src.ui.hud"
local Input = require "src.ui.input"
local Slide = require "src.ui.slide"

local floor, min, max = math.floor, math.min, math.max
local IDX = T.IDX
local BUTTONS, buttonRect = Toolbar.BUTTONS, Toolbar.buttonRect
local fit = View.fit
local TURN_TIME = S.TURN_TIME

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

-- The pointer, fingers and keys: src/ui/input.lua.
for _, name in ipairs({ "mousepressed", "mousereleased", "mousemoved", "wheelmoved",
    "touchpressed", "touchmoved", "touchreleased", "keypressed" }) do
    love[name] = Input[name]
end

function love.resize() fit() end
function love.displayrotated() fit() end

-- Sent to the background (a call, the home button, the phone locked): stop
-- the clock rather than let a wave run on unwatched, and the sound with it,
-- until the game is back in front.
function love.focus(f)
    if not f and not S.script and S.game then S.paused = true end
    audio.shown.focus = f
    Sfx.hide(not (audio.shown.focus and audio.shown.visible))
end
function love.visible(v)
    audio.shown.visible = v
    Sfx.hide(not (audio.shown.focus and audio.shown.visible))
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    setWindowIcon()
    fit()
    Profile.load()
    codex.init()
    for n, a in ipairs(args or {}) do
        -- For testing the network: `--spores 100000` puts that many in the bank.
        if a == "--spores" and tonumber(args[n + 1]) then
            Profile.spores = tonumber(args[n + 1])
            Profile.save()
        end
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
        Run.play(n)
    else
        Title.open()
    end
end

function love.update(dt)
    -- The script runs on its own clock, the HUD's flourishes too.
    if S.script then dt = 1 / 30 end
    Sfx.warm(0.004)
    audio.ambience(dt)
    flair.update(dt)
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
            Run.start()
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
                    menu = function(on) if on then S.openMenu() else S.menu = nil end end,
                    loadout = function(n) if n then Loadout.open(n) else S.menu, S.pick = nil, nil end end,
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
        Input.findHover()
        audio.hover()
        if S.menu == "title" or S.menu == "home" or S.menu == "settings" then Title.sounds() end
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
    View.update(dt)
    flair.sky.update(S.game.weather or false, dt)
    if S.script then S.script.update(S.game, dt) end
    Input.findHover()
    audio.hover()
    Run.update(dt)
    if S.script then photograph() end
end

function love.draw()
    -- The HUD's picture starts empty each frame (nothing where the board shows
    -- through) and everything on it is drawn solid, so laying it over the board
    -- covers a pixel fully or not at all. The screen up is drawn on a picture
    -- of its own and laid on it, so it can slide in as the last one slides
    -- out (src/ui/slide.lua); its backdrop goes straight onto it, under,
    -- when that stays put.
    Slide.check()
    love.graphics.setCanvas(S.ui)
    love.graphics.clear(0, 0, 0, 0)
    local screen = S.menu and not S.painter and Input.screen()
    local backdrop = screen and screen.backdrop
    if backdrop and Slide.fixed() then backdrop() end
    love.graphics.setCanvas(Slide.front)
    love.graphics.clear(0, 0, 0, 0)
    if S.painter then
        flair.loading()
    elseif S.menu then
        if backdrop and not Slide.fixed() then backdrop() end
        screen.draw()
    else
        Hud.draw()
        love.graphics.setCanvas(S.canvas)
        Board.draw()
    end
    love.graphics.setCanvas(S.ui)
    Slide.compose()
    flair.draw()
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    if (S.painter or S.menu) and not Slide.showsBoard() then
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
