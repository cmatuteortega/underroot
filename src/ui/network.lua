-- The Spore Bank's network: the screen next to the encyclopedia where spores
-- are spent. The sprout in the middle, every node of D.NETWORK spread out
-- around it (src/network.lua lays them out), and the hyphae between them:
-- lit where they have grown, dim where they could, dark where they wait on
-- something. Buying a node's first rank grows its thread out from the one
-- it grows from, so the network spreads as it is bought.
--
-- Each node shows what it grows: the species (at the tier an upgrade node
-- brings), the seed, the enemy a field note is on, or a glyph for the
-- network's own numbers; dimmed while it waits, a silhouette behind a win.
-- Zoomed out the nodes are only dots, to see the whole of it at once.
--
-- Drag (or the arrows) to pan, the wheel, a pinch or + and - to zoom. A node
-- tapped is shown in the panel; tapped again, or its button, or G, grows a
-- rank. TAB picks the next node there are spores for.
--
-- For testing: `love . --spores 100000` puts that many in the bank, as do F8
-- on this screen and seven quick taps on its spore count. REGROW (twice)
-- sells the whole network back for every spore it cost.

local D = require "src.defs"
local N = require "src.network"
local Font = require "src.font"
local Profile = require "src.profile"
local S = require "src.ui.state"
local T = require "src.tracer"
local M = require "src.models"
local Draw = require "src.ui.draw"
local Pixels = require "src.ui.pixels"
local flair = require "src.ui.flair"

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt
local color, box, text, wrapLines, number, say, inside, wide =
    Draw.color, Draw.box, Draw.text, Draw.wrapLines, Draw.number, Draw.say, Draw.inside, Draw.wide
local sound, deny = flair.sound, flair.deny
local blit, CUT = Pixels.blit, Pixels.CUT

local net = {}

net.STEPS = { 12, 31, 40 } -- HUD pixels a step out from the sprout, at each zoom: the first is dots only
net.TESTING = 100000 -- what F8 and the seven taps put in the bank

net.cam = { x = 0, y = 0 } -- the pan, HUD pixels
net.zoom = 2
net.sel = nil -- the node in the panel
net.grew = {} -- when each node last grew a rank: its thread or its ring lights from then
net.back = nil -- "loadout" when it was opened from there, to go back to it
net.taps = { n = 0, t = 0 } -- quick taps on the spore count
net.sure = 0 -- until when REGROW waits for its second press
net.note = nil -- a line across the bottom for a moment: { s, k, t }

--- what the rest of the screens ask of it ------------------------------------------------------

-- A species or seed shut behind a level not won yet: still a "???" elsewhere.
function net.hidden(id)
    local row = Profile.nodeOf(id)
    return row ~= nil and Profile.nodeState(row.id) == "locked"
end

-- One line on how to get a species or seed not grown yet.
function net.howTo(id)
    local row = Profile.nodeOf(id)
    local state, level = Profile.nodeState(row.id)
    local name = D.TOWER[id] and D.TOWER[id].name or D.SEED[id].name
    if state == "locked" then return "???: WIN " .. level.name .. ", THEN GROW IT ON THE NETWORK" end
    if state == "shut" then return name .. ": GROW " .. D.NET[row.at].name .. " ON THE NETWORK FIRST" end
    return name .. ": GROW IT ON THE NETWORK, " .. N.price(Profile.net, row.id) .. " SPORES. YOU HAVE " .. Profile.spores
end

-- How many nodes there are spores for now: the menu's button shows it.
function net.ready()
    local n = 0
    for _, row in ipairs(D.NETWORK) do if Profile.nodeState(row.id) == "open" then n = n + 1 end end
    return n
end

-- Its button on the level picker, right of the encyclopedia's.
function net.button(after)
    local s = "NETWORK"
    local n = net.ready()
    if n > 0 then s = s .. " " .. n end
    return { x = after.x + after.w + 5, y = after.y, w = Font.width(s) + 8, h = 12, s = s, ready = n > 0 }
end

-- Opened from the level picker or the loadout; with `id` (a species or seed),
-- on the node it grows on.
function net.open(id)
    net.back = S.menu == "loadout" and "loadout" or nil
    S.menu = "network"
    net.sel, net.sure = nil, 0
    if id then
        local row = Profile.nodeOf(id)
        if row then net.sel = row.id; net.centre(row.id) end
    else
        -- Halfway from the sprout to the nearest node there are spores for,
        -- so both are on the screen.
        local near
        for _, row in ipairs(D.NETWORK) do
            if Profile.nodeState(row.id) == "open" and (not near or N.layout()[row.id].depth < N.layout()[near].depth) then
                near = row.id
            end
        end
        net.cam.x, net.cam.y = 0, 0
        if near then
            local p = N.layout()[near]
            net.cam.x, net.cam.y = -p.x * net.STEPS[net.zoom] / 2, -p.y * net.STEPS[net.zoom] / 2
        end
    end
    sound("panel")
