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
}
