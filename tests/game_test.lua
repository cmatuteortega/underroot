-- src/game.lua: the network and what grows on it, played without a screen.

require "tests.love"
local C = require "tests.check"
local D = require "src.defs"
local World = require "src.world"
local Game = require "src.game"

local worlds = {}
local function new(id, opts)
    local lv = D.LEVEL[id or "crack"]
    worlds[lv.id] = worlds[lv.id] or World.new(lv.map)
    local o = { dice = 1 }
    for k, v in pairs(opts or {}) do o[k] = v end
    return Game.new(worlds[lv.id], lv, o)
end

-- The pocket at tile (c, r).
local function pocket(g, c, r)
    for _, n in ipairs(g.nodes) do
        if n.pocket and n.pocket.c == c and n.pocket.r == r then return n end
    end
    error("no pocket at " .. c .. "," .. r)
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end

-- The pockets by how far they are from the sprout, nearest first.
local function byDistance(g)
    local list = {}
    for _, n in ipairs(g.nodes) do if not n.heart then list[#list + 1] = n end end
    table.sort(list, function(a, b) return dist(a, g.heart) < dist(b, g.heart) end)
    return list
end

-- Time passing between waves: links grow, nothing comes.
local function wait(g, seconds)
    for _ = 1, math.floor(seconds * 30) do g:update(1 / 30) end
end

-- A link grown at once, as the shots script grows them.
local function link(g, a, b)
    local l = assert(g:grow(a, b), "could not link")
    l.state, l.grow = "alive", 1
    g:recompute()
    return l
end

return {
    { "every level starts with its sprout, its pockets and its nutrients", function()
        for _, lv in ipairs(D.LEVELS) do
            local g = new(lv.id)
            C.yes(g.heart.heart, lv.id .. ": the first node is the sprout")
            C.eq(#g.nodes, #worlds[lv.id].pockets + 1, lv.id .. ": a node a pocket, and the sprout")
            C.eq(g.nutrients, lv.start + (D.SEEDS[1].start or 0), lv.id .. ": nutrients")
            C.eq(g.phase, "build", lv.id .. ": phase")
            C.yes(g.heart.conn, lv.id .. ": the sprout is fed")
        end
    end },

    { "a link grows out from the sprout, paid for, and feeds the pocket", function()
        local g = new()
        local p = byDistance(g)[1]
        local ok, cost = g:canLink(g.heart, p)
        C.yes(ok, "can link the nearest pocket")
        C.eq(cost, D.LINK.cost(dist(g.heart, p)), "what it costs")
        local before = g.nutrients
        local l = g:grow(g.heart, p)
        C.eq(g.nutrients, before - cost, "nutrients spent")
        C.eq(l.state, "grow", "growing")
        C.no(p.conn, "not fed until it arrives")
        wait(g, 8)
        C.eq(l.state, "alive", "arrived")
        C.yes(p.conn, "fed")
        C.eq(select(3, g:canLink(g.heart, p)), "ALREADY LINKED", "a second link")
    end },

    { "a link can only be so long, and only from what is fed", function()
        local g = new()
        local list = byDistance(g)
        local far = list[#list]
        C.yes(dist(g.heart, far) > g:linkReach(), "the farthest pocket is out of reach")
        C.eq(select(3, g:canLink(g.heart, far)), "TOO FAR", "too far")
        local a, b
        for _, x in ipairs(list) do
            for _, y in ipairs(list) do
                if x ~= y and not a and dist(x, y) <= g:linkReach() then a, b = x, y end
            end
        end
        C.eq(select(3, g:canLink(a, b)), "NOT CONNECTED TO THE SPROUT", "two unfed pockets")
        g.nutrients = 0
        C.eq(select(3, g:canLink(g.heart, list[1])), "NOT ENOUGH NUTRIENTS", "too poor")
    end },

    { "a cut link starves what is beyond it until it is regrown", function()
        local g = new()
        local p = byDistance(g)[1]
        local l = link(g, g.heart, p)
        g:cut(l)
        C.eq(l.state, "cut", "cut")
        C.no(p.conn, "starved")
        C.eq(g.stats.cuts, 1, "counted")
        g.nutrients = 1000
        C.yes(g:repair(l), "paid to regrow")
        wait(g, D.LINK.regrow + 1)
        C.eq(l.state, "alive", "regrown")
        C.yes(p.conn, "fed again")
    end },

    { "pruning a living link pays back its share", function()
        local g = new()
        local l = link(g, g.heart, byDistance(g)[1])
        local before = g.nutrients
        g:prune(l)
        C.eq(g.nutrients, before + math.floor(l.cost * D.LINK.prune), "refund")
        C.eq(#g.links, 0, "gone")
    end },

    { "a fruiting body is built, upgraded and cleared", function()
        local g = new()
        local p = byDistance(g)[1]
        link(g, g.heart, p)
        g.nutrients = 1000
        local t = g:build("puffer", p)
        C.yes(t, "built")
        C.eq(g.nutrients, 1000 - D.TOWER.puffer.cost, "paid")
        C.no(g:canBuild("needle", p), "one to a pocket")
        local row = D.TOWER.puffer.up[1][1]
        C.yes(g:upgrade(t, 1), "upgraded")
        C.eq(t.tier, 1, "tier")
        for k, v in pairs(row) do
            if type(v) == "number" and k ~= "cost" then C.eq(g:stat(t, k), v, "the upgrade's " .. k) end
        end
        C.no(g:canUpgrade(t, 2), "the other branch is shut")
        local spent = t.spent
        local before = g.nutrients
        g:sell(p)
        C.eq(p.tower, nil, "cleared")
        C.eq(g.nutrients, before + math.floor(spent * D.SELL), "paid back")
    end },

    { "a species not brought, or not open yet, cannot be built", function()
        local g = new("crack", { loadout = { "puffer" } })
        local p = byDistance(g)[1]
        link(g, g.heart, p)
        g.nutrients = 1000
        C.eq(select(2, g:canBuild("needle", p)), "LEFT AT HOME", "left at home")
        local late
        for _, t in ipairs(D.TOWERS) do if (t.unlock or 0) > 0 then late = t.id break end end
        g = new("crack")
        p = byDistance(g)[1]
        link(g, g.heart, p)
        g.nutrients = 1000
        C.yes(select(2, g:canBuild(late, p)):find("^UNLOCKS AFTER WAVE"), late .. " waits")
    end },

    { "a closed loop of living links is a fairy ring", function()
        local g = new()
        g.nutrients = 2000
        local function at(c, r) return pocket(g, c, r) end
        link(g, g.heart, at(12, 6))
        link(g, at(12, 6), at(12, 9))
        link(g, at(12, 9), at(11, 8))
        link(g, at(11, 8), at(8, 9))
        link(g, at(8, 9), at(6, 7))
        link(g, at(6, 7), at(7, 5))
        C.eq(#g.rings, 0, "no ring while it is open")
        link(g, at(7, 5), at(10, 6))
        link(g, at(10, 6), at(11, 8))
        C.yes(#g.rings > 0, "the loop closes a ring")
        local inside = false
        for _, n in ipairs(g.nodes) do if n.ringed then inside = true end end
        C.yes(inside, "the ring's nodes know it")
    end },

    { "a wave comes in, and the run is lost when the sprout dies", function()
        local g = new()
        g:startWave()
        C.eq(g.phase, "wave", "phase")
        C.eq(g.wave, 1, "wave")
        wait(g, 120)
        C.yes(g.stats.kills == 0 and g.heartHp < g.heartMax, "unopposed, they reach the sprout")
        for _ = 1, 30 * 600 do
            if g.phase ~= "wave" and g.phase ~= "build" then break end
            if g.phase == "build" then g:startWave() end
            g:update(1 / 30)
        end
        C.eq(g.phase, "lost", "with nothing grown, the sprout wilts")
    end },

    { "the first levels bring the weathers one at a time", function()
        local first = {}
        for _, lv in ipairs(D.LEVELS) do
            for _, w in ipairs(D.weathersOf(lv)) do first[w] = first[w] or lv.id end
        end
        C.eq(first.rain, "crack", "rain on the Crack")
        C.eq(first.night, "flowerpot", "night on the Flowerpot")
        C.eq(first.drought, "shed", "drought on the Shed Floor")
        C.eq(first.frost, "log", "frost on the Rotting Log")
        C.list(D.weathersOf(D.LEVEL.crack), { "rain" }, "the Crack has only rain")
    end },

    { "endless brings only the weathers its level does", function()
        local g = new("crack")
        g.phase = "won"
        g:goEndless()
        for k = 1, 60 do
            local w = g:endlessWave(g.endlessFrom + k)
            C.yes(not w.weather or w.weather == "rain", "wave " .. k .. ": " .. tostring(w.weather))
        end
    end },

    { "the pulse is on the toolbar only once it is grown", function()
        local N = require "src.network"
        local Toolbar = require "src.ui.toolbar"
        local function has(g)
            Toolbar.layTools(g)
            for _, b in ipairs(Toolbar.BUTTONS) do if b.mode == "pulse" then return true end end
            return false
        end
        C.no(has(new("crack", { net = N.grown({}) })), "a new network")
        C.yes(has(new("crack", { net = N.grown({ hyphae = 1, pulse = 1 }) })), "grown")
        C.yes(has(new("crack")), "the whole network")
    end },
}
