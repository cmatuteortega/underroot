-- The Spore Bank's network: the screen next to the encyclopedia where spores
-- are spent. It is the title's ground seen close up: the sprout on it under
-- the night, and every node of D.NETWORK dug down into the soil under it
-- (src/network.lua lays them out), the hyphae between them lit where they
-- have grown, dim where they could, dark where they wait on something.
-- Buying a node's first rank grows its thread down from the one it grows
-- from, so the network digs deeper as it is bought.
--
-- Each node shows what it grows: the species (at the tier an upgrade node
-- brings), the seed, the enemy a field note is on, or a glyph for the
-- network's own numbers; dimmed while it waits, a silhouette behind a win.
-- Zoomed out the nodes are only dots, to see the whole of it at once.
--
-- Opened from the home screen it dives in: the home screen's own picture
-- at first (the sprout on its ground low on the screen, the name over it),
-- then the ground going up and the view zooming in on what is under it, the
-- title's own roots going dark in the soil as the network's come up; BACK
-- comes up out of it the same way.
--
-- Drag (or the arrows) to pan, the wheel, a pinch or + and - to zoom. A node
-- tapped is shown in the panel; tapped again, or its button, or G, grows a
-- rank. TAB picks the next node there are spores for.
--
-- The first time it is up, once the dive is down, the guide says what spores
-- are and points at a good first node (src/ui/guide.lua).
--
-- For testing: `love . --spores 100000` puts that many in the bank, as do F8
-- on this screen and seven quick taps on its spore count. REGROW (twice)
-- sells the whole network back for every spore it cost. ALL (or A) switches
-- the whole network on, every node grown, without spending or losing what
-- was bought: runs, the loadout and the encyclopedia play it all.

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
local Title = require "src.ui.title"
local Guide = require "src.ui.guide"
local Lang = require "src.lang"
local tr, trf = Lang.t, Lang.f

local floor, max, min = math.floor, math.max, math.min
local color, box, text, wrapLines, say, inside, wide =
    Draw.color, Draw.box, Draw.text, Draw.wrapLines, Draw.say, Draw.inside, Draw.wide
local sound, deny = flair.sound, flair.deny
local blit, CUT = Pixels.blit, Pixels.CUT

local net = {}
local clampCam

-- HUD pixels a step out from the sprout, at each zoom: under ICONS the nodes
-- are dots only, from NAMES each species and seed is named. A pinch, the
-- wheel or + and - go a step at a time.
net.STEPS = { 12, 16, 22, 27, 31, 36, 40, 46 }
net.ICONS, net.NAMES = 22, 40
net.TESTING = 100000 -- what F8 and the seven taps put in the bank
net.SKY = 36 -- the most night over the ground, HUD pixels
net.DIVE_TIME, net.DIVE_STEP = 1.1, 6 -- how long the dive takes, and the step it starts from
net.TAKEOVER = 0.3 -- how far into the dive the title's roots give way to the network's
net.dive = nil -- the dive under way: { t0, out = true going back up }

net.cam = { x = 0, y = 0 } -- the pan, HUD pixels
net.zoom = 3
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
    if state == "locked" then return trf("???: WIN %s, THEN GROW IT ON THE NETWORK", level.name) end
    if state == "shut" then return trf("%s: GROW %s ON THE NETWORK FIRST", name, D.NET[row.at].name) end
    return trf("%s: GROW IT ON THE NETWORK, %s SPORES. YOU HAVE %s", name, N.price(Profile.ranks(), row.id), Profile.spores)
end

-- How many nodes there are spores for now: the menu's button shows it.
function net.ready()
    local n = 0
    for _, row in ipairs(D.NETWORK) do if Profile.nodeState(row.id) == "open" then n = n + 1 end end
    return n
end

