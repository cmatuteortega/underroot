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
-- what the mouse means. The rules are in src/game.lua and the numbers in
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

local canvas, vw, vh, zoom
local overlay, overlayImage, opx
local world, painter, progress = nil, nil, 0
local game
local camx, camy, panx, pany = 0, 0, 0, 0
local mode = "grow"
local drag -- the node a link is being pulled from
local hover = {}
local mouse = { x = 0, y = 0 }
local speed, paused = 1, false
local heartFlash = 0
local script -- the --shots run

--- the screen ----------------------------------------------------------------------

local function fit()
    local w, h = love.graphics.getDimensions()
    zoom = max(1, floor(min(w, h) / SHORT))
    vw, vh = ceil(w / zoom), ceil(h / zoom)
    canvas = love.graphics.newCanvas(vw, vh)
    canvas:setFilter("nearest", "nearest")
    -- The overlay is one byte-for-byte picture of everything laid over the board
    -- this frame: a pixel is either covered, fully, or not there. Painter's order
    -- is simply the order things are put.
    overlay = love.image.newImageData(vw, vh, "rgba8")
    opx = ffi.cast("uint8_t*", overlay:getFFIPointer())
    overlayImage = love.graphics.newImage(overlay)
    overlayImage:setFilter("nearest", "nearest")
end

function love.resize() fit() end

local RGB8 = {}
for k, c in ipairs(T.RGB) do RGB8[k] = { floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5) } end

-- Put key k at screen pixel (x, y).
local function putS(k, x, y)
    if k == 0 or x < 0 or y < 0 or x >= vw or y >= vh then return end
    local p = (y * vw + x) * 4
    local c = RGB8[k]
    opx[p], opx[p + 1], opx[p + 2], opx[p + 3] = c[1], c[2], c[3], 255
end
-- Put key k at board-image pixel (i, j).
local function put(k, i, j) putS(k, floor(i - floor(camx)), floor(j - floor(camy))) end

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

-- The same picture flat on the screen, for the toolbar.
local function blit(pic, x, y, remap)
    remap = remap or T.SAME
    for pj = 0, pic.h - 1 do
        for pi = 0, pic.w - 1 do
            local k = pic.key[pj * pic.w + pi]
            if k ~= 0 then
                love.graphics.setColor(T.RGB[remap[k]])
                love.graphics.rectangle("fill", x - pic.oi + pi, y - pic.oj + pj, 1, 1)
            end
        end
    end
end

-- A shadow straight down onto whatever faces up under (x, z): each pixel there
-- goes one step darker.
local function shadow(x, z, r)
    local i0 = floor(world:toImage(x - r, 0, z + r)) - 1
    local i1 = ceil(world:toImage(x + r, 0, z - r)) + 1
    local _, j0 = world:toImage(x - r, 4, z - r)
    local _, j1 = world:toImage(x + r, -1, z + r)
    for j = max(0, floor(j0)), min(world.h - 1, ceil(j1)) do
        for i = max(0, i0), min(world.w - 1, i1) do
            local n = j * world.w + i
            if world.up[n] == 1 and (world.wx[n] - x) ^ 2 + (world.wz[n] - z) ^ 2 <= r * r then
                put(T.DARKER[world.key[n]], i, j)
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
    camx = floor((world.w - vw) / 2) + panx
    camy = floor((world.h - (vh - TOP - BOTTOM)) / 2) - TOP + pany
end

-- The board-image pixel under the mouse.
local function cursor()
    return mouse.x + floor(camx), mouse.y + floor(camy)
end

--- what the mouse is over ------------------------------------------------------------

