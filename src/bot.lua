-- Dev only: `love . --bot [runs] [level] [generic] [challenge]` plays a level
-- headless, the way a sensible player would -- grow a network, build on it,
-- upgrade, repair cuts, prune brine -- a few times over with different dice,
-- prints how far each run got and quits. A balance check, not an AI: if it
-- wins easily the waves are soft, if it never reaches the last boss they are
-- not.
--
-- It follows a build order written for the level's map. A map without one
-- (or `generic`) gets a rule that works on any map: grow out to whichever
-- pocket in reach watches the most trail, put the next species of a fixed
-- rotation on it, upgrade when it is rich. That one is much the weaker
-- player; the build orders are what the balance is tuned against.

local D = require "src.defs"
local World = require "src.world"
local Game = require "src.game"

local B = {}

-- The build orders, one a level, by pocket (column, row). Each step is tried
-- in turn while it is affordable; a step that cannot happen yet (locked, not
-- linked) waits.
local PLANS = {}
PLANS.crack = {
    { "link", "H", { 12, 6 } }, { "build", "puffer", { 12, 6 } },
    { "link", "H", { 12, 3 } }, { "build", "needle", { 12, 3 } },
    { "link", "H", { 11, 8 } }, { "build", "puffer", { 11, 8 } },
    { "link", { 11, 8 }, { 8, 9 } }, { "build", "needle", { 8, 9 } },
    { "lay", "mat", { 9, 5 } },
    { "link", { 12, 6 }, { 10, 6 } }, { "build", "stink", { 10, 6 } },
    { "link", { 11, 8 }, { 12, 9 } }, { "build", "mane", { 12, 9 } },
    { "up", { 12, 6 }, 2 }, { "up", { 12, 3 }, 1 },
    { "link", { 10, 6 }, { 7, 5 } }, { "build", "puffer", { 7, 5 } },
    { "build", "inky", { 12, 1 }, link = { 12, 3 } },
    { "link", { 8, 9 }, { 6, 7 } }, { "link", { 6, 7 }, { 7, 5 } }, { "build", "relay", { 6, 7 } },
    { "lay", "shelf", { 9, 7 } }, { "lay", "mat", { 6, 8 } },
    { "up", { 11, 8 }, 1 }, { "up", { 8, 9 }, 2 }, { "up", { 12, 9 }, 2 },
    { "link", { 7, 5 }, { 8, 1 } }, { "build", "mortar", { 8, 1 } },
    { "up", { 10, 6 }, 1 }, { "up", { 12, 6 }, 2 }, { "up", { 12, 3 }, 1 },
    { "link", { 7, 5 }, { 3, 4 } }, { "build", "cordyceps", { 3, 4 } },
    { "up", { 7, 5 }, 1 }, { "up", { 8, 1 }, 1 }, { "up", { 6, 7 }, 2 }, { "up", { 11, 8 }, 1 },
    { "up", { 8, 9 }, 2 }, { "up", { 10, 6 }, 1 }, { "up", { 7, 5 }, 1 }, { "up", { 8, 1 }, 1 },
    { "up", { 3, 4 }, 1 }, { "up", { 12, 1 }, 2 }, { "up", { 3, 4 }, 1 },
    { "lay", "shelf", { 5, 2 } }, { "lay", "mat", { 9, 3 } }, { "lay", "shelf", { 5, 8 } },
}

