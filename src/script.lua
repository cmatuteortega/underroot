-- Dev only: `love . --shots` plays a scripted game on a fixed 30fps clock --
-- grows a network, builds on it, plays waves, cuts and prunes -- writes
-- screenshots to the save directory, prints what happened, and quits. The
-- "look at it before the game does" step from Survive School's 3dmethod.md,
-- for a whole board.
--
-- `love . --shots pond` (or lawn) plays another level instead, with the
-- bot's generic player growing the network, and photographs the bare board,
-- each kind of weather and the boss. Add `challenge` for the challenge wave.

local D = require "src.defs"

local S = {}
io.stdout:setvbuf("line")

-- No one is watching the window: an error should say so and stop, not wait.
function love.errorhandler(msg)
    print("ERROR", msg, debug.traceback())
    os.exit(1)
end

local clock, shots = 0, 0
local game
local steps

local function node(c, r)
    for _, n in ipairs(game.nodes) do
        if n.pocket and n.pocket.c == c and n.pocket.r == r then return n end
    end
    error("no pocket at " .. c .. "," .. r)
end

-- Grown at once: the script has no time to wait for each thread to arrive.
local function link(a, b)
    local l = assert(game:grow(a, b), "could not link")
    l.state, l.grow = "alive", 1
    game:recompute()
end

-- Another level: the bot plays, kept alive, and the script skips ahead to the
-- waves worth a picture.
local act
local function playTo(wave, seconds)
    local t = 0
    while (game.wave < wave or t < seconds) and game.phase ~= "won" do
        if game.wave >= wave then t = t + 1 / 30 end
        act()
        game.heartHp = math.max(game.heartHp, 3)
        game:update(1 / 30)
    end
end