local BUTTONS = {
    { mode = "grow", key = "1", name = "GROW HYPHAE", blurb = "DRAG FROM A FED NODE TO A POCKET. COST GROWS WITH LENGTH" },
}
for _, t in ipairs(D.TOWERS) do
    BUTTONS[#BUTTONS + 1] = { mode = t.id, key = t.key, name = t.name, blurb = t.blurb, cost = t.cost }
end
BUTTONS[#BUTTONS + 1] = { mode = "prune", key = "X", name = "PRUNE", blurb = "CUT YOUR OWN LINK (HALF BACK) OR CLEAR A TOWER" }
BUTTONS[#BUTTONS + 1] = { mode = "pulse", key = "Q", name = "SPORE PULSE",
    blurb = "CLICK A FED NODE: EVERY TOWER ON THE WAY THERE OVERCHARGES" }

local BW, BH = 30, 27
local function buttonRect(n)
    local total = #BUTTONS * (BW + 2) - 2
    local x0 = floor((vw - total) / 2) - 26
    return x0 + (n - 1) * (BW + 2), vh - BH - 3, BW, BH
end
local function waveRect()
    local x = select(1, buttonRect(#BUTTONS)) + BW + 8
    return x, vh - BH - 3, 44, BH
end
local function inside(x, y, rx, ry, rw, rh) return x >= rx and y >= ry and x < rx + rw and y < ry + rh end

local function nodeScreen(n)
    local i, j = world:toImage(n.x, n.y + (n.heart and 10 or 5), n.z)
    return i, j
end

local function findHover()
    hover = {}
    local mx, my = mouse.x, mouse.y
    for n = 1, #BUTTONS do
        if inside(mx, my, buttonRect(n)) then hover.button = n return end
    end
    if inside(mx, my, waveRect()) then hover.wave = true return end
    if my < TOP then return end
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
    game = Game.new(world)
    mode, drag, panx, pany = "grow", nil, 0, 0
    paused, speed = false, 1
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    fit()
    world = World.new()
    painter = coroutine.create(function() world:paint() end)
    for _, a in ipairs(args or {}) do
        if a == "--shots" then script = require("src.script") end
    end
end

local function click(b)
    if b == 2 then
        mode, drag = "grow", nil
        return
    end
    if hover.button then
        mode, drag = BUTTONS[hover.button].mode, nil
        return
    end
    if hover.wave then
        if game.phase == "build" then game:startWave() else speed = speed % 3 + 1 end
        return
    end
    if game.phase == "won" or game.phase == "lost" then return end
    if mode == "grow" then
        if hover.node then
            if drag and drag ~= hover.node then
                game:grow(drag, hover.node)
                drag = nil
            else
                drag = hover.node
            end
        elseif hover.link and hover.link.state == "cut" then
            game:repair(hover.link)
        else
            drag = nil
        end
    elseif mode == "prune" then
        if hover.node and hover.node.tower then
            game:sell(hover.node)
        elseif hover.link then
            game:prune(hover.link)
        elseif hover.mat then
            game:liftMat(hover.mat)
        end
    elseif mode == "mat" then
        if hover.c then game:layMat(hover.c, hover.r) end
    elseif mode == "pulse" then
        if hover.node and game:pulse(hover.node) then mode = "grow" end
    else
        if hover.node then game:build(mode, hover.node) end
    end
end

function love.mousepressed(x, y, b)
    if painter then return end
    mouse.x, mouse.y = floor(x / zoom), floor(y / zoom)
    findHover()
    if b == 3 then mouse.pan = { x = mouse.x, y = mouse.y, px = panx, py = pany } return end
    click(b)
end

function love.mousereleased(x, y, b)
    if painter then return end
    if b == 3 then mouse.pan = nil return end
    mouse.x, mouse.y = floor(x / zoom), floor(y / zoom)
    findHover()
    -- Pulled from one node and let go over another: that is a link too.
    if b == 1 and mode == "grow" and drag and hover.node and hover.node ~= drag then
        game:grow(drag, hover.node)
        drag = nil
    end
end

function love.mousemoved(x, y)
    mouse.x, mouse.y = floor(x / zoom), floor(y / zoom)
    if mouse.pan then
        panx = mouse.pan.px - (mouse.x - mouse.pan.x)
        pany = mouse.pan.py - (mouse.y - mouse.pan.y)
    end
end

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen())
        fit()
        return
    end
    if painter then return end
    if key == "escape" then
        -- Never quits: one key too many and a run is gone. The window's close does that.
        if drag or mode ~= "grow" then mode, drag = "grow", nil else paused = not paused end
    end
    for _, b in ipairs(BUTTONS) do
        if key == b.key:lower() then mode, drag = b.mode, nil end
    end
    if key == "space" then
        if game.phase == "build" then game:startWave() end
    end
    if key == "f" then speed = speed % 3 + 1 end
    if key == "p" then paused = not paused end
    if key == "r" and (game.phase == "won" or game.phase == "lost" or love.keyboard.isDown("lshift")) then start() end
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
                    button = function(name)
                        for n, b in ipairs(BUTTONS) do
                            if b.mode == name then
                                local x, y, w, h = buttonRect(n)
                                return (x + w / 2) * zoom, (y + h / 2) * zoom
                            end
                        end
                    end,
                })
            end
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
    local lim = max(40, (world.w - vw) / 2 + 40)
    panx, pany = max(-lim, min(lim, panx)), max(-60, min(60, pany))
    centre()

    if script then script.update(game, dt) end
    findHover()
    if not paused then
        for _ = 1, speed do
            game:update(dt)
            if game.events.heart then heartFlash = 0.15 end
        end
    end
    heartFlash = max(0, heartFlash - dt)
    if script then script.after(game, canvas) end
end

--- drawing the world -------------------------------------------------------------------

local function linkY(l, f, x, z)
    local g = world:groundAt(x, z) + 0.4
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
    local hurt = l.state == "alive" and l.hp < D.LINK.hp * 0.5
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

local function towerPicture(t)
    if t.kind == "puffer" then return M.puffer(t.squash) end
    return M.tower(t.kind, game.clock)
end

local function remapFor(t)
    if t.hunger == "dormant" then return T.DARKER2 end
    if t.hunger == "starved" then return T.DARKER end
end

local function enemyPicture(e)
    if e.kind == "ant" then
        local rate = e.state == "chew" and 14 or 8
        return M.ant(e.h, floor(e.anim * rate) % 2)
    elseif e.kind == "pillbug" then
        if e.rolling then return M.pillbug(e.h, true, floor(e.anim * 12) % 4) end
        return M.pillbug(e.h, false)
    elseif e.kind == "mite" then
        return M.mite(e.h)
    end
    return M.brine(floor(e.anim * 4) % 2)
end

local SHADOW = { ant = 4, pillbug = 4.5, brine = 3.5 }

local function drawBoard()
    love.graphics.clear(unpack(T.RGB[IDX.o]))
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(world.image, -floor(camx), -floor(camy))
    ffi.fill(opx, vw * vh * 4, 0)

    -- On the ground first: shadows, mats, threads and rings.
    for _, e in ipairs(game.enemies) do
        if SHADOW[e.kind] then shadow(e.x, e.z, SHADOW[e.kind]) end
    end
    for _, m in ipairs(game.mats) do
        local fading = not m.fed and m.life < 8 and floor(game.clock * 4) % 2 == 0
        stamp(M.mat(), m.x, 0, m.z, fading and T.DARKER or nil)
    end
    if mode == "mat" and hover.c and not hover.button then
        local ok = game:canMat(hover.c, hover.r)
        if world:distAt(hover.c, hover.r) then
            stamp(M.mat(), hover.c * 16 + 8, 0, hover.r * 16 + 8, ok and T.DARKER or T.DARKER2)
        end
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

    -- Reach: whatever is hovered, or what is about to be grown.
    local towerMode = D.TOWER[mode] and mode ~= "mat"
    if hover.node and hover.node.tower and D.TOWER[hover.node.tower.kind].range then
        local t = hover.node.tower
        ring(hover.node.x, hover.node.z, D.TOWER[t.kind].range * (t.reach or 1), IDX.l, true)
    elseif towerMode and hover.node and not hover.node.heart then
        local q = World.QUALITY[hover.node.quality].power
        ring(hover.node.x, hover.node.z, D.TOWER[mode].range * q, IDX.l, true)
    end
    if mode == "grow" and (drag or hover.node) then
        local from = drag or hover.node
        ring(from.x, from.z, D.LINK.reach, from.conn and IDX.c or IDX.r, true)
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
    local wilt = 1 - game.heartHp / D.HEART_HP
    add(game.heart.x, game.heart.y, game.heart.z, function()
        stamp(M.sprout(wilt), game.heart.x, game.heart.y - 1, game.heart.z, heartFlash > 0 and T.FLASH or nil)
    end)
    for _, n in ipairs(game.nodes) do
        local t = n.tower
        if t then
            add(n.x, n.y, n.z, function()
                stamp(towerPicture(t), n.x, n.y, n.z, remapFor(t))
                if t.boost then
                    for s = 0, 3 do
                        local a = game.clock * 5 + s * 1.57
                        local i, j = world:toImage(n.x + math.cos(a) * 6, n.y + 6 + math.sin(game.clock * 7 + s) * 4, n.z + math.sin(a) * 6)
                        put(IDX.w, i, j)
                    end
                end
                local d = D.TOWER[t.kind]
                if d.reserve and d.reserve > 0 and (t.reserve < d.reserve - 0.05 or not n.conn) then
                    bar(n.x, n.y + 17, n.z, t.reserve / d.reserve, n.conn and IDX.l or IDX.r)
                end
            end)
        elseif D.TOWER[mode] and mode ~= "mat" and hover.node == n and not n.heart then
            add(n.x, n.y, n.z, function()
                local ok = game:canBuild(mode, n)
                stamp(M.tower(mode, game.clock), n.x, n.y, n.z, ok and T.DARKER or T.DARKER2)
            end)
        end
    end
    for _, c in ipairs(game.corpses) do
        add(c.x, 0, c.z, function()
            local remap = T.DARKER
            if c.absorb then remap = floor(game.clock * 10) % 2 == 0 and T.DARKER2 or T.DARKER end
            stamp(M.corpse(c.kind, c.h or 0), c.x, c.carried and 2.5 or 0, c.z, remap)
        end)
    end
    for _, e in ipairs(game.enemies) do
        add(e.x, e.y, e.z, function()
            stamp(enemyPicture(e), e.x, e.y, e.z, e.flash > 0 and T.FLASH or nil)
            if e.hp < e.maxHp and e.kind ~= "mite" then
                bar(e.x, e.y + (e.kind == "brine" and 12 or 10), e.z, e.hp / e.maxHp, IDX.r)
            end
        end)
    end
    for _, s in ipairs(game.shots) do
        if s.kind == "spore" then
            local f = s.t / s.flight
            local x, z = s.x0 + (s.tx - s.x0) * f, s.z0 + (s.tz - s.z0) * f
            local y = s.y0 * (1 - f) + math.sin(math.pi * f) * 16
            add(x, y, z, function()
                local i, j, d = world:toImage(x, y, z)
                i, j = floor(i), floor(j)
                if visible(i, j, d + 2) then
                    put(IDX.t, i + 1, j + 1); put(IDX.t, i, j + 1); put(IDX.t, i + 1, j)
                    put(IDX.w, i, j)
                end
            end)
        else
            add(s.x1, s.y1, s.z1, function()
                line3(s.x0, s.y0, s.z0, s.x1, s.y1, s.z1, s.big and IDX.l or IDX.w)
            end)
        end
    end
    table.sort(movers, function(a, b) return a.d < b.d end)
    for _, m in ipairs(movers) do m.draw() end

    for _, p in ipairs(game.fx) do
        if p.cloud then
            local f = 1 - p.life / p.max
            local r = p.r * (0.5 + 0.5 * f)
            for s = 0, 29 do
                if love.math.random() > f * 0.8 then
                    local a = s / 30 * 2 * math.pi + f
                    local rr = r * (0.4 + 0.6 * ((s * 7) % 5) / 4)
                    local x, z = p.x + math.cos(a) * rr, p.z + math.sin(a) * rr
                    local i, j, d = world:toImage(x, 1 + f * 4 + (s % 3), z)
                    if visible(floor(i), floor(j), d + 2) then put(s % 3 == 0 and IDX.t or IDX.w, i, j) end
                end
            end
        elseif p.glow then
            local f = p.t / p.max
            local x, z = p.x + (p.tx - p.x) * f, p.z + (p.tz - p.z) * f
            local i, j, d = world:toImage(x, 1 + math.sin(f * math.pi) * 4, z)
            if visible(floor(i), floor(j), d + 2) then put(IDX.l, i, j) end
        else
            local i, j, d = world:toImage(p.x, p.y, p.z)
            if visible(floor(i), floor(j), d + 1) then put(IDX[p.k], i, j) end
        end
    end

    overlayImage:replacePixels(overlay)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(overlayImage, 0, 0)
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
    for _, kind in ipairs(D.ENEMY_ORDER) do
        if count[kind] then parts[#parts + 1] = count[kind] .. " " .. (kind == "mite" and "MITES" or kind:upper()) end
    end
    return table.concat(parts, "  ")
end

-- What to say at the bottom when nothing is hovered: the next thing to learn.
local function hint()
    if game.phase ~= "build" then
        local brine = false
        for _, e in ipairs(game.enemies) do if e.kind == "brine" and e.slide then brine = true end end
        if brine then return "BRINE IN THE NETWORK! PRUNE (X) THE LINK IT IS ON", "r" end
        return nil
    end
    local living = 0
    for _, l in ipairs(game.links) do if l.state ~= "cut" then living = living + 1 end end
    local towers = 0
    for _, n in ipairs(game.nodes) do if n.tower then towers = towers + 1 end end
    if living == 0 then return "DRAG FROM THE SPROUT TO A POCKET TO GROW A LINK", "g" end
    if towers == 0 then return "PICK A FRUITING BODY BELOW, THEN CLICK A LINKED POCKET", "g" end
    local nxt = game:nextWave()
    if nxt then
        for _, g in ipairs(nxt) do
            if not game.seen[g[1]] then return "NEW: " .. D.ENEMIES[g[1]].name .. ". " .. D.ENEMIES[g[1]].blurb, "t" end
        end
    end
    if game.wave == 0 then return "SPACE TO START THE FIRST WAVE", "g" end
end

local function tooltip()
    if hover.button then
        local b = BUTTONS[hover.button]
        return b.name .. (b.cost and (" (" .. b.cost .. ")") or "") .. ": " .. b.blurb, "w"
    end
    if hover.wave then
        return game.phase == "build" and "START THE NEXT WAVE (SPACE)" or "GAME SPEED (F)", "w"
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
        local d = D.TOWER[t.kind]
        local s = d.name
        if mode == "prune" then return "CLEAR " .. s .. ": +" .. floor(t.spent * D.SELL), "r" end
        if t.hunger == "dormant" then s = s .. ": DORMANT, NO NUTRIENTS"
        elseif not hover.node.conn then s = s .. ": CUT OFF, ON ITS RESERVE"
        elseif t.hunger == "starved" then s = s .. ": STARVED" end
        if t.kind == "puffer" then s = s .. "  PUFFS " .. max(1, min(4, game:degree(hover.node))) end
        if t.kind == "needle" and game:degree(hover.node) == 1 then s = s .. "  DEAD END X1.8" end
        if hover.node.ringed then s = s .. "  RING +25%" end
        return s .. "  " .. hover.node.quality:upper() .. " POCKET", "w"
    end
    if hover.node then
        local n = hover.node
        if n.heart then return "THE SPROUT. IF IT DIES, YOU LOSE", "g" end
        local s = n.pocket.kind:upper() .. ": " .. n.quality:upper() .. " POCKET"
        if (n.salted or 0) > 0 then s = s .. ", SALTED" end
        if n.quality == "rich" then s = s .. ". +30% POWER, PAYS SUGAR" elseif n.quality == "poor" then s = s .. ". -25% POWER" end
        if D.TOWER[mode] and mode ~= "mat" then
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
            return "CUT LINK. CLICK TO REGROW: " .. game:repairCost(l), "l"
        end
        local s = "LINK " .. floor(l.hp) .. "/" .. D.LINK.hp .. "  FLOW " .. l.cap
        if l.thick then s = s .. " (RELAY)" end
        if not l.a.conn then s = s .. "  NOT FED" end
        return s, "w"
    end
    if mode == "mat" and hover.c then
        local ok, why = game:canMat(hover.c, hover.r)
        if ok then return "LAY SLIME MAT: " .. D.TOWER.mat.cost, "l" end
        if not world:distAt(hover.c, hover.r) then return "SLIME MATS GO ON THE TRAIL", "r" end
        return why or "", "r"
    end
    if mode == "prune" and hover.mat then return "LIFT MAT", "r" end
    if mode == "grow" and drag then return "LET GO OVER A GLOWING POCKET. RIGHT CLICK CANCELS", "l" end
    if mode == "pulse" then
        if game.pulseCd > 0 then return "PULSE REGROWING: " .. math.ceil(game.pulseCd) .. "S", "r" end
        return "CLICK A FED NODE TO SEND THE PULSE", "l"
    end
end

local function drawHud()
    -- The top strip.
    color("o")
    love.graphics.rectangle("fill", 0, 0, vw, TOP - 1)
    local inc = game.income or 0
    local s = "NUTRIENTS " .. floor(game.nutrients)
    text(s, 3, 3, "l")
    local x = 3 + Font.width(s) + 2
    if game.phase == "wave" then
        local i = (inc >= 0 and "+" or "") .. string.format("%.1f", inc)
        text(i, x + 2, 3, inc >= 0 and "c" or "r")
        x = x + Font.width(i) + 4
    end
    s = "SPROUT " .. math.ceil(game.heartHp) .. "/" .. D.HEART_HP
    text(s, x + 8, 3, game.heartHp < D.HEART_HP * 0.4 and "r" or "g")
    local w = "WAVE " .. game.wave .. "/" .. #D.WAVES
    local nxt = game:nextWave()
    local right = w
    if nxt and game.phase == "build" then right = "NEXT: " .. waveSummary(nxt) .. "   " .. w end
    if game.phase == "wave" then
        local left = #game.queue
        for _, e in ipairs(game.enemies) do left = left + 1 end
        right = left .. " LEFT   " .. w
    end
    text(right, vw - Font.width(right) - 3, 3, "w")
    if paused then text("PAUSED", floor((vw - Font.width("PAUSED")) / 2), 3, "r") end

    -- Gates: where the next wave comes in.
    if nxt and game.phase == "build" then
        local per = {}
        for _, g in ipairs(nxt) do per[g[4]] = (per[g[4]] or 0) + g[2] * (g[1] == "mite" and D.ENEMIES.mite.swarm or 1) end
        for gate, n in pairs(per) do
            local e = world.entrances[gate]
            if e then
                local i, j = world:toImage(e.x - 6, 6, e.z)
                local sx, sy = floor(i - camx), floor(j - camy)
                if floor(game.clock * 2) % 2 == 0 then label(n .. " IN", sx - 6, sy - 10, "w", "r") end
            end
        end
    end

    -- Words in the world.
    for _, t in ipairs(game.texts) do
        local i, j = world:toImage(t.x, t.y, t.z)
        local sx, sy = floor(i - camx - Font.width(t.text) / 2), floor(j - camy)
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
            local pic = M.tower(b.mode, game.clock)
            local afford = game.nutrients >= (b.cost or 0)
            blit(pic, cx, b.mode == "mat" and by + 12 or by + 18, not afford and T.DARKER2 or nil)
        end
        text(b.key, bx + 1, by + 1, "s")
        if b.cost then
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
        text("SPACE", wx + floor((ww - Font.width("SPACE")) / 2), wy + 20, "s")
    else
        box(wx, wy, ww, wh, "u", hover.wave and "t" or "o")
        local s2 = "SPEED X" .. speed
        text(s2, wx + floor((ww - Font.width(s2)) / 2), wy + 9, "w")
        text("F", wx + floor((ww - 3) / 2), wy + 18, "s")
    end

    -- One line of help above the toolbar.
    local tip, k = tooltip()
    if not tip then tip, k = hint() end
    if tip then
        if Font.width(tip) > vw - 8 then tip = tip:sub(1, floor((vw - 8) / 4)) end
        centred(tip, vh - BH - 14, k)
    end

    if game.phase == "won" then
        centred("THE SPROUT LIVES", floor(vh / 2) - 24, "g")
        centred("KILLS " .. game.stats.kills .. "   DRUNK " .. floor(game.stats.drunk) .. "   CUTS " .. game.stats.cuts, floor(vh / 2) - 12, "w")
        centred("R TO PLAY AGAIN", floor(vh / 2), "l")
    elseif game.phase == "lost" then
        centred("THE SPROUT HAS WILTED", floor(vh / 2) - 24, "r")
        centred("YOU HELD " .. (game.wave - 1) .. " WAVES OF " .. #D.WAVES, floor(vh / 2) - 12, "w")
        centred("R TO TRY AGAIN", floor(vh / 2), "l")
    end
end

local function drawLoading()
    love.graphics.clear(unpack(T.RGB[IDX.o]))
    local s = "GROWING THE PATIO"
    local w = 80
    local x, y = floor((vw - w) / 2), floor(vh / 2)
    text(s, floor((vw - Font.width(s)) / 2), y - 10, "t")
    color("u")
    love.graphics.rectangle("fill", x, y, w, 4)
    color("c")
    love.graphics.rectangle("fill", x, y, floor(w * progress), 4)
end

function love.draw()
    love.graphics.setCanvas(canvas)
    if painter then
        drawLoading()
    else
        drawBoard()
        drawHud()
    end
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, zoom, zoom)
end