-- The Flowerpot: puffers either side of the sprout hold the hole and the
-- last turn of the spiral; the rest reaches out over the rings of trail.
PLANS.flowerpot = {
    { "link", "H", { 6, 4 } }, { "build", "puffer", { 6, 4 } },
    { "link", "H", { 9, 6 } }, { "build", "needle", { 9, 6 } },
    { "link", "H", { 5, 6 } }, { "build", "puffer", { 5, 6 } },
    { "lay", "mat", { 8, 4 } },
    { "link", "H", { 7, 7 } }, { "build", "mane", { 7, 7 } },
    { "up", { 6, 4 }, 2 }, { "up", { 9, 6 }, 1 },
    { "link", { 9, 6 }, { 10, 4 } }, { "build", "puffer", { 10, 4 } },
    { "link", { 7, 7 }, { 10, 7 } }, { "build", "needle", { 10, 7 } },
    { "lay", "mat", { 6, 5 } },
    { "link", { 5, 6 }, { 4, 7 } }, { "build", "mortar", { 4, 7 } },
    { "link", { 6, 4 }, { 4, 4 } }, { "link", { 4, 4 }, { 4, 7 } }, { "build", "relay", { 4, 4 } },
    { "up", { 5, 6 }, 2 }, { "up", { 10, 4 }, 2 }, { "up", { 7, 7 }, 1 },
    { "lay", "mat", { 2, 6 } }, { "lay", "mat", { 12, 5 } },
    { "link", { 10, 4 }, { 8, 2 } }, { "build", "mortar", { 8, 2 } },
    { "up", { 9, 6 }, 1 }, { "up", { 10, 7 }, 1 }, { "up", { 4, 7 }, 1 }, { "up", { 4, 4 }, 2 },
    { "up", { 6, 4 }, 2 }, { "up", { 5, 6 }, 2 }, { "up", { 10, 4 }, 2 }, { "up", { 8, 2 }, 1 },
    { "up", { 7, 7 }, 1 }, { "up", { 10, 7 }, 1 }, { "up", { 4, 7 }, 1 }, { "up", { 8, 2 }, 1 }, { "up", { 4, 4 }, 2 },
    { "lay", "mat", { 7, 8 } },
}

-- The Shed Floor: hold the chokepoint from the caps either side of it, a
-- shelf across it and mats behind, and puffers for the springtails that hop it.
PLANS.shed = {
    { "link", "H", { 14, 5 } }, { "build", "puffer", { 14, 5 } },
    { "link", "H", { 13, 7 } }, { "build", "needle", { 13, 7 } },
    { "lay", "shelf", { 12, 6 } },
    { "link", { 13, 7 }, { 13, 8 } }, { "build", "puffer", { 13, 8 } },
    { "link", "H", { 13, 4 } }, { "build", "mane", { 13, 4 } },
    { "lay", "mat", { 10, 6 } },
    { "up", { 14, 5 }, 2 }, { "up", { 13, 7 }, 1 },
    { "link", { 13, 4 }, { 13, 2 } }, { "build", "needle", { 13, 2 } },
    { "link", { 13, 4 }, { 13, 3 } }, { "build", "stink", { 13, 3 } },
    { "link", { 13, 8 }, { 10, 10 } }, { "build", "puffer", { 10, 10 } },
    { "lay", "mat", { 11, 6 } },
    { "up", { 13, 8 }, 2 }, { "up", { 13, 3 }, 1 }, { "up", { 13, 4 }, 2 },
    { "link", { 13, 2 }, { 9, 2 } }, { "build", "puffer", { 9, 2 } },
    { "up", { 13, 2 }, 1 }, { "up", { 13, 7 }, 1 }, { "up", { 10, 10 }, 2 }, { "up", { 9, 2 }, 2 },
    { "lay", "mat", { 9, 6 } },
    { "up", { 14, 5 }, 2 }, { "up", { 13, 8 }, 2 }, { "up", { 13, 3 }, 1 }, { "up", { 13, 4 }, 2 },
    { "up", { 13, 2 }, 1 }, { "up", { 13, 7 }, 1 }, { "up", { 10, 10 }, 2 }, { "up", { 9, 2 }, 2 },
    { "lay", "mat", { 8, 6 } },
}

