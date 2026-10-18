-- src/resume.lua: a run kept and read back plays on as the one it was taken from.

local Love = require "tests.love"
local C = require "tests.check"
local D = require "src.defs"
local World = require "src.world"
local Game = require "src.game"
local R = require "src.resume"

-- A player with no memory of its own, so two runs in the same state play the
-- same: links out to every pocket it can reach, puffers on them, and the next
-- wave started; the first mutation offered.
local function drive(g)
    if g.phase == "mutate" then g:mutate(1) end
    if g.phase == "build" then
        for _, n in ipairs(g.nodes) do
            if not n.heart and #n.links == 0 then
                for _, m in ipairs(g.nodes) do
                    if (m.heart or #m.links > 0) and g:canLink(m, n) then g:grow(m, n) break end
                end
            end
        end
        for _, n in ipairs(g.nodes) do
            if not n.heart and #n.links > 0 and g:canBuild("puffer", n) then g:build("puffer", n) end
        end
        g:startWave()
    end
    g:update(1 / 30)
end

local function summary(g)
    local s = g.stats
    return ("%s wave %d sprout %.2f kills %d cuts %d nutrients %d links %d enemies %d")
        :format(g.phase, g.wave, g.heartHp, s.kills, s.cuts, g.nutrients, #g.links, #g.enemies)
end

local function finish(g)
    local clock = 0
    while g.phase ~= "won" and g.phase ~= "lost" and clock < 1200 do
        drive(g)
        clock = clock + 1 / 30
    end
    return summary(g)
end

-- Played until `stop(g)`, kept, read back on a board of its own, and both
-- played out.
local function both(id, stop)
    local lv = D.LEVEL[id]
    local g = Game.new(World.new(lv.map), lv, { dice = 3, challenge = "bombardier" })
    g.nutrients = 2000 -- puffers everywhere: a long run, and a busy one
    local clock = 0
    while not stop(g) do
        drive(g)
        clock = clock + 1 / 30
        assert(clock < 600 and g.phase ~= "lost" and g.phase ~= "won", id .. ": never got there, " .. summary(g))
    end
    local text = assert(R.encode(g, { level = id }))
    local back = R.decode(text, World.new(lv.map))
    C.yes(back, "read back")
    C.eq(summary(back), summary(g), id .. ": as it was kept")
    return finish(back), finish(g)
end

return {
    { "a run kept at a build phase plays on the same", function()
        local a, b = both("crack", function(g) return g.phase == "build" and g.wave == 2 end)
        C.eq(a, b, "the Crack, kept before wave 3")
    end },

    { "a run kept in the middle of a wave plays on the same", function()
        local frames = 0
        local a, b = both("pond", function(g)
            if g.phase == "wave" and g.wave == 3 then frames = frames + 1 end
            return frames > 300 and #g.enemies > 0
        end)
        C.eq(a, b, "the Pond Edge, kept ten seconds into wave 3")
    end },

    { "what points at what still does", function()
        local lv = D.LEVEL.crack
        local world = World.new(lv.map)
        local g = Game.new(world, lv, { dice = 1 })
        while g.wave < 2 do drive(g); assert(g.phase ~= "lost", summary(g)) end
        local back = assert(R.decode(assert(R.encode(g, {})), World.new(lv.map)))
        C.yes(back.level == D.LEVEL.crack, "the level is the numbers' own")
        C.yes(back.nodes[1] == back.heart, "the sprout is its first node")
        for _, l in ipairs(back.links) do
            local found = false
            for _, x in ipairs(l.a.links) do if x == l then found = true end end
            C.yes(found, "a link is in its node's list")
        end
        for k, p in ipairs(back.world.pockets) do C.yes(back.nodes[k + 1].pocket == p, "a node's pocket is its board's") end
        C.eq(back.dice:random(1000), g.dice:random(1000), "the dice roll on as they would have")
    end },

    { "kept the way the save is, and let go", function()
        Love.clearFiles()
        local lv = D.LEVEL.crack
        local g = Game.new(World.new(lv.map), lv, { dice = 1 })
        C.yes(R.save(g, { level = "crack", challenge = false }), "kept")
        g:update(1 / 30)
        R.save(g, { level = "crack", challenge = false })
        local text, head = R.load()
        C.yes(text, "read")
        C.eq(head.level, "crack", "what run it is")
        Love.files["run.txt"] = text:sub(1, 40)
        C.yes(R.load(), "one cut short: the copy beside it")
        R.clear()
        C.eq(R.load(), nil, "let go")
    end },

    { "a run that will not read is none", function()
        local lv = D.LEVEL.crack
        local g = Game.new(World.new(lv.map), lv, { dice = 1 })
        local text = assert(R.encode(g, {}))
        C.eq(R.decode(text:gsub("^return {v=%d+", "return {v=0"), World.new(lv.map)), nil, "another version's")
        C.eq(R.decode(text:gsub('{"D",', '{"Q",'), World.new(lv.map)), nil, "pointing at what is gone")
        C.eq(R.decode("return os.exit()\nreturn {}\nend\n", World.new(lv.map)), nil, "nothing in reach")
    end },
}
