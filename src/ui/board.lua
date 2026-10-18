-- The board drawn each frame: the board's picture for the sky (two of them
-- dithering while the weather turns), then the overlay over it -- ink, shadows,
-- mats, threads and rings on the ground first, then everything standing up,
-- furthest first, then smoke, sparks and the weather itself.

local ffi = require "ffi"
local T = require "src.tracer"
local World = require "src.world"
local Game = require "src.game"
local D = require "src.defs"
local M = require "src.models"
local S = require "src.ui.state"
local Pixels = require "src.ui.pixels"
local flair = require "src.ui.flair"

local floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt
local IDX = T.IDX
local putS, put, putGround, visible, screenBox, turned, stamp, outline, shadow, line3, ring =
    Pixels.putS, Pixels.put, Pixels.putGround, Pixels.visible, Pixels.screenBox, Pixels.turned, Pixels.stamp,
    Pixels.outline, Pixels.shadow, Pixels.line3, Pixels.ring

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
    -- A Truffle's, underground: a ridge of soil with the glow showing through.
    local buried = l.buried and l.state == "alive" and not highlight and not surge
    if buried then core, under = IDX.t, IDX.n end
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
                        k = buried and IDX.c or IDX.l
                    end
                end
                -- A Bleeding Tooth's sap: dark red beads along it, swelling in turn.
                if l.sap and l.state == "alive" and not highlight and s % 6 == 3 then
                    put(IDX.r, i, j - 1)
                    if floor(t * 2 + s * 0.2) % 3 == 0 then put(IDX.r, i + 1, j - 1) end
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

-- Each enemy's picture this frame: its model, facing as it goes in the view
-- shown, on the step of its walk (or its roll, its leap, its dig).
local PICTURE = {
    ant = function(e)
        local rate = (e.state == "chew" or e.state == "gnawShelf") and 14 or 8
        return M.ant(turned(e.h), floor(e.anim * rate) % 2)
    end,
    pillbug = function(e)
        if e.rolling then return M.pillbug(turned(e.h), true, floor(e.anim * 12) % 4) end
        return M.pillbug(turned(e.h), false)
    end,
    mite = function(e) return M.mite(turned(e.h)) end,
    gnat = function(e) return M.gnat(turned(e.h), floor(e.anim * 20) % 2) end,
    slug = function(e) return M.slug(turned(e.h), floor(e.anim * (e.state == "eat" and 4 or 2)) % 2) end,
    spider = function(e) return M.spider(turned(e.h), floor(e.anim * 10) % 2) end,
    knight = function(e) return M.knight(turned(e.h), floor(e.anim * 6) % 2) end,
    queen = function(e) return M.queen(turned(e.h), floor(e.anim * 5) % 2) end,
    stag = function(e) return M.stag(turned(e.h), floor(e.anim * (e.charging and 14 or 6)) % 2, e.charging ~= nil) end,
    dung = function(e)
        -- It walks backwards, pushing: its picture faces away from the way it goes.
        return M.dung(turned(e.h + math.pi), floor(e.anim * 5) % 2)
    end,
    moth = function(e) return M.moth(turned(e.h), floor(e.anim * 12) % 2) end,
    waterbug = function(e) return M.waterbug(turned(e.h), floor(e.anim * 5) % 2, e.state == "grab" or e.state == "lunge") end,
    centipede = function(e) return M.centipede(turned(e.h), floor(e.anim * 8) % 2) end,
    centseg = function(e) return M.centseg(turned(e.h), floor(e.anim * 8 + (e.x + e.z) * 0.1) % 2) end,
    centi = function(e) return M.centipede(turned(e.h), floor(e.anim * 10) % 2, 0.9) end,
    centiseg = function(e) return M.centseg(turned(e.h), floor(e.anim * 10 + (e.x + e.z) * 0.1) % 2, 0.85) end,
    cricket = function(e)
        local dig = e.state == "sink" or e.state == "up"
        return M.mole(turned(e.h), floor(e.anim * (dig and 7 or 6)) % 2, dig, 1.35)
    end,
    bombardier = function(e) return M.bombardier(turned(e.h), floor(e.anim * 6) % 2, e.state == "siege") end,
    springtail = function(e) return M.springtail(turned(e.h), floor(e.anim * 9) % 2, e.hopT ~= nil) end,
    click = function(e)
        if e.state == "belly" then return M.click(turned(e.h), floor(e.anim * 8) % 2, "belly") end
        if e.state == "leap" then return M.click(turned(e.h), 0, "leap", floor((e.spin or 0) * 4) % 4) end
        return M.click(turned(e.h), floor(e.anim * 5) % 2)
    end,
    mole = function(e)
        local dig = e.state == "dig" or e.state == "surface"
        return M.mole(turned(e.h), floor(e.anim * (dig and 7 or 5)) % 2, dig)
    end,
    brine = function(e) return M.brine(floor(e.anim * 4) % 2) end,
    diver = function(e) return M.diver(turned(e.h), floor(e.anim * 7) % 2) end,
    wireworm = function(e) return M.wireworm(turned(e.h), floor(e.anim * 5) % 2) end,
    leafcutter = function(e)
        local rate = e.gnaw and 14 or 9
        return M.leafcutter(turned(e.h), floor(e.anim * rate) % 2, e.full)
    end,
    mold = function(e) return M.mold(floor(e.anim * 2) % 2) end,
    naiad = function(e) return M.naiad(turned(e.h), floor(e.anim * 5) % 2, e.strikeT ~= nil, e.state == "molt") end,
    dragonfly = function(e) return M.dragonfly(turned(e.h), floor(e.anim * 24) % 2) end,
    rhino = function(e) return M.rhino(turned(e.h), floor(e.anim * 5) % 2, e.tossT ~= nil) end,
    hornet = function(e) return M.hornet(turned(e.h), floor(e.anim * 22) % 2) end,
}