-- The Rotting Log: two rings of three over the last straight either side of
-- the sprout, a lamp out at the corner, and the rot paying for it all.
PLANS.log = {
    { "link", "H", { 13, 5 } }, { "build", "puffer", { 13, 5 } },
    { "link", "H", { 13, 7 } }, { "build", "needle", { 13, 7 } },
    { "link", "H", { 10, 5 } }, { "build", "puffer", { 10, 5 } },
    { "link", { 13, 5 }, { 13, 3 } }, { "link", { 10, 5 }, { 13, 3 } }, { "build", "needle", { 13, 3 } },
    { "link", "H", { 14, 6 } }, { "build", "mane", { 14, 6 } },
    { "up", { 13, 5 }, 2 }, { "up", { 13, 7 }, 1 },
    { "link", { 13, 7 }, { 13, 9 } }, { "build", "puffer", { 13, 9 } },
    { "link", { 13, 9 }, { 10, 10 } }, { "link", { 13, 7 }, { 10, 10 } }, { "build", "mortar", { 10, 10 } },
    { "link", { 10, 5 }, { 8, 3 } }, { "build", "lamp", { 8, 3 } },
    { "up", { 10, 5 }, 2 }, { "up", { 13, 3 }, 1 }, { "up", { 14, 6 }, 1 },
    { "link", { 10, 5 }, { 7, 6 } }, { "build", "inky", { 7, 6 } },
    { "link", { 13, 9 }, { 11, 9 } }, { "build", "needle", { 11, 9 } },
    { "up", { 13, 9 }, 2 }, { "up", { 10, 10 }, 1 }, { "up", { 8, 3 }, 1 }, { "up", { 13, 7 }, 1 },
    { "link", { 8, 3 }, { 8, 1 } }, { "build", "mortar", { 8, 1 } },
    { "up", { 13, 5 }, 2 }, { "up", { 10, 5 }, 2 }, { "up", { 13, 3 }, 1 }, { "up", { 11, 9 }, 1 },
    { "up", { 7, 6 }, 2 }, { "up", { 8, 1 }, 1 }, { "up", { 14, 6 }, 1 }, { "up", { 13, 9 }, 2 },
    { "up", { 10, 10 }, 1 }, { "up", { 8, 3 }, 1 }, { "up", { 13, 7 }, 1 }, { "up", { 11, 9 }, 1 }, { "up", { 8, 1 }, 1 },
}

-- The Pond Edge: hold the end of the flooded lane and the turn down to the
-- sprout; stones for what the Water Bug must not have.
PLANS.pond = {
    { "link", "H", { 12, 7 } }, { "build", "puffer", { 12, 7 } },
    { "link", "H", { 14, 5 } }, { "build", "stink", { 14, 5 } },
    { "link", "H", { 12, 8 } }, { "build", "needle", { 12, 8 } },
    { "lay", "mat", { 12, 5 } },
    { "link", { 12, 7 }, { 10, 6 } }, { "build", "puffer", { 10, 6 } },
    { "link", { 12, 8 }, { 13, 9 } }, { "build", "mane", { 13, 9 } },
    { "up", { 12, 7 }, 2 }, { "up", { 12, 8 }, 1 },
    { "link", { 14, 5 }, { 13, 3 } }, { "build", "puffer", { 13, 3 } },
    { "link", { 10, 6 }, { 9, 4 } }, { "build", "lamp", { 9, 4 } },
    { "link", { 9, 4 }, { 7, 3 } }, { "build", "needle", { 7, 3 } },
    { "lay", "shelf", { 11, 5 } },
    { "link", { 12, 8 }, { 10, 9 } }, { "build", "giant", { 10, 9 } },
    { "up", { 14, 5 }, 1 }, { "up", { 10, 6 }, 2 }, { "up", { 13, 3 }, 1 }, { "up", { 12, 8 }, 1 },
    { "link", { 10, 6 }, { 7, 7 } }, { "build", "mortar", { 7, 7 } },
    { "up", { 13, 9 }, 2 }, { "up", { 9, 4 }, 2 }, { "up", { 7, 3 }, 2 }, { "up", { 12, 7 }, 2 },
    { "up", { 10, 9 }, 1 }, { "up", { 14, 5 }, 1 }, { "up", { 10, 6 }, 2 }, { "up", { 13, 3 }, 1 },
    { "lay", "mat", { 6, 5 } }, { "up", { 7, 7 }, 1 }, { "up", { 10, 9 }, 1 }, { "up", { 9, 4 }, 2 }, { "up", { 7, 3 }, 2 },
}