-- Opened from the home screen or the loadout; with `id` (a species or seed),
-- on the node it grows on.
function net.open(id)
    net.back = S.menu == "loadout" and "loadout" or nil
    net.dive = (S.menu == "home" and not S.script) and { t0 = flair.now() } or nil
    S.menu = "network"
    net.sel, net.sure = nil, 0
    if id then
        local row = Profile.nodeOf(id)
        if row then net.sel = row.id; net.centre(row.id) end
    else
        -- The sprout at the top under a strip of sky, the way the title has
        -- it, and across, halfway to the shallowest node there are spores
        -- for, so both are on the screen; lower if that node is out of sight.
        local near
        for _, row in ipairs(D.NETWORK) do
            if Profile.nodeState(row.id) == "open" and (not near or N.layout()[row.id].depth < N.layout()[near].depth) then
                near = row.id
            end
        end
        net.cam.x, net.cam.y = 0, 1e9
        local step = net.STEPS[net.zoom]
        if near then
            local p = N.layout()[near]
            net.cam.x = -p.x * step / 2
            net.cam.y = floor(net.layout().area.h / 2 - (p.y + 2) * step)
        end
        clampCam()
    end
    sound("panel")
end

function net.close()
    sound("back")
    if net.back == "loadout" and S.pick then S.menu = "loadout"
    elseif S.script then S.openHome()
    else net.sel, net.dive = nil, { t0 = flair.now(), out = true } end
end

local function smooth(f) return f * f * (3 - 2 * f) end

-- Called as each frame is drawn: the dive in done, the network is up; back
-- up at the top, it is the home screen again, its choices coming up one by
-- one as they do after the title. That last frame is still drawn here, as
-- the top of the dive (the dive is kept, ended, so it is): never the
-- network's own view for a frame between.
function net.diving()
    local d = net.dive
    if not d or d.over or flair.now() - d.t0 < net.DIVE_TIME then return end
    if d.out then
        d.over = true
        Title.down = flair.now() - Title.DROP_TIME
        S.openHome()
    else
        net.dive = nil
    end
end

-- HUD pixels a step out, as zoomed and as far as the dive has got: from the
-- dive's own step, as far in again each moment, to the zoom's.
function net.step(e)
    local step = net.STEPS[net.zoom]
    if not e then return step end
    return net.DIVE_STEP * (step / net.DIVE_STEP) ^ e
end

--- where things are ---------------------------------------------------------------------------

local function panelWidth() return wide() and min(150, floor(S.vw * 0.36)) or S.vw - S.inset.l - S.inset.r - 6 end

function net.layout()
    local L = { back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 } }
    local rs = tr(net.sure > flair.now() and "SURE? ALL BACK" or "REGROW")
    L.regrow = { s = rs, w = Font.width(rs) + 8, h = 12, y = S.inset.t + 4 }
    L.regrow.x = S.vw - S.inset.r - 4 - L.regrow.w
    local as = tr(Profile.all and "ALL: ON" or "ALL: OFF")
    L.all = { s = as, w = Font.width(as) + 8, h = 12, y = S.inset.t + 4 }
    L.all.x = L.regrow.x - 5 - L.all.w
    L.spores = { x = L.back.x + L.back.w + 6, y = S.inset.t + 4, h = 12 }
    L.spores.s = trf("SPORES %s", Profile.spores)
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
    L.sky = L.area -- what the night and the ground fill
    local d = net.dive
    if d then
        -- From where the home screen has the sprout to where the network has it.
        local e = (flair.now() - d.t0) / net.DIVE_TIME
        e = smooth(max(0, min(1, e)))
        if d.out then e = 1 - e end
        local _, low = Title.ground()
        local hx = floor(S.vw / 2)
        L.cx = floor(hx + (L.cx - hx) * e + 0.5)
        L.cy = floor(low + (L.cy - low) * e + 0.5)
        L.step = net.step(e)
        L.e, L.sky = e, { x = 0, y = 0, w = S.vw, h = S.vh }
    end
    return L
end

-- Where a node is on the screen.
local function at(L, id)
    local p = N.layout()[id]
    return floor(L.cx + p.x * L.step + 0.5), floor(L.cy + p.y * L.step + 0.5)
end

-- Zoomed in far enough for pictures, and for names.
local function icons(L) return L.step >= net.ICONS end
local function names(L) return L.step >= net.NAMES end

