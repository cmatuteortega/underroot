-- The six species grown deep in the network: the Fly Agaric, the Earthstar,
-- the Oyster Mushroom, the Bleeding Tooth, the Truffle and the Turkey Tail.

require "tests.love"
local C = require "tests.check"
local D = require "src.defs"
local World = require "src.world"
local Game = require "src.game"

local DEEP = { "agaric", "earthstar", "oyster", "tooth", "truffle", "turkey" }

local world
local function new()
    local lv = D.LEVEL.crack
    world = world or World.new(lv.map)
    local g = Game.new(world, lv, { dice = 1 })
    g.nutrients = 10000
    return g
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end

-- The pockets by how far they are from the sprout, nearest first.
local function byDistance(g)
    local list = {}
    for _, n in ipairs(g.nodes) do if not n.heart then list[#list + 1] = n end end
    table.sort(list, function(a, b) return dist(a, g.heart) < dist(b, g.heart) end)
    return list
end

-- A link grown at once.
local function link(g, a, b)
    local l = assert(g:grow(a, b), "could not link")
    l.state, l.grow = "alive", 1
    g:recompute()
    return l
end

-- A chain out from the sprout through the nearest pockets that reach each other.
local function chain(g, n)
    local list, out = byDistance(g), { g.heart }
    for _, p in ipairs(list) do
        if #out > n then break end
        if dist(out[#out], p) <= g:linkReach() then
            link(g, out[#out], p)
            out[#out + 1] = p
        end
    end
    assert(#out > n, "no chain that long")
    return out
end

-- An enemy standing at (x, z), on the trail tile nearest it.
local function at(g, kind, x, z)
    local c, r = g:nearestTrail(x, z, 0, 0)
    return g:spawnAt(kind, x, z, c, r)
end

return {
    { "each grows off a species already on the network, behind no level and no wave", function()
        for _, id in ipairs(DEEP) do
            local row = D.NET[id]
            C.yes(row and row.species == id, id .. " is on the network")
            C.no(row.won, id .. " waits on no level")
            C.no(D.TOWER[id].unlock, id .. " waits on no wave")
            local from = D.NET[row.at]
            C.yes(from and from.tower and D.NET[from.tower], id .. " grows off another species' branch")
            C.yes(row.price[1] > D.NET.needle.price[1], id .. " costs more than the needle")
        end
    end },

    { "every key on the toolbar is its own", function()
        local seen = {}
        for _, t in ipairs(D.TOWERS) do
            C.no(seen[t.key], t.id .. "'s key " .. t.key)
            seen[t.key] = true
        end
    end },

    { "a Fly Agaric shoots fliers and leaves walkers be", function()
        local g = new()
        local p = chain(g, 1)[2]
        local t = g:plant("agaric", p, 0)
        t.reserve, t.cool = 8, 0
        local ant = at(g, "ant", p.x + 10, p.z)
        local gnat = at(g, "gnat", p.x - 10, p.z)
        g:fire(p, t, D.TOWER.agaric, 0.01)
        C.eq(ant.hp, ant.maxHp, "the ant is not shot")
        C.yes(gnat.hp < gnat.maxHp, "the gnat is")
        C.yes((gnat.dazeT or 0) > 0, "and dazed")
    end },

    { "a Fly Agaric hits harder on a bridge", function()
        local g = new()
        local c = chain(g, 2)
        local p = c[2]
        local t = g:plant("agaric", p, 0)
        t.power = 1
        local gnat = at(g, "gnat", p.x, p.z)
        g:fling(p, t, D.TOWER.agaric, function(k) return g:stat(t, k) end, 1, 70, { gnat })
        local bridge = gnat.maxHp - gnat.hp
        C.eq(g:degree(p), 2, "two links")
        C.eq(bridge, D.TOWER.agaric.damage * D.TOWER.agaric.bridge, "x1.5")
    end },

    { "an Earthstar thumps a burrowed nymph twice as hard as a walker", function()
        local g = new()
        local p = chain(g, 1)[2]
        local t = g:plant("earthstar", p, 0)
        t.reserve, t.cool, t.power = 8, 0, 1
        g.phase = "wave"
        local ant = at(g, "ant", p.x + 6, p.z)
        local nymph = at(g, "cricket", p.x - 6, p.z)
        nymph.under, nymph.state = true, "tunnel"
        g:earthstar(p, t, function(k) return g:stat(t, k) end, 1, 1, 0.01)
        local d = D.TOWER.earthstar
        C.eq(ant.maxHp - ant.hp, d.damage, "the ant takes a thump")
        C.yes(ant.stun > 0, "and staggers")
        C.eq(nymph.maxHp - nymph.hp, d.damage * d.deep - D.ENEMIES.cricket.armor, "the nymph twice, through its armor")
    end },

    { "an Earthstar hears further down longer links", function()
        local g = new()
        local c = chain(g, 2)
        local t = g:plant("earthstar", c[2], 0)
        local len = 0
        for _, l in ipairs(c[2].links) do len = len + l.len end
        local d = D.TOWER.earthstar
        C.eq(g:towerRange(t), math.min(d.maxRange, d.range + d.perLen * len) * (t.reach or 1), "range by length")
    end },

    { "an Oyster Mushroom strips armor, and it grows back", function()
        local g = new()
        local knight = at(g, "knight", 0, 0)
        local base = g:armor(knight)
        g:dripOn(knight, { damage = 0, strip = 2, stripMax = 12, regrow = 0.5, hold = 0.35 })
        C.eq(g:armor(knight), base - 2, "two off")
        g:dripOn(knight, { damage = 0, strip = 2, stripMax = 12, regrow = 0.5, hold = 0.35 })
        C.eq(g:armor(knight), base - 4, "stacking")
        C.yes(knight.stun > 0, "held")
        knight.stun = 0
        g:move(knight, 2)
        C.eq(g:armor(knight), base - 3, "a point back in two seconds")
    end },

    { "an Oyster Mushroom goes for the toughest shell", function()
        local g = new()
        local p = chain(g, 1)[2]
        local t = g:plant("oyster", p, 0)
        local ant, knight = at(g, "ant", p.x, p.z), at(g, "knight", p.x, p.z)
        g:drip(p, t, D.TOWER.oyster, function(k) return g:stat(t, k) end, 1, 50, { ant, knight })
        C.eq(g.shots[#g.shots].target, knight, "the knight")
    end },

    { "a Bleeding Tooth saps its links: biters bleed and stick, mites die", function()
        local g = new()
        local c = chain(g, 1)
        local p = c[2]
        local t = g:plant("tooth", p, 0)
        t.hunger = nil
        g:recompute()
        local l = p.links[1]
        C.eq(l.sap, t, "its link is sapped")
        local ant = at(g, "ant", l.a.x, l.a.z)
        g:biteLink(l, 1, ant)
        C.eq(ant.maxHp - ant.hp, D.TOWER.tooth.sapHit, "the ant is hurt")
        C.yes((ant.stickT or 0) > 0 and (ant.bleedT or 0) > 0, "stuck and bleeding")
        local hp = ant.hp
        g:biteLink(l, 1, ant)
        C.eq(ant.hp, hp, "hurt once a link, not every bite")
        local mite = at(g, "mite", l.a.x, l.a.z)
        g:crush(l, mite)
        C.yes(mite.dead, "a mite dies on it")
    end },

    { "a Truffle's links are out of reach of all but a burrower", function()
        local g = new()
        local p = chain(g, 1)[2]
        g:plant("truffle", p, 0)
        local l = p.links[1]
        C.yes(l.buried, "buried")
        local ant = at(g, "ant", (l.a.x + l.b.x) / 2, (l.a.z + l.b.z) / 2)
        C.eq(g:linkNear(ant, 10), nil, "an ant on it finds nothing to chew")
        C.eq(#g:linksNear(ant.x, ant.z, 10), 0, "nor does a beetle")
        local nymph = at(g, "cricket", ant.x, ant.z)
        C.eq(g:cricketPrey(nymph, D.ENEMIES.cricket), l, "a nymph does")
    end },

    { "a Truffle pays interest, more each wave uncut, and a cut starts it over", function()
        local g = new()
        local p = chain(g, 1)[2]
        local t = g:plant("truffle", p, 0)
        local d = D.TOWER.truffle
        g.nutrients = 200
        g:payInterest()
        C.eq(g.nutrients, 200 + math.floor(200 * d.interest), "8% of the bank")
        g.nutrients = 200
        g:payInterest()
        C.eq(g.nutrients, 200 + math.floor(200 * (d.interest + d.perWave)), "+3% for a wave uncut")
        g.nutrients = 10000
        g:payInterest()
        C.eq(g.nutrients, 10000 + d.cap, "never more than its cap")
        g:cut(p.links[1])
        C.yes(t.cutWave, "its link cut")
        g:payInterest()
        C.eq(t.streak, 0, "the run starts over")
    end },

    { "a Turkey Tail hastens what grows round it, more for each species", function()
        local g = new()
        local c = chain(g, 3)
        g:plant("turkey", c[2], 0)
        local a = g:plant("puffer", c[3], 0)
        local b = g:plant("needle", c[4], 0)
        local d = D.TOWER.turkey
        -- Two species within its two links: the puffer and the needle.
        C.eq(a.haste, d.haste + d.perSpecies * 2, "the puffer")
        C.eq(b.haste, a.haste, "the needle, two links off")
        C.eq(a.shake, d.shake, "and they shake off stuns")
    end },
}
