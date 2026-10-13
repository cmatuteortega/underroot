-- Dev only: `love . --bot [runs]` plays the whole campaign headless, the way a
-- sensible player would -- grow a network, build on it, upgrade, repair cuts,
-- prune brine -- a few times over with different dice, prints how far each run
-- got and quits. A balance check, not an AI: if it wins easily the waves are
-- soft, if it never reaches the last boss they are not.

local D = require "src.defs"
local World = require "src.world"
local Game = require "src.game"

local B = {}

-- The build order, by pocket (column, row). Each step is tried in turn while
-- it is affordable; a step that cannot happen yet (locked, not linked) waits.
local PLAN = {
    { "link", "H", { 12, 6 } }, { "build", "puffer", { 12, 6 } },
    { "link", "H", { 12, 3 } }, { "build", "needle", { 12, 3 } },
    { "link", "H", { 11, 8 } }, { "build", "puffer", { 11, 8 } },
    { "link", { 11, 8 }, { 8, 9 } }, { "build", "needle", { 8, 9 } },
    { "lay", "mat", { 9, 5 } },
    { "link", { 12, 6 }, { 10, 6 } }, { "build", "puffer", { 10, 6 } },
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

local function run(seed)
    love.math.setRandomSeed(seed)
    local world = World.new()
    local g = Game.new(world)
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
    while g.phase ~= "won" and g.phase ~= "lost" and clock < 3600 do
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
                if e.boss then g:pulse(node({ 7, 5 })) break end
            end
        end
        g:update(1 / 30)
        clock = clock + 1 / 30
    end
    return g
end

function B.run(args)
    local runs = tonumber(args[1]) or 4
    local won = 0
    for seed = 1, runs do
        local t0 = love.timer.getTime()
        local g = run(seed)
        if g.phase == "won" then won = won + 1 end
        local leaks = {}
        for k, v in pairs(g.stats.leaked) do leaks[#leaks + 1] = k .. "=" .. v end
        print("   leaked: " .. table.concat(leaks, " ") .. "  bosses through at:" .. (g.stats.bossLeft or ""))
        local mods = {}
        for _, m in ipairs(g.picked) do mods[#mods + 1] = m.id end
        print(("run %d: %s at wave %d  sprout %.1f/%d  kills %d  bosses %d  cuts %d  drunk %d  bank %d  [%s]  %.1fs")
            :format(seed, g.phase, g.wave, g.heartHp, g.heartMax, g.stats.kills, g.stats.bosses, g.stats.cuts,
                g.stats.drunk, g.nutrients, table.concat(mods, " "), love.timer.getTime() - t0))
    end
    print(("won %d of %d"):format(won, runs))
    love.event.quit()
end

return B
