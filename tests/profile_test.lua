-- src/profile.lua: what is kept between runs, the file it is kept in, the
-- six files a save from before had, and the Spore Bank's rules.

local Love = require "tests.love"
local C = require "tests.check"
local D = require "src.defs"
local P = require "src.profile"

local function fresh()
    Love.clearFiles()
    P.load()
end

-- A species put up for sale by a level's first win, and that level.
local function prize()
    for _, l in ipairs(D.LEVELS) do if l.prize then return l.prize, l end end
end

return {
    { "a first run has nothing", function()
        fresh()
        C.eq(P.spores, 0, "spores")
        C.eq(next(P.won), nil, "levels won")
        C.yes(P.levelOpen(1), "the first level is open")
        C.no(P.levelOpen(2), "the second is shut")
        C.no(P.challengeOpen(), "challenge mode is shut")
    end },

    { "what is saved is what is loaded", function()
        fresh()
        P.won.crack, P.records.crack, P.spores = true, 21, 40
        P.loadouts.crack, P.sown.crack = { "puffer", "needle" }, "oak"
        P.owned.inky, P.seeds.oak, P.seen.ant, P.sound = true, true, true, 0.5
        P.save()
        C.yes(Love.files["save.txt"]:find("^version 1\n"), "the file starts with its version")
        P.load()
        C.yes(P.won.crack, "won")
        C.eq(P.records.crack, 21, "endless record")
        C.eq(P.spores, 40, "spores")
        C.list(P.loadouts.crack, { "puffer", "needle" }, "loadout")
        C.eq(P.sown.crack, "oak", "seed")
        C.yes(P.owned.inky, "species bought")
        C.yes(P.seeds.oak, "seed bought")
        C.yes(P.seen.ant, "enemy met")
        C.eq(P.sound, 0.5, "sound")
    end },

    { "a save from before is read from its six files", function()
        Love.clearFiles()
        local f = Love.files
        f["progress.txt"] = "crack\npond\n"
        f["endless.txt"] = "crack 21\nnowhere 3\n"
        f["loadout.txt"] = "crack puffer needle mat inky stink relay seed=oak\npond puffer nothing\n"
        f["bank.txt"] = "spores 900\nowned inky stink\nseeds oak\n"
        f["seen.txt"] = "ant\nqueen\n"
        f["sound.txt"] = "0.5\n"
        P.load()
        C.yes(P.won.crack and P.won.pond, "levels won")
        C.eq(P.records.crack, 21, "record")
        C.eq(P.records.nowhere, nil, "a record for no level")
        C.list(P.loadouts.crack, { "puffer", "needle", "mat", "inky", "stink", "relay" }, "loadout")
        C.eq(P.sown.crack, "oak", "seed")
        C.list(P.loadouts.pond, { "puffer" }, "an unknown species is dropped")
        C.eq(P.spores, 900, "spores")
        C.yes(P.owned.inky and P.owned.stink, "species bought")
        C.eq(P.sound, 0.5, "sound")
        -- Whatever comes on a level won was met there.
        for _, w in ipairs(D.LEVEL.pond.waves) do
            for _, g in ipairs(w) do C.yes(P.seen[g[1]], g[1] .. " met on the Pond Edge") end
        end
        -- Written back as the one file, and read from it after.
        P.save()
        C.yes(f["save.txt"], "save.txt written")
        f["bank.txt"] = "spores 1\n"
        P.load()
        C.eq(P.spores, 900, "save.txt wins over the old files")
    end },

    { "a loadout brings no more than its share", function()
        fresh()
        local all = {}
        for _, t in ipairs(D.TOWERS) do all[#all + 1] = t.id end
        Love.files["save.txt"] = "version 1\nloadout crack " .. table.concat(all, " ") .. " seed=nothing\n"
        P.load()
        C.eq(#P.loadouts.crack, D.LOADOUT, "species brought")
        C.eq(P.sown.crack, nil, "an unknown seed")
    end },

    { "a level's prize is for sale once it is won, and bought with spores", function()
        fresh()
        local id, level = prize()
        C.no(P.owns(id), "not had at first")
        C.no(P.forSale(id), "not for sale before the win")
        P.won[level.id] = true
        C.yes(P.forSale(id), "for sale after it")
        C.yes(P.known(id), "known once for sale")
        P.spores = D.TOWER[id].price - 1
        C.no(P.buy(id), "too few spores")
        P.spores = D.TOWER[id].price + 3
        C.yes(P.buy(id), "bought")
        C.eq(P.spores, 3, "the price is paid")
        C.yes(P.owns(id), "had")
        C.no(P.forSale(id), "no longer for sale")
        P.load()
        C.yes(P.owns(id), "kept")
    end },

    { "the starter species are had from the start", function()
        fresh()
        for _, t in ipairs(D.TOWERS) do
            if t.starter then C.yes(P.owns(t.id), t.id .. " is had") end
        end
    end },

    { "seeds: the free one is had, one with a price is bought", function()
        fresh()
        C.yes(P.ownsSeed(D.SEEDS[1].id), "the first seed is had")
        for _, sd in ipairs(D.SEEDS) do
            if sd.price and not sd.after then
                C.yes(P.seedForSale(sd.id), sd.id .. " is for sale from the start")
                P.spores = sd.price
                C.yes(P.buySeed(sd.id), sd.id .. " bought")
                C.eq(P.spores, 0, "the price is paid")
                C.yes(P.ownsSeed(sd.id), sd.id .. " is had")
            elseif sd.after then
                C.no(P.seedForSale(sd.id), sd.id .. " waits on " .. sd.after)
            end
        end
    end },

    { "a level is open once the one before is won, or any after it", function()
        fresh()
        P.won[D.LEVELS[1].id] = true
        C.yes(P.levelOpen(2), "the next one opens")
        C.no(P.levelOpen(3), "not the one after")
        P.won[D.LEVELS[#D.LEVELS].id] = true
        C.yes(P.levelOpen(3), "a later win keeps the ones before it open")
        C.yes(P.challengeOpen(), "the last won opens challenge mode")
    end },
}