-- The Lawn: the stinkhorn between the two branches by the sprout, and the
-- network out along the southern trail where the three ways in meet.
PLANS.lawn = {
    { "link", "H", { 14, 8 } }, { "build", "puffer", { 14, 8 } },
    { "link", "H", { 13, 4 } }, { "build", "needle", { 13, 4 } },
    { "link", "H", { 11, 6 } }, { "build", "stink", { 11, 6 } },
    { "lay", "mat", { 13, 5 } },
    { "link", { 11, 6 }, { 8, 8 } }, { "build", "puffer", { 8, 8 } },
    { "link", "H", { 16, 7 } }, { "build", "mane", { 16, 7 } },
    { "up", { 14, 8 }, 2 }, { "up", { 13, 4 }, 1 },
    { "link", { 8, 8 }, { 7, 6 } }, { "build", "needle", { 7, 6 } },
    { "link", { 8, 8 }, { 10, 10 } }, { "build", "lamp", { 10, 10 } },
    { "lay", "shelf", { 14, 7 } },
    { "link", { 11, 6 }, { 12, 3 } }, { "build", "giant", { 12, 3 } },
    { "up", { 8, 8 }, 2 }, { "up", { 11, 6 }, 1 }, { "up", { 7, 6 }, 1 }, { "up", { 16, 7 }, 2 },
    { "link", { 7, 6 }, { 4, 8 } }, { "build", "mortar", { 4, 8 } },
    { "up", { 14, 8 }, 2 }, { "up", { 13, 4 }, 1 }, { "up", { 10, 10 }, 2 }, { "up", { 12, 3 }, 1 },
    { "up", { 8, 8 }, 2 }, { "up", { 11, 6 }, 1 }, { "up", { 7, 6 }, 1 }, { "up", { 16, 7 }, 2 },
    { "lay", "mat", { 6, 8 } }, { "up", { 4, 8 }, 1 }, { "up", { 12, 3 }, 1 }, { "up", { 10, 10 }, 2 }, { "up", { 4, 8 }, 1 },
}

-- The rotation the generic player grows in.
local ROTATION = { "puffer", "needle", "puffer", "mane", "stink", "relay", "puffer", "inky", "lamp", "mortar",
    "needle", "puffer", "giant", "cordyceps", "stink", "puffer", "needle", "lamp", "mortar", "puffer", "relay", "needle" }

