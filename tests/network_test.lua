-- src/network.lua and its rows in D.NETWORK: every node can be reached, a
-- full network plays the game as defs writes it, and an empty one holds it back.

require "tests.love"
local C = require "tests.check"
local D = require "src.defs"
local N = require "src.network"
local World = require "src.world"
local Game = require "src.game"

return {
    { "every node grows from one that is there, and the ids are their own", function()
        local seen = {}
        for k, row in ipairs(D.NETWORK) do
            C.no(seen[row.id], "one id, one node: " .. row.id)
            seen[row.id] = true
            if k == 1 then C.eq(row.at, nil, "the sprout grows from nothing")
            else C.yes(row.at and seen[row.at], row.id .. " grows from a node before it") end
            C.yes(row.free or (row.price and #row.price > 0), row.id .. " has a price or is free")
            if row.from then C.yes(row.from > 0 and row.from < 1, row.id .. ": its numbers start held back") end
            if row.won then C.yes(D.LEVEL[row.won], row.id .. " waits on a level there is") end
        end
    end },

    { "everything is on it: each species, seed, upgrade and mutation", function()
        local g = N.grown(N.everything())
        for _, t in ipairs(D.TOWERS) do
            C.yes(g.species[t.id], t.id .. " is grown")
            for b = 1, 2 do C.eq(N.tier(g, t.id, b), 2, t.id .. " branch " .. b) end
        end
        for _, sd in ipairs(D.SEEDS) do C.yes(g.seeds[sd.id], sd.id .. " is grown") end
        for _, m in ipairs(D.MUTATIONS) do C.yes(g.mutations[m.id], m.id .. " can be offered") end
        C.yes(g.pulse, "the pulse")
    end },

    { "fully grown, every number is what defs writes", function()
        local g = N.grown(N.everything())
        for _, t in ipairs(D.TOWERS) do
            for k, v in pairs(t) do
                if type(v) == "number" then C.eq(N.value(g, t.id, k, v), v, t.id .. "." .. k) end
            end
        end
        for key in pairs(N.WORLD) do C.eq(N.world(g, key, 7), 7, key) end
        for kind in pairs(D.ENEMIES) do
            C.eq(N.vs(g, kind), 1, "against " .. kind)
            C.eq(N.loot(g, kind), 1, kind .. "'s body")
        end
    end },

    { "a run on a full network is the same run as one given none", function()
        local lv = D.LEVEL.crack
        local a = Game.new(World.new(lv.map), lv, { dice = 3 })
        local b = Game.new(World.new(lv.map), lv, { dice = 3, net = N.grown(N.everything()) })
        C.eq(b.nutrients, a.nutrients, "nutrients to start")
        C.eq(b.heartMax, a.heartMax, "the sprout")
        C.eq(b:linkHp(), a:linkHp(), "a link")
        C.eq(b:towerCost("mortar"), a:towerCost("mortar"), "a mortar's cost")
        C.eq(b:pulseCooldown(), a:pulseCooldown(), "the pulse")
    end },

    { "an empty network brings only the puffer, held back, with no upgrades", function()
        local lv = D.LEVEL.crack
        local g = Game.new(World.new(lv.map), lv, { dice = 3, net = N.grown({}) })
        C.yes(g:brought("puffer"), "the puffer")
        C.no(g:brought("needle"), "not the needle")
        C.no(g:hasPulse(), "no pulse")
        C.yes(g.heartMax < lv.heart, "a weaker sprout")
        C.yes(g:towerCost("puffer") > D.TOWER.puffer.cost, "a dearer puffer")
        local t = { kind = "puffer", tier = 0 }
        C.yes(g:stat(t, "damage") < D.TOWER.puffer.damage, "a weaker puffer")
        C.yes(g:stat(t, "every") > D.TOWER.puffer.every, "a slower one")
        C.eq(g:stat(t, "range"), D.TOWER.puffer.range, "but as long a reach")
        C.eq(#g:upgrades(t), 0, "and no upgrades")
    end },

    { "each rank brings a number nearer, and the last brings it all the way", function()
        local row = D.NET["puffer.power"]
        local last
        for r = 0, #row.price do
            local v = N.value(N.grown({ ["puffer.power"] = r }), "puffer", "damage", D.TOWER.puffer.damage)
            if last then C.yes(v > last, "rank " .. r .. " hits harder") end
            last = v
        end
        C.eq(last, D.TOWER.puffer.damage, "all the way")
    end },

    { "every rank of a species' node moves a number the game reads", function()
        local lv = D.LEVEL.crack
        for _, row in ipairs(D.NETWORK) do
            if row.tower then
                local d = D.TOWER[row.tower]
                -- The species as it stands and at every tier of every branch.
                local looks = { { kind = row.tower, tier = 0 } }
                for b = 1, 2 do for tier = 1, 2 do looks[#looks + 1] = { kind = row.tower, branch = b, tier = tier } end end
                local last
                for r = 0, #row.price do
                    local g = Game.new(World.new(lv.map), lv, { dice = 3, net = N.grown({ [row.id] = r }) })
                    local now = {}
                    for _, k in ipairs(row.stats) do
                        for _, t in ipairs(looks) do
                            local v = k == "cost" and g:towerCost(row.tower) or g:stat(t, k)
                            if type(v) == "number" then now[#now + 1] = v end
                        end
                    end
                    if last then
                        local moved = false
                        for n, v in ipairs(now) do if v ~= last[n] then moved = true end end
                        C.yes(moved, row.id .. " rank " .. r .. " changes something")
                    end
                    last = now
                end
                for _, k in ipairs(row.stats) do
                    local any = type(d[k]) == "number"
                    for b = 1, 2 do for tier = 1, 2 do any = any or type(d.up[b][tier][k]) == "number" end end
                    C.yes(any, row.id .. ": " .. k .. " is a number the species has")
                end
            end
        end
    end },

    { "a shelf's shade and a needle's dead end grow with the network", function()
        local lv = D.LEVEL.crack
        local function shade(ranks)
            local g = Game.new(World.new(lv.map), lv, { dice = 3, net = N.grown(ranks) })
            g.mats = { { kind = "shelf", tier = 0, x = 0, z = 0 } }
            return g:shield({ a = { x = -5, z = 0 }, b = { x = 5, z = 0 } })
        end
        C.yes(shade({}) > shade({ ["shelf.guard"] = 1 }), "a rank of wide shade shields more")
        C.eq(shade(N.everything()), D.TOWER.shelf.shieldMul, "fully grown, as defs writes")
        local t = { kind = "needle", tier = 0 }
        local function deadEnd(ranks)
            return Game.new(World.new(lv.map), lv, { dice = 3, net = N.grown(ranks) }):stat(t, "deadEnd")
        end
        C.yes(deadEnd({}) < deadEnd({ ["needle.power"] = 1 }), "a rank of harder needles")
    end },

    { "field notes: every rank hits or feeds more, the whole branch all the way", function()
        local ranks = {}
        for _, row in ipairs(D.NETWORK) do
            if row.vs or row.loot then
                local kind = (row.vs or row.loot)[1]
                local get = row.vs and N.vs or N.loot
                for r = 1, #row.price do
                    local before = get(N.grown(ranks), kind)
                    ranks[row.id] = r
                    C.yes(get(N.grown(ranks), kind) > before, row.id .. " rank " .. r)
                end
            end
        end
        for kind in pairs(D.ENEMIES) do
            C.eq(N.vs(N.grown(ranks), kind), 1, "against " .. kind)
            C.eq(N.loot(N.grown(ranks), kind), 1, kind .. "'s body")
            C.yes(N.vs(N.grown({}), kind) < 1, kind .. " is hit softer knowing nothing")
        end
        local lv = D.LEVEL.crack
        local g = Game.new(World.new(lv.map), lv, { dice = 3, net = N.grown({}) })
        C.yes(g:corpseValue("ant") < D.ENEMIES.ant.corpse, "an ant's body is worth less knowing nothing")
    end },

    { "every node has a place on the screen", function()
        local places = N.layout()
        for _, row in ipairs(D.NETWORK) do C.yes(places[row.id], row.id) end
    end },

    { "the network digs down: each node under what it grows from, none in a row on top of another", function()
        local places = N.layout()
        local rows = {}
        for _, row in ipairs(D.NETWORK) do
            local p = places[row.id]
            if row.at then C.yes(p.y > places[row.at].y, row.id .. " is under " .. row.at) end
            rows[p.depth] = rows[p.depth] or {}
            for _, q in ipairs(rows[p.depth]) do
                C.yes(math.abs(q.x - p.x) >= N.GAP - 1e-9, row.id .. " has room in its row")
            end
            table.insert(rows[p.depth], p)
        end
    end },
}