local function beginGeneric(g)
    game = g
    act = require("src.bot").generic(g)
    local waves = {}
    for k, w in ipairs(g.waves) do
        if w.weather and not waves[w.weather] then waves[w.weather] = k end
    end
    steps = { { 0.5, "shot" }, { 0.6, function() g.nutrients = g.nutrients + 300; playTo(1, 6) end }, { 0.7, "shot" } }
    local t = 1
    local order = {}
    for kind, k in pairs(waves) do order[#order + 1] = { kind, k } end
    table.sort(order, function(a, b) return a[2] < b[2] end)
    for _, o in ipairs(order) do
        steps[#steps + 1] = { t, function() g.nutrients = g.nutrients + 250; playTo(o[2], 7) end }
        steps[#steps + 1] = { t + 0.1, "shot" }
        t = t + 0.5
    end
    -- The boss: the last wave with one in it.
    local bossWave
    for k, w in ipairs(g.waves) do
        for _, row in ipairs(w) do if D.ENEMIES[row[1]].boss then bossWave = k end end
    end
    steps[#steps + 1] = { t, function() g.nutrients = g.nutrients + 600; playTo(bossWave, 9) end }
    steps[#steps + 1] = { t + 0.1, "shot" }
    steps[#steps + 1] = { t + 0.5, function() playTo(bossWave, 15) end }
    steps[#steps + 1] = { t + 0.6, "shot" }
    steps[#steps + 1] = { t + 1.0, function() playTo(bossWave, 22) end }
    steps[#steps + 1] = { t + 1.1, "shot" }
    steps[#steps + 1] = { t + 1.5, "quit" }
end

function S.begin(g, api)
    if S.level ~= "crack" then return beginGeneric(g) end
    game = g
    local H = g.heart
    local function at(n) return api.at(n.x, n.y + (n.heart and 10 or 5), n.z) end
    local function move(x, y) love.mousemoved(x, y) end
    local function press(x, y) love.mousemoved(x, y); love.mousepressed(x, y, 1) end
    local function release(x, y) love.mousemoved(x, y); love.mousereleased(x, y, 1) end
    steps = {
        -- The first minute, played with the mouse the way a player would.
        { 0.3, function() press(at(H)); move(at(node(12, 6))) end },
        { 0.4, function() release(at(node(12, 6))) end },
        { 0.6, function() press(at(H)); release(at(H)); press(at(node(12, 3))); release(at(node(12, 3))) end },
        { 0.9, function() press(at(H)); local x, y = at(node(11, 8)); move(x - 30, y + 10) end },
        { 1.0, "shot" },
        { 1.1, function() release(at(node(11, 8))) end },
        { 2.0, function() press(api.button("puffer")); release(api.button("puffer")); press(at(node(12, 6))); release(at(node(12, 6))) end },
        { 2.2, function() move(at(node(12, 3))) end },
        { 2.3, "shot" },
        { 2.5, function()
            assert(#g.links == 3, "three links by hand, got " .. #g.links)
            assert(node(12, 6).tower, "a puffer by hand")
            move(api.button("grow"))
            love.keypressed("space")
        end },
        { 6, "shot" },
        { 9, function()
            -- A lot more network, paid for by the script.
            g.nutrients = g.nutrients + 600
            link(node(12, 6), node(12, 9))
            link(node(12, 9), node(11, 8))
            link(node(11, 8), node(8, 9))
            link(node(8, 9), node(6, 7))
            link(node(6, 7), node(7, 5))
            link(node(7, 5), node(10, 6))
            link(node(10, 6), node(11, 8)) -- closes a ring of five round the trail
        end },
        { 13, function()
            assert(g:build("needle", node(8, 9)))
            assert(g:build("mane", node(11, 8)))
            assert(g:build("relay", node(12, 9)))
            assert(g:build("puffer", node(7, 5)))
            assert(g:build("puffer", node(12, 3)))
            assert(g:lay("mat", 5, 3))
            assert(g:lay("mat", 4, 8))
            -- Upgrades, both ways up the fork.
            assert(g:upgrade(node(12, 6).tower, 2))
            assert(g:upgrade(node(12, 6).tower, 2))
            assert(g:upgrade(node(8, 9).tower, 1))
            assert(g:upgrade(node(12, 9).tower, 1))
        end },
        { 14, "shot" },
        { 16, function() assert(g:pulse(node(7, 5)), "pulse") end },
        { 17, "shot" },
        { 18, function()
            -- A drop of brine straight onto the network, to see it run.
            g:spawn("brine", 1)
            local e = g.enemies[#g.enemies]
            local l = g:linkBetween(node(11, 8), node(8, 9))
            e.x, e.z = (l.a.x + l.b.x) / 2, (l.a.z + l.b.z) / 2
            g:attach(e, l)
        end },
        { 18.6, "shot" },
        { 30, "skip" },  -- through to wave 6, the brine
        { 31, "shot" },
        { 40, "shot" },
        { 50, "shot" },
        { 60, "skip" },
        { 62, "shot" },
        { 75, "shot" },
        { 76, function()
            -- Every species grown and upgraded, for a look at all of them at once.
            g.nutrients = g.nutrients + 2000
            g.cleared = 99
            local looks = { { "inky", 7, 5, 2, 2 }, { "mortar", 6, 7, 1, 2 }, { "cordyceps", 3, 4, 2, 1 },
                { "puffer", 12, 3, 1, 2 }, { "mane", 11, 8, 2, 2 }, { "needle", 1, 3, 2, 2 },
                { "stink", 10, 6, 1, 2 }, { "lamp", 8, 1, 2, 1 }, { "giant", 12, 9, 1, 0 }, { "stink", 3, 2, 2, 2 } }
            for _, l in ipairs(looks) do
                local n = node(l[2], l[3])
                if n.tower then g:sell(n) end
                -- Linked to the nearest fed node, so it is fed and lit.
                if not n.conn then
                    local best, bd
                    for _, o in ipairs(g.nodes) do
                        local d = (o.x - n.x) ^ 2 + (o.z - n.z) ^ 2
                        if o ~= n and o.conn and (not bd or d < bd) and g:canLink(o, n) then best, bd = o, d end
                    end
                    if best then link(best, n) end
                end
                local t = assert(g:build(l[1], n))
                for _ = 1, l[5] do g:upgrade(t, l[4]) end
            end
            if not g:matAt(9, 4) then assert(g:lay("shelf", 9, 5) or g:lay("shelf", 9, 4) or true) end
        end },
        { 77, function()
            -- A fresh puffer, picked: its upgrade fork shows.
            local n = node(10, 6)
            if not n.tower then assert(g:build("puffer", n)) end
            api.select(n.tower)
        end },
        { 78, "shot" },
        { 79, function()
            -- The bosses, brought on to be looked at.
            -- set down mid-trail where they can be seen.
            local function boss(kind, gate, c, r)
                local e = g:spawn(kind, gate)
                e.x, e.z, e.tc, e.tr = c * 16 + 8, r * 16 + 8, c, r
            end
            boss("queen", 1, 6, 3)
            boss("stag", 2, 4, 8)
            boss("dung", 2, 8, 8)
        end },
        { 80, "shot" },
        { 84, "shot" },
        { 85, function()
            -- Frost on the board, and the Humongous Fungus's quake.
            g.weather = "frost"
            local n = node(12, 9)
            if n.tower then n.tower.grown, n.tower.cool = 1, 0 end
        end },
        { 85.9, "shot" },
        { 86, function() g.weather = "night" end },
        { 87, "shot" },
        { 88, function() g.weather = nil; api.menu(true) end },
        { 88.2, "shot" },
        { 88.4, function() api.menu(false); api.loadout(3) end },
        { 88.6, "shot" },
        { 88.8, function() api.loadout(false) end },
        { 89, function() g:offerMutations() end },
        { 89.5, "shot" },
        { 90, function() assert(g:mutate(2)) end },
        { 90.5, "quit" },
    }
end

-- Plays whole waves through, for the "skip" step: waves 2..6 at a stroke.
local function skipTo(wave)
    while game.wave < wave and game.phase ~= "lost" do
        if game.phase == "mutate" then game:mutate(1) end
        if game.phase == "build" then
            game.nutrients = game.nutrients + 50
            game:startWave()
        end
        for _ = 1, 30 do game:update(1 / 30) end
    end
end

function S.update(g, dt)
    clock = clock + dt
    while steps[1] and clock >= steps[1][1] do
        local s = table.remove(steps, 1)[2]
        if type(s) == "function" then
            s()
        elseif s == "skip" then
            skipTo(g.wave + 3)
            if g.phase == "mutate" then g:mutate(1) end
            if g.phase == "build" then g:startWave() end
        elseif s == "shot" then
            S.pending = true
        elseif s == "quit" then
            print(("wave %d  phase %s  sprout %.1f  nutrients %d  kills %d  drunk %d  cuts %d  stolen %d")
                :format(g.wave, g.phase, g.heartHp, g.nutrients, g.stats.kills, g.stats.drunk, g.stats.cuts, g.stats.stolen))
            print("pictures kept", require("src.models").count())
            print(("frame: %.2f ms average, %.2f ms worst (update + draw, real time)"):format(S.total / S.frames * 1000, S.worst * 1000))
            love.event.quit()
        end
    end
end

S.total, S.frames, S.worst = 0, 0, 0
local last
function S.after(g, canvas)
    local now = love.timer.getTime()
    if last and clock > 1 then
        local d = now - last
        S.total, S.frames, S.worst = S.total + d, S.frames + 1, math.max(S.worst, d)
    end
    last = now
    if S.pending then
        S.pending = false
        shots = shots + 1
        canvas:newImageData():encode("png", ("shot%d.png"):format(shots))
        print(("shot %d at %.1fs: wave %d %s, %d enemies, %d links, %d rings, nutrients %d, sprout %.1f")
            :format(shots, clock, g.wave, g.phase, #g.enemies, #g.links, #g.rings, g.nutrients, g.heartHp))
    end
end

return S