-- A node's socket: a dot zoomed out, room for its picture zoomed in, the
-- sprout's biggest and a species' or seed's bigger than the rest.
local function radius(L, row)
    local step = L.step
    local k = not row.at and 1 or ((row.species or row.seed) and 2 or 3)
    if not icons(L) then return min(({ 6, 4, 3 })[k], max(1, floor(step / 4))) end
    return floor(step * ({ 0.42, 0.355, 0.29 })[k])
end

-- The pan that puts a node in the middle of the free ground.
function net.centre(id)
    net.cam.x, net.cam.y = 0, 0
    local L = net.layout()
    local x, y = at(L, id)
    net.cam.x = L.area.x + L.area.w / 2 - x
    net.cam.y = L.area.y + L.area.h / 2 - y
    clampCam()
end

-- Kept so the network cannot be dragged out of sight: the middle of the
-- screen stays over it, and the ground no lower than a strip of sky under
-- the top (`net.SKY`, HUD pixels), room for the sprout standing on it.
function clampCam()
    local step, b = net.STEPS[net.zoom], (N.layout() and N.bounds)
    local area = net.layout().area
    net.cam.x = max(-b.r * step, min(-b.l * step, net.cam.x))
    -- All of it across the screen: in the middle of it.
    if (b.r - b.l + 2) * step <= area.w then net.cam.x = -floor((b.l + b.r) / 2 * step) end
    local h = area.h
    local top = net.SKY - floor(h / 2)
    net.cam.y = min(top, max(-b.bottom * step, net.cam.y))
end

function net.getCam() return { x = net.cam.x, y = net.cam.y } end
function net.drag(from, dx, dy)
    if net.dive then return end
    net.cam.x, net.cam.y = from.x + dx, from.y + dy
    clampCam()
end