local function enemyPicture(e) return (PICTURE[e.kind] or PICTURE.brine)(e) end

local SHADOW = { ant = 4, pillbug = 4.5, brine = 3.5, gnat = 2.5, slug = 6, spider = 5, knight = 5,
    queen = 11, stag = 13, dung = 10, moth = 3.5, waterbug = 12, centipede = 6, centseg = 5.5, bombardier = 10,
    springtail = 3, click = 10, mole = 10, cricket = 5.5, centi = 3.5, centiseg = 3,
    diver = 4.5, wireworm = 3, leafcutter = 4, mold = 4.5, naiad = 11, dragonfly = 9, rhino = 13, hornet = 8 }

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
local function heave(x, z, t, k)
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
local function hole(x, z, r)
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
local function tunnelLine(a, b)
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
local function shock(p)
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
local function splat(p)
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

local function draw()
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
    for _, p in ipairs(S.game.fx) do if p.splat then splat(p) end end
    for _, p in ipairs(S.game.fx) do if p.shock then shock(p) end end
    for _, t in ipairs(S.game.tunnels) do
        if t.open then tunnelLine(t.a, t.b); hole(t.b.x, t.b.z, 6) end
        hole(t.a.x, t.a.z, 6)
    end
    for _, e in ipairs(S.game.enemies) do
        if e.under and (e.kind == "mole" or e.kind == "cricket" or e.kind == "wireworm") then
            heave(e.x, e.z, S.game.clock, e.kind == "cricket" and 0.5 or (e.kind == "wireworm" and 0.35))
        elseif e.under then ripples(e.x, e.z, S.game.clock) end
        if e.under and (e.exposed or 0) > 0 then
            -- Found by an Earthstar: a rust mark over it, for everything to aim at.
            local i, j = S.world:toImage(e.x, S.world:groundAt(e.x, e.z) + 6, e.z)
            i, j = floor(i), floor(j)
            put(IDX.r, i, j); put(IDX.r, i - 1, j - 1); put(IDX.r, i + 1, j - 1); put(IDX.r, i, j - 2)
        end
        if not e.under and SHADOW[e.kind] and not e.hidden then shadow(e.x, e.z, SHADOW[e.kind]) end
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
                local i, j = S.world:toImage(x, y, z)
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
        elseif s.kind == "drop" then
            local x, y, z = arc(s, 6)
            add(x, y, z, function() dot(x, y, z, IDX.w, IDX.s) end)
        else
            add(s.x1, s.y1, s.z1, function()
                line3(s.x0, s.y0, s.z0, s.x1, s.y1, s.z1, s.k and IDX[s.k] or (s.big or s.mark) and IDX.l or IDX.w)
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

return { draw = draw }