end

function net.close()
    sound("back")
    if net.back == "loadout" and S.pick then S.menu = "loadout" else S.openMenu() end
end

--- where things are ---------------------------------------------------------------------------

local function panelWidth() return wide() and min(150, floor(S.vw * 0.36)) or S.vw - S.inset.l - S.inset.r - 6 end

function net.layout()
    local L = { back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 } }
    local rs = net.sure > flair.now() and "SURE? ALL BACK" or "REGROW"
    L.regrow = { s = rs, w = Font.width(rs) + 8, h = 12, y = S.inset.t + 4 }
    L.regrow.x = S.vw - S.inset.r - 4 - L.regrow.w
    L.spores = { x = L.back.x + L.back.w + 6, y = S.inset.t + 4, h = 12 }
    L.spores.s = "SPORES " .. Profile.spores
    L.spores.w = Font.width(L.spores.s) + 4
    local top, bottom = S.inset.t + 20, S.vh - S.inset.b - 2
    L.area = { x = S.inset.l, y = top, w = S.vw - S.inset.l - S.inset.r, h = bottom - top }
    if net.sel then
        local w = panelWidth()
        if wide() then
            L.panel = { x = S.vw - S.inset.r - w - 3, y = top, w = w, h = bottom - top - 1 }
            L.area.w = L.panel.x - 3 - L.area.x
        else
            local h = min(118, floor((bottom - top) * 0.5))
            L.panel = { x = S.inset.l + 3, y = bottom - h - 1, w = w, h = h }
            L.area.h = L.panel.y - 3 - top
        end
        L.panel.button = { x = L.panel.x + 4, y = L.panel.y + L.panel.h - 18, w = L.panel.w - 8, h = 14 }
    end
    L.cx = floor(L.area.x + L.area.w / 2 + net.cam.x)
    L.cy = floor(L.area.y + L.area.h / 2 + net.cam.y)
    L.step = net.STEPS[net.zoom]
    return L
end

-- Where a node is on the screen.
local function at(L, id)
    local p = N.layout()[id]
    return floor(L.cx + p.x * L.step + 0.5), floor(L.cy + p.y * L.step + 0.5)
end

-- A node's socket: a dot zoomed out, room for its picture zoomed in.
local SIZE = { { 6, 4, 3 }, { 13, 11, 9 }, { 17, 14, 12 } }
local function radius(row)
    local z = SIZE[net.zoom]
    if not row.at then return z[1] end
    if row.species or row.seed then return z[2] end
    return z[3]
end

-- The pan that puts a node in the middle of the free ground.
function net.centre(id)
    net.cam.x, net.cam.y = 0, 0
    local L = net.layout()
    local x, y = at(L, id)
    net.cam.x = L.area.x + L.area.w / 2 - x
    net.cam.y = L.area.y + L.area.h / 2 - y
end

-- Kept so the network cannot be dragged out of sight.
local function clampCam()
    local reach = 13 * net.STEPS[net.zoom]
    net.cam.x = max(-reach, min(reach, net.cam.x))
    net.cam.y = max(-reach, min(reach, net.cam.y))
end

function net.getCam() return { x = net.cam.x, y = net.cam.y } end
function net.drag(from, dx, dy)
    net.cam.x, net.cam.y = from.x + dx, from.y + dy
    clampCam()
end