-- Zoomed a step in (+1) or out (-1), about the middle of the screen or
-- about (fx, fy) on it, HUD pixels: what is there stays there. True if it did.
function net.zoomBy(d, fx, fy)
    if net.dive then return false end
    local z = max(1, min(#net.STEPS, net.zoom + d))
    if z == net.zoom then return false end
    local f = net.STEPS[z] / net.STEPS[net.zoom]
    local L = net.layout()
    local mx, my = L.area.x + L.area.w / 2, L.area.y + L.area.h / 2
    fx, fy = (fx or mx) - mx, (fy or my) - my
    net.cam.x, net.cam.y = fx - (fx - net.cam.x) * f, fy - (fy - net.cam.y) * f
    net.zoom = z
    clampCam()
    sound("zoom")
    return true
end

-- The whole network switched on or off.
function net.toggleAll()
    Profile.setAll(not Profile.all)
    sound(Profile.all and "on" or "off")
    net.note = { s = tr(Profile.all and "THE WHOLE NETWORK IS ON: EVERY NODE GROWN" or "THE NETWORK IS AS GROWN AGAIN"),
        k = Profile.all and "g" or "t", t = flair.now() + 2.5 }
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

-- "4.5 > 5.1": now, and at the next rank (nil when it is full), with as
-- many places as it takes for a rank to be seen to move them, up to two.
-- Never how far it goes in the end: that is for growing it to find out.
-- `pct` shows them as a part of a hundred.
local function pair(now, nxt, pct)
    local m = pct and 100 or 1
    local function show(v, places)
        local s = string.format("%." .. places .. "f", v * m)
        if places > 0 then s = s:gsub("0+$", ""):gsub("%.$", "") end
        return s .. (pct and "%" or "")
    end
    for places = 0, 2 do
        local a = show(now, places)
        if not nxt then
            if places == 2 or now * m * 10 ^ places == floor(now * m * 10 ^ places) then return a end
        else
            local b = show(nxt, places)
            if a ~= b or places == 2 then return a .. " > " .. b end
        end
    end
end

local function nowNext(mode, full, row, r)
    local nxt = r < N.ranks(row) and N.scale(mode, full, N.factor(row, r + 1)) or nil
    return pair(N.scale(mode, full, N.factor(row, r)), nxt)
end

-- The same for what the field notes grow, read off the whole network: two
-- of its nodes multiply into one number, `get` (N.vs or N.loot) for a kind.
local function nowNextNotes(get, kind, row, r)
    local ranks = {}
    for k, v in pairs(Profile.ranks()) do ranks[k] = v end
    local now, nxt = get(N.grown(ranks), kind)
    if r < N.ranks(row) then
        ranks[row.id] = r + 1
        nxt = get(N.grown(ranks), kind)
    end
    return pair(now, nxt, true)
end

local function kindOf(row)
    if not row.at then return tr("THE SPROUT") end
    if row.species then return trf("SPECIES: %s", D.TOWER[row.species].role) end
    if row.tower then return D.TOWER[row.tower].name end
    if row.up then return trf("UPGRADES: %s", D.TOWER[row.up[1]].name) end
    if row.seed then return tr("SEED") end
    if row.vs or row.loot then return tr("FIELD NOTES") end
    if row.mutations then return tr("MUTATIONS") end
    if row.slots then return tr("THE LOADOUT") end
    return tr("THE NETWORK")
end

-- A node's panel, as lines { s, k } `w` wide.
function net.lines(id, w)
    local row = D.NET[id]
    local r, n = N.rank(Profile.ranks(), id), N.ranks(row)
    local out = {}
    local function add(s, k) for _, l in ipairs(wrapLines(s, w)) do out[#out + 1] = { s = l, k = k } end end
    local function gap() out[#out + 1] = { gap = 3 } end
    add(row.name, "w")
    add(kindOf(row), "t")
    if not row.free then
        local s = tr(r > 0 and "GROWN" or "NOT GROWN")
        if n > 1 then s = r >= n and trf("RANK %s, FULLY GROWN", r) or trf("RANK %s > %s", r, r + 1) end
        add(s, r >= n and "g" or "l")
    end
    gap()
    add(row.blurb, "s")
    if row.species then gap(); add(D.TOWER[row.species].about, "s") end
    if row.seed then gap(); add(D.SEED[row.seed].about, "s") end
    if row.tower then
        gap()
        local d = D.TOWER[row.tower]
        for _, k in ipairs(row.stats) do
            local name = tr(NAME[k] or k:upper())
            if type(d[k]) == "number" then
                add(name .. " " .. nowNext(N.MODE[k] or "more", d[k], row, r), "l")
            else
                local nxt = r < n and N.factor(row, r + 1) or nil
                add(trf("%s, FROM ITS UPGRADES: %s", name, pair(N.factor(row, r), nxt, true)), "l")
            end
        end
    end
    if row.world then
        gap()
        local w2 = WORLD[row.world]
        add(tr(w2[1]) .. " " .. nowNext(N.WORLD[row.world], w2[2], row, r), "l")
        if row.world == "pulse" then
            local function back(rr) return floor(N.scale("less", D.PULSE.cooldown, N.factor(row, rr)) + 0.5) .. "S" end
            add(trf("COMES BACK IN %s", back(r)) .. (r < n and (" > " .. back(r + 1)) or ""), "l")
        end
    end
    local kinds = row.vs or row.loot
    if kinds then
        gap()
        if row.vs then add(trf("DAMAGE TO THEM %s", nowNextNotes(N.vs, kinds[1], row, r)), "l") end
        if row.loot then add(trf("THEIR BODIES WORTH %s", nowNextNotes(N.loot, kinds[1], row, r)), "l") end
        local met = {}
        for _, k in ipairs(kinds) do
            if Profile.seen[k] and not D.ENEMIES[k].segment then met[#met + 1] = D.ENEMIES[k].name end
        end
        if #met > 0 then add(trf("MET: %s", table.concat(met, ", ")), "s") end
    end
    if row.up then
        gap()
        local up = D.TOWER[row.up[1]].up[row.up[2]]
        -- What is grown, and the next; not what lies past it.
        for tier = 1, min(2, r + 1) do add((tier == 1 and "I  " or "II ") .. up[tier].name, tier <= r and "g" or "k") end
    end
    if row.mutations then
        gap()
        for k, m in ipairs(row.mutations) do
            for _, mm in ipairs(D.MUTATIONS) do
                if mm.id == m and (row.free or k <= r + 1) then
                    add(mm.name, k <= r and "g" or "k")
                    add(mm.blurb, k <= r and "s" or "k")
                end
            end
        end
    end
    if row.slots then
        gap()
        local now = N.slots(Profile.grown())
        add(trf("SPECIES ON A RUN %s", now) .. (r < n and now < row.slots and (" > " .. row.slots) or ""), "l")
    end
    if row.pulse then gap(); add(tr("THE PULSE ON THE TOOLBAR: A SURGE TO ANY FED NODE, EVERY TOWER ON THE WAY OVERCHARGED"), "s") end
    return out
end

-- What the panel's button says, and whether it can be pressed.
local function buttonText(id)
    local state, level = Profile.nodeState(id)
    local row = D.NET[id]
    if Profile.all and not row.free then return tr("ALL ON: SWITCH IT OFF TO GROW IT"), false, "g" end
    if state == "full" then return tr(row.free and "THERE FROM THE START" or "FULLY GROWN"), false, "g" end
    if state == "open" then return say("G: ", "") .. trf("GROW IT: %s SPORES", N.price(Profile.ranks(), id)), true, "l" end
    if state == "poor" then return trf("%s SPORES. YOU HAVE %s", N.price(Profile.ranks(), id), Profile.spores), false, "r" end
    if state == "shut" then return trf("GROW %s FIRST", D.NET[row.at].name), false, "k" end
    if state == "locked" then return trf("WIN %s FIRST", level.name), false, "r" end
    return "???", false, "k"
end

--- growing ---------------------------------------------------------------------------------

local function say2(s, k) net.note = { s = s, k = k or "l", t = flair.now() + 2.5 } end

function net.grow(id)
    local row = D.NET[id]
    if not Profile.buy(id) then deny() return false end
    net.grew[id] = flair.now()
    sound((row.species or row.seed) and "unlock" or "grow")
    local r = N.rank(Profile.ranks(), id)
    if r >= N.ranks(row) then say2(trf("%s FULLY GROWN", row.name), "g") else say2(trf("%s: RANK %s", row.name, r), "l") end
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
    say2(trf("+%s SPORES, FOR TESTING", net.TESTING), "t")
end

local function regrow()
    if net.sure > flair.now() then
        net.sure = 0
        local back = Profile.regrow()
        net.grew = {}
        sound("prune")
        say2(trf("THE NETWORK IS SOLD BACK: +%s SPORES", back), "t")
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
-- Each kind's bodies are one of its own, on its back.
for group, kind in pairs({ ants = "ant", shells = "pillbug", crawlers = "centi", fliers = "gnat", diggers = "springtail",
    soft = "slug" }) do
    NOTE["notes." .. group .. ".bodies"] = function() return M.corpse, { kind, FACE } end
end

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
-- A weak spot: a mark on it.
for _, row in ipairs(D.NETWORK) do
    if row.id:match("^notes%.%w+%.weak$") then
        GLYPH[row.id] = function(x, y, r, a, b)
            color(a); love.graphics.circle("line", floor(x) + 0.5, floor(y) + 0.5, r * 0.55)
            line(x, y - r * 0.8, x, y - r * 0.3); line(x, y + r * 0.3, x, y + r * 0.8)
            line(x - r * 0.8, y, x - r * 0.3, y); line(x + r * 0.3, y, x + r * 0.8, y)
            color(b); love.graphics.rectangle("fill", floor(x) - 1, floor(y) - 1, 2, 2)
        end
    end
end

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

-- A point `t` of the way along the hypha from (x0, y0) down to (x1, y1):
-- a root's curve, leaving the one it grows from heading down and a little
-- out, and coming into the next heading down, however far across it has to
-- go between.
local function along(x0, y0, x1, y1, t)
    local k, dx = (y1 - y0) * 0.6, (x1 - x0) * 0.2
    local u = 1 - t
    local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
    return x0 * a + (x0 + dx) * b + (x1 - dx) * c + x1 * d, y0 * a + (y0 + k) * b + (y1 - k) * c + y1 * d
end

-- The hypha drawn as far as `upto` (0 to 1) of the way, dotted or not;
-- where it got to.
local function thread(x0, y0, x1, y1, upto, dotted)
    local len = math.abs(x1 - x0) + math.abs(y1 - y0)
    if len < 1 then return end
    local steps = max(3, floor(len / 4))
    local px, py = x0, y0
    for k = 1, steps do
        local t = k / steps
        if t > upto + 1e-6 then break end
        local qx, qy = along(x0, y0, x1, y1, t)
        if not dotted or k % 2 == 0 then love.graphics.line(floor(px) + 0.5, floor(py) + 0.5, floor(qx) + 0.5, floor(qy) + 0.5) end
        px, py = qx, qy
    end
    return px, py
end

-- The sprout standing on the ground, as big as the zoom has the nodes.
local sprouts = {}
local function sproutPic(L)
    local s = max(1, min(2, floor(L.step / 24 * 4) / 4))
    sprouts[s] = sprouts[s] or (s == 1 and M.sprout(0) or M.scaled(s, M.sprout, 0))
    return sprouts[s]
end

-- Where the sprout's picture is, for pointing at it: its middle, and how far that reaches.
local function sproutSpot(L)
    local pic = sproutPic(L)
    local b = ink(pic)
    local x, y = at(L, D.NETWORK[1].id)
    local h = pic.oj - b.y
    return x, y - floor(h / 2), floor(max(b.w, h) / 2)
end

-- The night over the ground and the soil under it, as the title has them:
-- its stars, further off than the ground so they go by slower, and, at the
-- top of the dive, its own roots under the sprout, going dark in the soil as
-- the network's come up in their place. A few stones in the soil, where the
-- ground has them, to see it go by.
local function ground(L)
    local gy, V = L.cy, L.sky
    local _, low = Title.ground()
    local hx = floor(S.vw / 2)
    color("o")
    love.graphics.rectangle("fill", V.x, V.y, V.w, V.h)
    Title.stars(gy, floor((L.cx - hx) / 4), floor((gy - low) / 4), V.y)
    if gy >= V.y + V.h then return end
    local top = max(V.y, gy)
    color("u")
    love.graphics.rectangle("fill", V.x, top, V.w, V.y + V.h - top)
    -- A stone or none a patch of ground, the same ones wherever it is looked at.
    local cell = 24
    local ix0, iy0 = floor((V.x - L.cx) / cell), max(0, floor((top - gy) / cell))
    for iy = iy0, iy0 + floor(V.h / cell) + 1 do
        for ix = ix0, ix0 + floor(V.w / cell) + 1 do
            local h = (ix * 73856093 + iy * 19349663) % 1000
            if h < 230 then
                local x, y = L.cx + ix * cell + h % cell, gy + 6 + iy * cell + floor(h / 7) % cell
                color(h < 60 and "n" or "o")
                love.graphics.rectangle("fill", x, y, h % 3 + 1, 1 + h % 2)
            end
        end
    end
    if Title.threads and L.e and L.e < net.TAKEOVER then
        local gy0 = Title.ground()
        color(L.e < net.TAKEOVER / 2 and "c" or "d")
        for _, t in ipairs(Title.threads) do
            for _, q in ipairs(t) do
                love.graphics.rectangle("fill", L.cx + q.x - hx, gy + q.y - gy0, 1, 1)
            end
        end
    end
    color("n")
    love.graphics.rectangle("fill", V.x, gy, V.w, 2)
    color("m")
    love.graphics.rectangle("fill", V.x, gy - 1, V.w, 1)
end

local GROW_TIME = 0.7

function net.draw()
    net.diving()
    if not net.dive then Guide.network(net) end
    Guide.networkUpdate()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local L = net.layout()
    local now = flair.now()
    local states = {}
    for k, row in ipairs(D.NETWORK) do states[row.id] = { Profile.nodeState(row.id), k } end

    love.graphics.setScissor(L.sky.x, L.sky.y, L.sky.w, L.sky.h)
    ground(L)
    -- At the top of the dive, the title's roots are all there is under the
    -- sprout, as on the home screen; the network comes up in their place.
    if L.e and L.e < net.TAKEOVER / 2 then
        blit(sproutPic(L), L.cx, L.cy)
        love.graphics.setScissor()
        local _, low = Title.ground()
        Title.name(L.cy - low)
        return
    end
    -- The threads first, the dim ones under the lit.
    for pass = 1, 2 do
        for k, row in ipairs(D.NETWORK) do
            local st = states[row.id][1]
            if row.at and st ~= "unknown" then
                local r = N.rank(Profile.ranks(), row.id)
                local x0, y0 = at(L, row.at)
                local x1, y1 = at(L, row.id)
                local depth = N.layout()[row.id].depth
                if r == 0 and pass == 1 then
                    -- Not grown: dotted where it could be, faint where it waits.
                    color((st == "open" or st == "poor") and "k" or "o")
                    love.graphics.setLineWidth(1)
                    thread(x0, y0, x1, y1, 1, true)
                elseif r > 0 and pass == 2 then
                    local grew = net.grew[row.id]
                    local upto = (grew and r == 1) and min(1, (now - grew) / GROW_TIME) or 1
                    if upto < 1 then
                        color("k")
                        love.graphics.setLineWidth(1)
                        thread(x0, y0, x1, y1, 1, true)
                    end
                    color(r >= N.ranks(row) and "l" or "c")
                    love.graphics.setLineWidth((depth <= 2 and L.step >= net.ICONS) and 2 or 1)
                    local tx, ty = thread(x0, y0, x1, y1, upto)
                    love.graphics.setLineWidth(1)
                    if upto < 1 and tx then
                        -- The growing tip.
                        color("w")
                        love.graphics.rectangle("fill", floor(tx) - 1, floor(ty) - 1, 3, 3)
                    else
                        -- Nutrients running out along it, now and then.
                        local t = (now * 0.45 + k * 0.37) % 1.6
                        if t < 1 then
                            local px, py = along(x0, y0, x1, y1, t)
                            color("w")
                            love.graphics.rectangle("fill", floor(px), floor(py), 1, 1)
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
        if not row.at then
            -- The sprout, on the ground over it all; named when pointed at.
            local x, y = at(L, row.id)
            blit(sproutPic(L), x, y)
            if net.sel == row.id or S.hover.netNode == row.id then
                local sx, sy, reach = sproutSpot(L)
                color("w")
                love.graphics.circle("line", sx + 0.5, sy + 0.5, reach + 3)
                local tx, ty = x - floor(Font.width(row.name) / 2), sy - reach - 12
                color("o")
                love.graphics.rectangle("fill", tx - 1, ty - 1, Font.width(row.name) + 2, 7)
                text(row.name, tx, ty, "g")
            end
        elseif st ~= "unknown" then
            local x, y = at(L, row.id)
            local rad = radius(L, row)
            local r, n = N.rank(Profile.ranks(), row.id), N.ranks(row)
            local iconic = icons(L)
            local fill, edge
            if iconic then
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
            if iconic and r >= n and row.at then
                color("c")
                love.graphics.circle("fill", x + 0.5, y + 0.5, rad)
                color(fill)
                love.graphics.circle("fill", x + 0.5, y + 0.5, rad - 1)
            else
                color(fill)
                love.graphics.circle("fill", x + 0.5, y + 0.5, rad)
            end
            if iconic then
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
            -- A pip a rank grown, under it, and a dark one for the next while
            -- there is one: never how many there are in all.
            if n > 1 then
                local shown = min(n, r + 1)
                local w = shown * 2 - 1
                for k2 = 1, shown do
                    color(k2 <= r and "w" or "k")
                    love.graphics.rectangle("fill", x - floor(w / 2) + (k2 - 1) * 2, y + rad + 3, 1, 1)
                end
            end
            -- Names: the sprout's, every species' and seed's close up, and the one pointed at.
            local named = not row.at or (names(L) and (row.species or row.seed))
                or ((net.sel == row.id or S.hover.netNode == row.id) and iconic)
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

    -- Diving, the name goes up with the ground, and nothing else is up yet.
    if L.e then
        local _, low = Title.ground()
        Title.name(L.cy - low)
        return
    end

    -- The top: BACK, the spores, how much is grown, ALL and REGROW.
    local b = L.back
    box(b.x, b.y, b.w, b.h, S.hover.netBack and "n" or "u", S.hover.netBack and "t" or "k")
    text(tr("BACK"), b.x + floor((b.w - Font.width(tr("BACK"))) / 2), b.y + 4, "w")
    text(L.spores.s, L.spores.x + 2, L.spores.y + 4, "t")
    local all, spent = N.total(Profile.ranks())
    local pct = trf("NETWORK %s%%", floor(spent / all * 100))
    -- Left out on a screen too narrow for it.
    if L.spores.x + L.spores.w + 8 + Font.width(pct) < L.all.x - 4 then
        text(pct, L.spores.x + L.spores.w + 8, L.spores.y + 4, Profile.all and "g" or "c")
    end
    local a = L.all
    box(a.x, a.y, a.w, a.h, S.hover.netAll and "n" or (Profile.all and "d" or "u"), Profile.all and "g" or "k")
    text(a.s, a.x + 4, a.y + 4, Profile.all and "g" or "s")
    local g = L.regrow
    local sure = net.sure > now
    box(g.x, g.y, g.w, g.h, S.hover.netRegrow and "n" or "u", sure and "r" or "k")
    text(g.s, g.x + 4, g.y + 4, sure and "r" or "s")

    if L.panel then net.drawPanel(L) end

    -- The line along the bottom: what just happened, else how it works.
    local tip, k
    if net.note and net.note.t > now then tip, k = net.note.s, net.note.k
    elseif not L.panel then
        tip, k = tr(say("CLICK A NODE TO READ IT, AGAIN TO GROW IT. DRAG TO LOOK ROUND. TAB: THE NEXT YOU CAN GROW",
            "TAP A NODE TO READ IT, AGAIN TO GROW IT. DRAG TO LOOK ROUND")), "s"
    end
    if tip then
        local y = L.panel and not wide() and L.panel.y - 11 or S.vh - S.inset.b - 10
        local mid = floor(L.area.x + L.area.w / 2)
        Draw.centred(tip, y, k, "o", mid)
    end
    Guide.draw("network")
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
    if net.dive then return end
    if Guide.hover(mx, my, "network") then return end
    local L = net.layout()
    if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then S.hover.netBack = true return end
    if inside(mx, my, L.regrow.x, L.regrow.y, L.regrow.w, L.regrow.h) then S.hover.netRegrow = true return end
    if inside(mx, my, L.all.x, L.all.y, L.all.w, L.all.h) then S.hover.netAll = true return end
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
            local reach = radius(L, row)
            if not row.at then x, y, reach = sproutSpot(L) end
            local d = (x - mx) ^ 2 + (y - my) ^ 2
            reach = reach + (S.touch and 6 or 3)
            if d <= reach * reach and (not bd or d < bd) then best, bd = row.id, d end
        end
    end
    S.hover.netNode = best
end

function net.under()
    if S.hover.guide then return Guide.under("network") end
    local L = net.layout()
    local function rect(b) return function() return b.x, b.y, b.w, b.h end end
    if S.hover.netBack then return rect(L.back) end
    if S.hover.netRegrow then return rect(L.regrow) end
    if S.hover.netAll then return rect(L.all) end
    if S.hover.netGrow then return rect(L.panel.button) end
end

function net.click(b)
    if net.dive then return end
    if Guide.click("network") then return end
    if b == 2 then
        if net.sel then net.sel = nil; sound("back") else net.close() end
        return
    end
    if S.hover.netBack then net.close() return end
    if S.hover.netRegrow then regrow() return end
    if S.hover.netAll then net.toggleAll() return end
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
    if net.dive then return end
    if Guide.key(key, "network") then return end
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
    elseif key == "a" then net.toggleAll()
    end
end

return net