-- A player for any map: answers a function to call every tick.
function B.generic(g)
    local w = g.world
    local trail = {}
    for r = 0, w.rows - 1 do
        for c = 0, w.cols - 1 do
            if w:distAt(c, r) then trail[#trail + 1] = { x = c * 16 + 8, z = r * 16 + 8, d = w:distAt(c, r) } end
        end
    end
    -- How much trail a pocket watches, nearer the sprout counting more.
    local watch = {}
    for _, n in ipairs(g.nodes) do
        local v = 0
        for _, t in ipairs(trail) do
            local d2 = (t.x - n.x) ^ 2 + (t.z - n.z) ^ 2
            if d2 <= 44 * 44 then v = v + 1 + 4 / (1 + t.d) end
        end
        watch[n] = v
    end
    local next, laid, upTurn = 1, 0, 0
    return function()
        if g.phase == "mutate" then g:mutate(1) end
        -- Repair, and prune whatever brine is running down.
        for _, e in ipairs(g.enemies) do
            if e.slide and e.slide.state == "alive" then g:prune(e.slide) end
        end
        for _, l in ipairs(g.links) do
            if l.state == "cut" and not l.hand then
                if l.salted then g:prune(l) elseif g.nutrients > g:repairCost(l) + 5 then g:repair(l) end
            end
        end
        -- The next species on the best pocket it can reach.
        local kind = ROTATION[(next - 1) % #ROTATION + 1]
        if not g:unlocked(kind) or (D.TOWER[kind].unique and g.uniques[kind]) then
            next = next + 1
        else
            local best, bv, from
            for _, n in ipairs(g.nodes) do
                if not n.heart and not n.tower and (n.salted or 0) <= 0 and watch[n] > 0 then
                    local src
                    if n.conn then src = n
                    else
                        for _, o in ipairs(g.nodes) do
                            if o.conn and g:canLink(o, n) and (not src or (o.x - n.x) ^ 2 + (o.z - n.z) ^ 2 < (src.x - n.x) ^ 2 + (src.z - n.z) ^ 2) then src = o end
                        end
                    end
                    -- A Water Bug drags what is in reach of the water: stones first, near it.
                    local v = watch[n] * (n.pocket.high and 1.3 or 1)
                    if src and (not bv or v > bv) then best, bv, from = n, v, src end
                end
            end
            if best then
                local cost = D.TOWER[kind].cost + (best.conn and 0 or g:linkCost(math.sqrt((best.x - from.x) ^ 2 + (best.z - from.z) ^ 2)))
                if g.nutrients >= cost + 5 then
                    if not best.conn then
                        local l = g:grow(from, best)
                        if l then l.state, l.grow = "alive", 1; g:recompute() end
                    end
                    if g:build(kind, best) then next = next + 1 end
                end
            end
        end
        -- A mat on the trail now and then, near the sprout.
        if laid < 4 and g.nutrients > 60 then
            for _, t in ipairs(trail) do
                if t.d == 3 + laid * 2 then
                    local c, r = math.floor(t.x / 16), math.floor(t.z / 16)
                    if g:lay("mat", c, r) then laid = laid + 1 break end
                end
            end
        end
        -- Rich: upgrade, taking turns down the list.
        if g.nutrients > 110 then
            local list = {}
            for _, n in ipairs(g.nodes) do if n.tower and g:upgrades(n.tower)[1] then list[#list + 1] = n.tower end end
            if list[1] then
                upTurn = upTurn + 1
                local t = list[(upTurn - 1) % #list + 1]
                g:upgrade(t, t.branch or (upTurn % 2 + 1))
            end
        end
        if g.phase == "build" then g:startWave() end
        if g.pulseCd <= 0 then
            for _, e in ipairs(g.enemies) do
                if e.boss then
                    local busy
                    for _, n in ipairs(g.nodes) do if n.tower and n.conn and (not busy or watch[n] > watch[busy]) then busy = n end end
                    if busy then g:pulse(busy) end
                    break
                end
            end
        end
    end
end

-- Still playing? With `endless` a win goes on into endless, until the sprout
-- falls (or the clock runs out).
local function going(g, endless, clock)
    if endless and g.phase == "won" then g:goEndless() end
    return g.phase ~= "won" and g.phase ~= "lost" and clock < (endless and 7200 or 3600)
end

local function run(seed, lv, generic, challenge, endless)
    love.math.setRandomSeed(seed)
    local world = World.new(lv.map)
    local g = Game.new(world, lv, { challenge = challenge })
    local PLAN = PLANS[lv.id]
    if generic or not PLAN then
        local act = B.generic(g)
        local clock = 0
        while going(g, endless, clock) do
            act()
            g:update(1 / 30)
            clock = clock + 1 / 30
        end
        return g
    end
    local function node(p)
        if p == "H" then return g.heart end
        for _, n in ipairs(g.nodes) do
            if n.pocket and n.pocket.c == p[1] and n.pocket.r == p[2] then return n end
        end
        error("no pocket " .. p[1] .. "," .. p[2])
    end
    local step = 1
    local function act()
        while PLAN[step] do
            local s = PLAN[step]
            local done = false
            if s[1] == "link" then
                local a, b = node(s[2]), node(s[3])
                if g:linkBetween(a, b) then done = true
                elseif g:canLink(a, b) then local l = g:grow(a, b); done = l and true end
            elseif s[1] == "build" then
                local n = node(s[3])
                if s.link and not g:linkBetween(n, node(s.link)) then
                    if g:canLink(node(s.link), n) then g:grow(node(s.link), n) else return end
                end
                if n.tower and n.tower.kind == s[2] then done = true
                elseif g:canBuild(s[2], n) then done = g:build(s[2], n) and true
                elseif not g:unlocked(s[2]) then done = false end
            elseif s[1] == "lay" then
                local m = g:matAt(s[3][1], s[3][2])
                if m then done = true
                else
                    local ok, why = g:canLay(s[2], s[3][1], s[3][2])
                    if ok then done = g:lay(s[2], s[3][1], s[3][2]) and true
                    elseif why == "TILE TAKEN" then done = true end
                end
            elseif s[1] == "up" then
                local t = node(s[2]).tower
                if not t or not g:upgrades(t)[1] then done = true
                elseif g:canUpgrade(t, s[3]) or g:canUpgrade(t, t.branch or s[3]) then
                    done = g:upgrade(t, t.branch or s[3])
                end
            end
            if not done then return end
            step = step + 1
        end
    end
    local clock = 0
    while going(g, endless, clock) do
        if g.phase == "mutate" then g:mutate(1) end
        act()
        -- Rebuild what slugs ate and brine sterilised: walk the plan again from the top.
        for k = 1, step - 1 do
            local s = PLAN[k]
            if s[1] == "build" then
                local n = node(s[3])
                if not n.tower and g:canBuild(s[2], n) then g:build(s[2], n) end
            end
        end
        -- Repair, and prune whatever brine is running down.
        for _, e in ipairs(g.enemies) do
            if e.slide and e.slide.state == "alive" then g:prune(e.slide) end
        end
        for _, l in ipairs(g.links) do
            if l.state == "cut" and not l.hand then
                if l.salted then g:prune(l) elseif g.nutrients > g:repairCost(l) + 5 then g:repair(l) end
            end
        end
        if g.phase == "build" then g:startWave() end
        -- Pulse the busiest tower when a boss is on.
        if g.pulseCd <= 0 then
            for _, e in ipairs(g.enemies) do
                if e.boss then g:pulse(node(lv.id == "crack" and { 7, 5 } or PLAN[2][3])) break end
            end
        end
        g:update(1 / 30)
        clock = clock + 1 / 30
    end
    g.planStep = PLAN[step] and step
    return g
end

function B.run(args)
    local runs = tonumber(args[1]) or 4
    local lv, generic, challenge, endless = D.LEVELS[1], false, false, false
    for _, a in ipairs(args) do
        if D.LEVEL[a] then lv = D.LEVEL[a] end
        if a == "generic" then generic = true end
        if a == "challenge" then challenge = true end
        if a == "endless" then endless = true end
    end
    print(lv.name .. (challenge and " (challenge)" or "") .. ((generic or not PLANS[lv.id]) and ", generic player" or ""))
    local won = 0
    for seed = 1, runs do
        local t0 = love.timer.getTime()
        local g = run(seed, lv, generic, challenge, endless)
        if g.phase == "won" or g.endless then won = won + 1 end
        if g.endless then print("   endless: held " .. g.cleared .. " waves") end
        local leaks = {}
        for k, v in pairs(g.stats.leaked) do leaks[#leaks + 1] = k .. "=" .. v end
        print("   leaked: " .. table.concat(leaks, " ") .. "  bosses through at:" .. (g.stats.bossLeft or ""))
        local mods = {}
        for _, m in ipairs(g.picked) do mods[#mods + 1] = m.id end
        -- Lost with the build order unfinished: the step it was waiting on.
        if g.phase == "lost" and g.planStep then print("   stuck at plan step " .. g.planStep) end
        print(("run %d: %s at wave %d  sprout %.1f/%d  kills %d  bosses %d  cuts %d  drunk %d  bank %d  [%s]  %.1fs")
            :format(seed, g.phase, g.wave, g.heartHp, g.heartMax, g.stats.kills, g.stats.bosses, g.stats.cuts,
                g.stats.drunk, g.nutrients, table.concat(mods, " "), love.timer.getTime() - t0))
    end
    print(("won %d of %d"):format(won, runs))
    love.event.quit()
end

return B
