-- Whole runs, played by src/bot.lua: the same dice play the same run, and the
-- build order the balance is tuned against still wins the first level.

require "tests.love"
local C = require "tests.check"
local D = require "src.defs"
local B = require "src.bot"

-- What a run came to, as one line.
local function summary(g)
    local s = g.stats
    return ("%s wave %d sprout %.1f kills %d bosses %d cuts %d drunk %d nutrients %d")
        :format(g.phase, g.wave, g.heartHp, s.kills, s.bosses, s.cuts, s.drunk, g.nutrients)
end

return {
    { "the same dice play the same run", function()
        for _, id in ipairs({ "crack", "pond", "lawn" }) do
            local a = summary(B.play(5, D.LEVEL[id], true))
            local b = summary(B.play(5, D.LEVEL[id], true))
            C.eq(b, a, id .. ", the generic player twice")
        end
    end },

    { "the Crack's build order wins it", function()
        for seed = 1, 2 do
            local g = B.play(seed, D.LEVEL.crack)
            C.eq(g.phase, "won", "seed " .. seed .. ": " .. summary(g))
        end
    end },

    -- The network's balance: from nothing, the build orders lose the Crack a
    -- few times before it falls, finish the story with the network still far
    -- from grown, and every level in turn.
    { "from an empty network the story is won, but not at once", function()
        local o = B.campaign(30, true)
        local log = "\n" .. table.concat(o.log, "\n")
        C.yes(o.wins.crack and o.wins.crack >= 4 and o.wins.crack <= 14, "the Crack falls after a few runs" .. log)
        local last = o.wins[D.LEVELS[#D.LEVELS].id]
        C.yes(last, "the story is won within 30 runs" .. log)
        C.yes(last - o.wins.crack >= #D.LEVELS, "the rest takes more than a run a level" .. log)
        C.yes(o.spent < o.all * 0.6, "with much of the network still to grow: " .. o.spent .. " of " .. o.all)
    end },
}