-- Zoomed a step in (+1) or out (-1), about the middle of the screen.
function net.zoomBy(d)
    local z = max(1, min(#net.STEPS, net.zoom + d))
    if z == net.zoom then return end
    local f = net.STEPS[z] / net.STEPS[net.zoom]
    net.cam.x, net.cam.y = net.cam.x * f, net.cam.y * f
    net.zoom = z
    clampCam()
    sound("zoom")
end

--- what a node says ---------------------------------------------------------------------------

-- The names its numbers go by in the panel.
local NAME = { every = "EVERY", deadEnd = "DEAD END X", clusterDamage = "BOMBLETS", perNode = "PER NODE",
    maxHp = "HOST HP", capMul = "FLOW X", amp = "DAMAGE X", battery = "RESERVE X", towerHeal = "TOWER HEAL",
    inkSlow = "INK SLOW", inkLife = "INK LASTS", shieldMul = "CHEWING X", feast = "FEAST X", slow = "SLOW X",
    reek = "REEK X", maxRange = "MOST RANGE" }
-- The network's own numbers: what they are called, and what they are fully grown.
local WORLD = {
    linkHp = { "LINK HP", D.LINK.hp }, linkCap = { "FLOW", D.LINK.cap }, linkCost = { "A 40 LONG LINK COSTS", D.LINK.cost(40) },
    linkGrow = { "SECONDS TO GROW", D.LINK.grow }, ring = { "RING DAMAGE X", D.RING.damage },
    pulse = { "PULSE DAMAGE X", D.PULSE.damage }, heart = { "SPROUT HP ON THE CRACK", D.LEVELS[1].heart },
    income = { "SUGAR A SECOND", D.INCOME }, start = { "TO START ON THE CRACK", D.LEVELS[1].start },
    bonus = { "FIRST WAVE CLEARED PAYS", D.WAVE_BONUS + 4 },
}

-- "4.5 > 5.1 OF 6": now, at the next rank, and fully grown.
local function nowNext(mode, full, row, r)
    local now = N.scale(mode, full, N.factor(row, r))
    local s = number(floor(now * 100 + 0.5) / 100)
    if r < N.ranks(row) then s = s .. " > " .. number(floor(N.scale(mode, full, N.factor(row, r + 1)) * 100 + 0.5) / 100) end
    return s .. " OF " .. number(full)
end

local function kindOf(row)
    if not row.at then return "THE SPROUT" end
    if row.species then return "SPECIES: " .. D.TOWER[row.species].role end
    if row.tower then return D.TOWER[row.tower].name end
    if row.up then return "UPGRADES: " .. D.TOWER[row.up[1]].name end
    if row.seed then return "SEED" end
    if row.vs then return "FIELD NOTES" end
    if row.mutations then return "MUTATIONS" end
    return "THE NETWORK"
end

-- A node's panel, as lines { s, k } `w` wide.
function net.lines(id, w)
    local row = D.NET[id]
    local r, n = N.rank(Profile.net, id), N.ranks(row)
    local out = {}
    local function add(s, k) for _, l in ipairs(wrapLines(s, w)) do out[#out + 1] = { s = l, k = k } end end
    local function gap() out[#out + 1] = { gap = 3 } end
    add(row.name, "w")
    add(kindOf(row), "t")
    if not row.free then add(n > 1 and ("RANK " .. r .. " OF " .. n) or (r > 0 and "GROWN" or "NOT GROWN"), r >= n and "g" or "l") end
    gap()
    add(row.blurb, "s")
    if row.species then gap(); add(D.TOWER[row.species].about, "s") end
    if row.seed then gap(); add(D.SEED[row.seed].about, "s") end
    if row.tower then
        gap()
        local d = D.TOWER[row.tower]
        for _, k in ipairs(row.stats) do
            local name = NAME[k] or k:upper()
            if type(d[k]) == "number" then
                add(name .. " " .. nowNext(N.MODE[k] or "more", d[k], row, r), "l")
            else
                add(name .. ", FROM ITS UPGRADES: " .. floor(N.factor(row, r) * 100 + 0.5) .. "%", "l")
            end
        end
    end
    if row.world then
        gap()
        local w2 = WORLD[row.world]
        add(w2[1] .. " " .. nowNext(N.WORLD[row.world], w2[2], row, r), "l")
        if row.world == "pulse" then
            add("COMES BACK IN " .. floor(N.scale("less", D.PULSE.cooldown, N.factor(row, r)) + 0.5) .. "S, FULLY "
                .. D.PULSE.cooldown .. "S", "l")
        end
    end
    if row.vs then
        gap()
        add("DAMAGE TO THEM X" .. nowNext("more", 1, row, r), "l")
        local met = {}
        for _, k in ipairs(row.vs) do
            if Profile.seen[k] and not D.ENEMIES[k].segment then met[#met + 1] = D.ENEMIES[k].name end
        end
        if #met > 0 then add("MET: " .. table.concat(met, ", "), "s") end
    end
    if row.up then
        gap()
        local up = D.TOWER[row.up[1]].up[row.up[2]]
        for tier = 1, 2 do add((tier == 1 and "I  " or "II ") .. up[tier].name, tier <= r and "g" or "k") end
    end
    if row.mutations then
        gap()
        for k, m in ipairs(row.mutations) do
            for _, mm in ipairs(D.MUTATIONS) do
                if mm.id == m then
                    add(mm.name, k <= r and "g" or "k")
                    add(mm.blurb, k <= r and "s" or "k")
                end
            end
        end
    end
    if row.pulse then gap(); add("THE PULSE ON THE TOOLBAR: A SURGE TO ANY FED NODE, EVERY TOWER ON THE WAY OVERCHARGED", "s") end
    return out
end

-- What the panel's button says, and whether it can be pressed.
local function buttonText(id)
    local state, level = Profile.nodeState(id)
    local row = D.NET[id]
    if state == "full" then return row.free and "THERE FROM THE START" or "FULLY GROWN", false, "g" end
    if state == "open" then return say("G: ", "") .. "GROW IT: " .. N.price(Profile.net, id) .. " SPORES", true, "l" end
    if state == "poor" then return N.price(Profile.net, id) .. " SPORES. YOU HAVE " .. Profile.spores, false, "r" end
    if state == "shut" then return "GROW " .. D.NET[row.at].name .. " FIRST", false, "k" end
    if state == "locked" then return "WIN " .. level.name .. " FIRST", false, "r" end
    return "???", false, "k"
end

--- growing ---------------------------------------------------------------------------------

local function say2(s, k) net.note = { s = s, k = k or "l", t = flair.now() + 2.5 } end

function net.grow(id)
    local row = D.NET[id]
    if not Profile.buy(id) then deny() return false end
    net.grew[id] = flair.now()
    sound((row.species or row.seed) and "unlock" or "grow")
    local r = N.rank(Profile.net, id)
    if r >= N.ranks(row) then say2(row.name .. " FULLY GROWN", "g") else say2(row.name .. ": RANK " .. r, "l") end
    return true
end

-- The next node there are spores for, round from the one in the panel.
local function nextOpen()
    local list = D.NETWORK
    local start = 0
    for k, row in ipairs(list) do if row.id == net.sel then start = k end end
    for d = 1, #list do
        local row = list[(start + d - 1) % #list + 1]
        if Profile.nodeState(row.id) == "open" then return row.id end
    end
end

local function testing()
    Profile.spores = Profile.spores + net.TESTING
    Profile.save()
    sound("unlock")
    say2("+" .. net.TESTING .. " SPORES, FOR TESTING", "t")
end

local function regrow()
    if net.sure > flair.now() then
        net.sure = 0
        local back = Profile.regrow()
        net.grew = {}
        sound("prune")
        say2("THE NETWORK IS SOLD BACK: +" .. back .. " SPORES", "t")
    else
        net.sure = flair.now() + 3
        sound("select")
    end
end

--- each node's picture ------------------------------------------------------------------------

local FACE = 0.35 -- the way a model faces: a little to the right of towards you, as in the encyclopedia
local NOTE = {
    notes = function() return M.spider, { FACE, 0 } end,
    ["notes.ants"] = function() return M.ant, { FACE, 0 } end,
    ["notes.shells"] = function() return M.pillbug, { FACE, false, 0 } end,
    ["notes.crawlers"] = function() return M.centipede, { FACE, 0, 0.9 } end,
    ["notes.fliers"] = function() return M.gnat, { FACE, 0 } end,
    ["notes.diggers"] = function() return M.springtail, { FACE, 0, 0 } end,
    ["notes.soft"] = function() return M.slug, { FACE, 0 } end,
}

-- The model a node shows, and what to ask it for; nil for a glyph. An
-- upgrade shows the tier its next rank grows.
local function model(row, r)
    if not row.at or row.id == "root" then return M.sprout, { 0, "bean" } end
    local kind = row.species or row.tower
    if kind then return M.tower, { kind, nil, 0, 0, 0 } end
    if row.up then return M.tower, { row.up[1], row.up[2], min(2, r + 1), 0, 0 } end
    local seed = row.seed or row.id:match("^(%w+)%.mut$")
    if seed then return M.sprout, { 0, seed } end
    if NOTE[row.id] then return NOTE[row.id]() end
    if row.id == "harvest" then return M.corpse, { "ant", FACE } end
end

-- What of a picture is drawn, not its margins: { x, y, w, h } in it.
local inks = setmetatable({}, { __mode = "k" })
local function ink(p)
    local b = inks[p]
    if b then return b end
    local x0, y0, x1, y1 = p.w, p.h, -1, -1
    for j = 0, p.h - 1 do
        for i = 0, p.w - 1 do
            if p.key[j * p.w + i] ~= 0 then x0, x1, y0, y1 = min(x0, i), max(x1, i), min(y0, j), max(y1, j) end
        end
    end
    b = x1 < 0 and { x = 0, y = 0, w = p.w, h = p.h } or { x = x0, y = y0, w = x1 - x0 + 1, h = y1 - y0 + 1 }
    inks[p] = b
    return b
end

-- Its picture, painted at the size whose drawn part fills a `box` pixels square.
local pics = {}
local function picture(row, r, box)
    local f, args = model(row, r)
    if not f then return end
    local key = row.id .. ":" .. (row.up and min(2, r + 1) or 0) .. ":" .. box
    local p = pics[key]
    if p then return p end
    local b = ink(f(unpack(args)))
    local s = max(0.25, min(2, floor(min(box / b.w, box / b.h) * 4) / 4))
    p = s == 1 and f(unpack(args)) or M.scaled(s, f, unpack(args))
    pics[key] = p
    return p
end

-- The network's own numbers have no model: a few strokes each, `r` the room.
local function line(x0, y0, x1, y1) love.graphics.line(floor(x0) + 0.5, floor(y0) + 0.5, floor(x1) + 0.5, floor(y1) + 0.5) end
local function drop(x, y, r)
    love.graphics.circle("fill", floor(x) + 0.5, floor(y + r * 0.3) + 0.5, r * 0.55)
    love.graphics.polygon("fill", x - r * 0.5, y + r * 0.15, x + r * 0.5, y + r * 0.15, x, y - r * 0.7)
end
local GLYPH = {
    -- A thread forking.
    hyphae = function(x, y, r, a, b)
        color(a); line(x, y + r * 0.7, x, y); line(x, y, x - r * 0.55, y - r * 0.6); line(x, y, x + r * 0.6, y - r * 0.45)
        color(b); line(x - r * 0.55, y - r * 0.6, x - r * 0.75, y - r * 0.2); line(x + r * 0.6, y - r * 0.45, x + r * 0.5, y - r * 0.8)
    end,
    -- Three threads side by side, nutrients along them.
    ["hyphae.cap"] = function(x, y, r, a, b)
        for k = -1, 1 do color(a); line(x - r * 0.7, y + k * r * 0.45, x + r * 0.7, y + k * r * 0.45) end
        color(b)
        for k = -1, 1 do love.graphics.rectangle("fill", floor(x + k * r * 0.35), floor(y + k * r * 0.45) - 1, 2, 3) end
    end,
    -- A short thread, cut.
    ["hyphae.cost"] = function(x, y, r, a, b)
        color(a); line(x - r * 0.7, y + r * 0.5, x - r * 0.1, y - r * 0.1); line(x + r * 0.15, y - r * 0.15, x + r * 0.7, y - r * 0.6)
        color(b); line(x - r * 0.25, y - r * 0.45, x + r * 0.3, y + r * 0.3)
    end,
    -- A thread shooting out.
    ["hyphae.grow"] = function(x, y, r, a, b)
        color(a); line(x - r * 0.7, y + r * 0.6, x + r * 0.5, y - r * 0.5)
        color(b); line(x + r * 0.6, y - r * 0.6, x + r * 0.05, y - r * 0.55); line(x + r * 0.6, y - r * 0.6, x + r * 0.55, y - r * 0.05)
    end,
    -- A ring of nodes.
    ring = function(x, y, r, a, b)
        color(a); love.graphics.circle("line", floor(x) + 0.5, floor(y) + 0.5, r * 0.6)
        color(b)
        for k = 0, 4 do
            local t = k / 5 * 2 * math.pi - math.pi / 2
            love.graphics.rectangle("fill", floor(x + math.cos(t) * r * 0.6) - 1, floor(y + math.sin(t) * r * 0.6) - 1, 3, 3)
        end
    end,
    -- A surge.
    pulse = function(x, y, r, a, b)
        color(a)
        love.graphics.polygon("fill", x + r * 0.25, y - r * 0.8, x - r * 0.45, y + r * 0.1, x, y + r * 0.1)
        love.graphics.polygon("fill", x, y - r * 0.05, x + r * 0.45, y - r * 0.05, x - r * 0.25, y + r * 0.8)
        color(b); love.graphics.rectangle("fill", floor(x) - 1, floor(y) - 1, 2, 2)
    end,
    -- Spores: what mutates.
    spores = function(x, y, r, a, b)
        color(a)
        love.graphics.circle("fill", floor(x - r * 0.35) + 0.5, floor(y + r * 0.3) + 0.5, r * 0.3)
        love.graphics.circle("fill", floor(x + r * 0.35) + 0.5, floor(y + r * 0.25) + 0.5, r * 0.25)
        love.graphics.circle("fill", floor(x) + 0.5, floor(y - r * 0.35) + 0.5, r * 0.32)
        color(b); love.graphics.rectangle("fill", floor(x) - 1, floor(y - r * 0.4) - 1, 2, 2)
    end,
    -- Sugar: a drop of it, or a few.
    sap = function(x, y, r, a, b)
        color(a); drop(x, y, r)
        color(b); love.graphics.rectangle("fill", floor(x - r * 0.15), floor(y + r * 0.1), 1, 2)
    end,
    store = function(x, y, r, a)
        color(a); drop(x - r * 0.35, y + r * 0.3, r * 0.5); drop(x + r * 0.35, y + r * 0.3, r * 0.5); drop(x, y - r * 0.3, r * 0.5)
    end,
}
GLYPH["pulse.power"] = GLYPH.pulse
GLYPH["lore.wild"], GLYPH["lore.soil"] = GLYPH.spores, GLYPH.spores

-- How a node's picture looks by where it stands: dimmed while it waits on
-- what it grows from, a silhouette behind a win.
local function remapOf(st)
    if st == "locked" then return CUT end
    if st == "shut" then return T.DARKER end
end

local function drawIcon(row, st, r, x, y, rad)
    local box = rad * 2 - 3
    local pic = picture(row, r, box)
    if pic then
        local sx, sy, sw, sh = love.graphics.getScissor()
        love.graphics.intersectScissor(x - rad, y - rad, rad * 2 + 1, rad * 2 + 1)
        local b = ink(pic)
        blit(pic, x - b.x - floor(b.w / 2) + pic.oi, y - b.y - floor(b.h / 2) + pic.oj, remapOf(st))
        love.graphics.setScissor(sx, sy, sw, sh)
        return
    end
    local g = GLYPH[row.id]
    if not g then return end
    local a, b = "l", "w"
    if st == "locked" then a, b = "o", "o"
    elseif st == "shut" then a, b = "k", "s" end
    g(x, y, rad, a, b)
end

--- drawing ---------------------------------------------------------------------------------

-- A hypha from (x0, y0) to (x1, y1), bowed a little to one side (the same
-- side every frame, by `seed`), drawn as far as `upto` (0 to 1) of the way.
local function thread(x0, y0, x1, y1, seed, upto, dotted)
    local dx, dy = x1 - x0, y1 - y0
    local len = sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local bow = (seed % 2 == 0 and 1 or -1) * min(4, len * 0.12)
    local nx, ny = -dy / len * bow, dx / len * bow
    local steps = max(3, floor(len / 4))
    local px, py = x0, y0
    for k = 1, steps do
        local t = k / steps
        if t > upto + 1e-6 then break end
        local b = 4 * t * (1 - t)
        local qx, qy = x0 + dx * t + nx * b, y0 + dy * t + ny * b
        if not dotted or k % 2 == 0 then love.graphics.line(px + 0.5, py + 0.5, qx + 0.5, qy + 0.5) end
        px, py = qx, qy
    end
    return px, py
end

-- A point `t` of the way along the same thread.
local function along(x0, y0, x1, y1, seed, t)
    local dx, dy = x1 - x0, y1 - y0
    local len = sqrt(dx * dx + dy * dy)
    local bow = (seed % 2 == 0 and 1 or -1) * min(4, len * 0.12)
    local nx, ny = -dy / max(len, 1) * bow, dx / max(len, 1) * bow
    local b = 4 * t * (1 - t)
    return floor(x0 + dx * t + nx * b), floor(y0 + dy * t + ny * b)
end

local GROW_TIME = 0.7

function net.draw()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local L = net.layout()
    local now = flair.now()
    local states = {}
    for k, row in ipairs(D.NETWORK) do states[row.id] = { Profile.nodeState(row.id), k } end

    love.graphics.setScissor(L.area.x, L.area.y, L.area.w, L.area.h)
    -- The threads first, the dim ones under the lit.
    for pass = 1, 2 do
        for k, row in ipairs(D.NETWORK) do
            local st = states[row.id][1]
            if row.at and st ~= "unknown" then
                local r = N.rank(Profile.net, row.id)
                local x0, y0 = at(L, row.at)
                local x1, y1 = at(L, row.id)
                local depth = N.layout()[row.id].depth
                if r == 0 and pass == 1 then
                    -- Not grown: dotted where it could be, faint where it waits.
                    color((st == "open" or st == "poor") and "k" or "u")
                    love.graphics.setLineWidth(1)
                    thread(x0, y0, x1, y1, k, 1, true)
                elseif r > 0 and pass == 2 then
                    local grew = net.grew[row.id]
                    local upto = (grew and r == 1) and min(1, (now - grew) / GROW_TIME) or 1
                    if upto < 1 then
                        color("k")
                        love.graphics.setLineWidth(1)
                        thread(x0, y0, x1, y1, k, 1, true)
                    end
                    color(r >= N.ranks(row) and "l" or "c")
                    love.graphics.setLineWidth(depth <= 2 and 2 or 1)
                    local tx, ty = thread(x0, y0, x1, y1, k, upto)
                    love.graphics.setLineWidth(1)
                    if upto < 1 and tx then
                        -- The growing tip.
                        color("w")
                        love.graphics.rectangle("fill", floor(tx) - 1, floor(ty) - 1, 3, 3)
                    else
                        -- Nutrients running out along it, now and then.
                        local t = (now * 0.45 + k * 0.37) % 1.6
                        if t < 1 then
                            local px, py = along(x0, y0, x1, y1, k, t)
                            color("w")
                            love.graphics.rectangle("fill", px, py, 1, 1)
                        end
                    end
                end
            end
        end
    end
    love.graphics.setLineWidth(1)

    -- The nodes.
    local blink = floor(now * 2.5) % 2 == 0
    for _, row in ipairs(D.NETWORK) do
        local st = states[row.id][1]
        if st ~= "unknown" then
            local x, y = at(L, row.id)
            local rad = radius(row)
            local r, n = N.rank(Profile.net, row.id), N.ranks(row)
            local icons = net.zoom >= 2
            local fill, edge
            if icons then
                -- A socket dark enough for the picture in it; the edge says where it stands.
                if not row.at then fill, edge = "d", "g"
                elseif r >= n then fill, edge = "d", "l"
                elseif r > 0 then fill, edge = "d", (st == "open" and blink) and "g" or "c"
                elseif st == "open" then fill, edge = "u", blink and "g" or "m"
                elseif st == "poor" then fill, edge = "u", "t"
                elseif st == "locked" then fill, edge = "u", "r"
                else fill, edge = "u", "k" end
            elseif not row.at then fill, edge = "g", "m"
            elseif r >= n then fill, edge = "l", "c"
            elseif r > 0 then fill, edge = "c", (st == "open" and blink) and "g" or "l"
            elseif st == "open" then fill, edge = "d", blink and "g" or "m"
            elseif st == "poor" then fill, edge = "u", "t"
            elseif st == "locked" then fill, edge = "o", "r"
            else fill, edge = "o", "k" end
            if net.sel == row.id or S.hover.netNode == row.id then
                color("w")
                love.graphics.circle("line", x + 0.5, y + 0.5, rad + 2)
            end
            -- A rank just grown rings out from it.
            local grew = net.grew[row.id]
            if grew and now - grew < 0.5 then
                color("l")
                love.graphics.circle("line", x + 0.5, y + 0.5, rad + 2 + (now - grew) * 16)
            end
            color(edge)
            love.graphics.circle("fill", x + 0.5, y + 0.5, rad + 1)
            -- Fully grown, a second ring.
            if icons and r >= n and row.at then
                color("c")
                love.graphics.circle("fill", x + 0.5, y + 0.5, rad)
                color(fill)
                love.graphics.circle("fill", x + 0.5, y + 0.5, rad - 1)
            else
                color(fill)
                love.graphics.circle("fill", x + 0.5, y + 0.5, rad)
            end
            if icons then
                drawIcon(row, st, r, x, y, rad)
                if st == "locked" then
                    -- A padlock on its edge.
                    local lx, ly = x + floor(rad * 0.55), y + floor(rad * 0.45)
                    color("o"); love.graphics.rectangle("fill", lx - 1, ly - 3, 7, 8)
                    color("r"); love.graphics.rectangle("fill", lx, ly, 5, 4)
                    love.graphics.rectangle("line", lx + 1.5, ly - 1.5, 2, 2)
                end
            elseif st == "locked" then
                color("r")
                love.graphics.rectangle("fill", x - 1, y - 1, 3, 3)
            end
            -- A pip a rank, under it: lit for those grown.
            if n > 1 then
                local w = n * 2 - 1
                for k2 = 1, n do
                    color(k2 <= r and "w" or "k")
                    love.graphics.rectangle("fill", x - floor(w / 2) + (k2 - 1) * 2, y + rad + 3, 1, 1)
                end
            end
            -- Names: the sprout's, every species' and seed's close up, and the one pointed at.
            local named = not row.at or (net.zoom >= 3 and (row.species or row.seed))
                or ((net.sel == row.id or S.hover.netNode == row.id) and net.zoom >= 2)
            if named then
                local s = row.name
                local k = (st == "full" or r > 0) and "w" or ((st == "open" or st == "poor") and "s" or "k")
                local tx, ty = x - floor(Font.width(s) / 2), y + rad + (n > 1 and 6 or 3)
                color("o")
                love.graphics.rectangle("fill", tx - 1, ty - 1, Font.width(s) + 2, 7)
                text(s, tx, ty, k)
            end
        end
    end
    love.graphics.setScissor()

    -- The top: BACK, the spores, how much is grown, and REGROW.
    local b = L.back
    box(b.x, b.y, b.w, b.h, S.hover.netBack and "n" or "u", S.hover.netBack and "t" or "k")
    text("BACK", b.x + floor((b.w - Font.width("BACK")) / 2), b.y + 4, "w")
    text(L.spores.s, L.spores.x + 2, L.spores.y + 4, "t")
    local all, spent = N.total(Profile.net)
    local pct = "NETWORK " .. floor(spent / all * 100) .. "%"
    text(pct, L.spores.x + L.spores.w + 8, L.spores.y + 4, "c")
    local g = L.regrow
    local sure = net.sure > now
    box(g.x, g.y, g.w, g.h, S.hover.netRegrow and "n" or "u", sure and "r" or "k")
    text(g.s, g.x + 4, g.y + 4, sure and "r" or "s")

    if L.panel then net.drawPanel(L) end

    -- The line along the bottom: what just happened, else how it works.
    local tip, k
    if net.note and net.note.t > now then tip, k = net.note.s, net.note.k
    elseif not L.panel then
        tip, k = say("CLICK A NODE TO READ IT, AGAIN TO GROW IT. DRAG TO LOOK ROUND. TAB: THE NEXT YOU CAN GROW",
            "TAP A NODE TO READ IT, AGAIN TO GROW IT. DRAG TO LOOK ROUND"), "s"
    end
    if tip then
        local y = L.panel and not wide() and L.panel.y - 11 or S.vh - S.inset.b - 10
        local mid = floor(L.area.x + L.area.w / 2)
        Draw.centred(tip, y, k, "o", mid)
    end
end

function net.drawPanel(L)
    local P = L.panel
    box(P.x, P.y, P.w, P.h, "u", "c")
    love.graphics.setScissor(P.x, P.y, P.w, P.h - 20)
    local y = P.y + 4
    for _, l in ipairs(net.lines(net.sel, P.w - 8)) do
        if l.gap then y = y + l.gap else text(l.s, P.x + 4, y, l.k); y = y + 7 end
    end
    love.graphics.setScissor()
    local b = P.button
    local s, can, k = buttonText(net.sel)
    box(b.x, b.y, b.w, b.h, (S.hover.netGrow and can) and "n" or (can and "d" or "o"), can and "l" or "k")
    text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 4, k)
end

--- pointing and keys ------------------------------------------------------------------------

function net.hover(mx, my)
    local L = net.layout()
    if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then S.hover.netBack = true return end
    if inside(mx, my, L.regrow.x, L.regrow.y, L.regrow.w, L.regrow.h) then S.hover.netRegrow = true return end
    if inside(mx, my, L.spores.x, L.spores.y, L.spores.w, L.spores.h) then S.hover.netSpores = true return end
    if L.panel then
        local b = L.panel.button
        if inside(mx, my, b.x, b.y, b.w, b.h) then S.hover.netGrow = true return end
        if inside(mx, my, L.panel.x, L.panel.y, L.panel.w, L.panel.h) then S.hover.netPanel = true return end
    end
    if not inside(mx, my, L.area.x, L.area.y, L.area.w, L.area.h) then return end
    -- The nearest node within a few pixels of the pointer.
    local best, bd
    for _, row in ipairs(D.NETWORK) do
        if Profile.nodeState(row.id) ~= "unknown" then
            local x, y = at(L, row.id)
            local d = (x - mx) ^ 2 + (y - my) ^ 2
            local reach = radius(row) + (S.touch and 6 or 3)
            if d <= reach * reach and (not bd or d < bd) then best, bd = row.id, d end
        end
    end
    S.hover.netNode = best
end

function net.under()
    local L = net.layout()
    local function rect(b) return function() return b.x, b.y, b.w, b.h end end
    if S.hover.netBack then return rect(L.back) end
    if S.hover.netRegrow then return rect(L.regrow) end
    if S.hover.netGrow then return rect(L.panel.button) end
end

function net.click(b)
    if b == 2 then
        if net.sel then net.sel = nil; sound("back") else net.close() end
        return
    end
    if S.hover.netBack then net.close() return end
    if S.hover.netRegrow then regrow() return end
    if S.hover.netSpores then
        -- Seven quick taps: spores for testing, on a phone with no F8.
        local now = flair.now()
        if now - net.taps.t > 1.2 then net.taps.n = 0 end
        net.taps.n, net.taps.t = net.taps.n + 1, now
        if net.taps.n >= 7 then net.taps.n = 0; testing() end
        return
    end
    if S.hover.netGrow then
        local _, can = buttonText(net.sel)
        if can then net.grow(net.sel) else deny() end
        return
    end
    if S.hover.netPanel then return end
    local id = S.hover.netNode
    if id and id == net.sel then
        local st = Profile.nodeState(id)
        if st == "open" then net.grow(id) elseif st ~= "full" then deny() end
    elseif id then
        net.sel = id
        sound("panel")
    elseif net.sel then
        net.sel = nil
        sound("back")
    end
end

local PAN = 24
function net.key(key)
    if key == "escape" or key == "backspace" then
        if net.sel then net.sel = nil; sound("back") else net.close() end
    elseif key == "left" then net.drag(net.getCam(), PAN, 0)
    elseif key == "right" then net.drag(net.getCam(), -PAN, 0)
    elseif key == "up" then net.drag(net.getCam(), 0, PAN)
    elseif key == "down" then net.drag(net.getCam(), 0, -PAN)
    elseif key == "=" or key == "+" or key == "kp+" then net.zoomBy(1)
    elseif key == "-" or key == "kp-" then net.zoomBy(-1)
    elseif key == "tab" then
        local id = nextOpen()
        if id then net.sel = id; net.centre(id); sound("select") else deny() end
    elseif key == "g" or key == "return" or key == "kpenter" or key == "space" then
        if net.sel then net.grow(net.sel) else deny() end
    elseif key == "f8" then testing()
    elseif key == "r" then regrow()
    end
end

return net
