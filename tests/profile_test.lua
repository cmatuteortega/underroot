-- src/profile.lua: what is kept between runs, the file it is kept in, the
-- saves from before it, and the network the Spore Bank grows.

local Love = require "tests.love"
local C = require "tests.check"
local D = require "src.defs"
local P = require "src.profile"

local function fresh()
    Love.clearFiles()
    P.load()
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
        P.net.needle, P.net["puffer.power"], P.seen.ant, P.sound = 1, 2, true, 0.5
        P.save()
        C.yes(Love.files["save.txt"]:find("^version 4\n"), "the file starts with its version")
        C.yes(Love.files["save.txt"]:find("\nend\n$"), "and ends on end")
        P.load()
        C.yes(P.won.crack, "won")
        C.eq(P.records.crack, 21, "endless record")
        C.eq(P.spores, 40, "spores")
        C.list(P.loadouts.crack, { "puffer", "needle" }, "loadout")
        C.eq(P.sown.crack, "oak", "seed")
        C.eq(P.net.needle, 1, "a node grown")
        C.eq(P.net["puffer.power"], 2, "a node's ranks")
        C.yes(P.owns("needle"), "what it grows")
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
        -- The old bank, and what it paid for inky (0), stink (20) and oak (15), at today's rate.
        C.eq(P.spores, (900 + 20 + 15) * 3, "spores, and what was spent paid back")
        C.no(P.owns("stink"), "what was bought is grown again on the network")
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
        C.eq(P.spores, (900 + 20 + 15) * 3, "save.txt wins over the old files, paid back only the once")
    end },

    { "a save cut short is not read: the one before it is", function()
        fresh()
        P.won.crack, P.spores = true, 40
        P.save()
        P.spores = 50
        P.save()
        local f = Love.files
        C.eq(f["save.tmp"], nil, "nothing left half way")
        C.yes(f["save.bak"]:find("spores 40\n"), "the last good save kept")
        -- Stopped writing save.txt: save.tmp has the new save whole.
        f["save.tmp"], f["save.txt"] = f["save.txt"], "version 3\nwon crack\nspo"
        P.load()
        C.eq(P.spores, 50, "the save being written")
        C.eq(f["save.txt"]:find("\nend\n$") ~= nil, true, "and save.txt whole again")
        -- Stopped writing save.tmp: save.txt is the last whole one.
        f["save.tmp"] = "version 3\nwon"
        P.load()
        C.eq(P.spores, 50, "save.txt, untouched")
        -- Both cut short (or emptied): save.bak.
        f["save.txt"], f["save.tmp"], f["save.bak"] = "", "version 3\n", "version 3\nwon crack\nspores 40\nend\n"
        P.load()
        C.eq(P.spores, 40, "the one before")
        C.yes(P.won.crack, "all of it")
    end },

    { "a version 2 save, from before the end line, still reads", function()
        fresh()
        Love.files["save.txt"] = "version 2\nwon crack\nspores 40\n"
        P.load()
        C.eq(P.spores, 40, "spores, not paid back again")
        C.yes(Love.files["save.txt"]:find("^version 4\n.*\nend\n$"), "brought up to this version")
    end },

    { "a save from a newer version is read, and kept as it was", function()
        fresh()
        local newer = "version 99\nwon crack\nspores 40\nhats red\nend\n"
        Love.files["save.txt"] = newer
        P.load()
        C.eq(P.spores, 40, "what this version knows of it")
        P.spores = 41
        P.save()
        C.eq(Love.files["save.v99.txt"], newer, "a copy of it as it was")
    end },

    { "a loadout brings no more than its share", function()
        fresh()
        local all = {}
        for _, t in ipairs(D.TOWERS) do all[#all + 1] = t.id end
        Love.files["save.txt"] = "version 2\nloadout crack " .. table.concat(all, " ") .. " seed=nothing\n"
        P.load()
        C.eq(#P.loadouts.crack, D.LOADOUT, "species brought")
        C.eq(P.sown.crack, nil, "an unknown seed")
    end },

    { "a version 1 save is paid back what it bought, once", function()
        fresh()
        Love.files["save.txt"] = "version 1\nwon crack\nspores 40\nowned stink giant\nseeds oak dandelion\n"
        P.load()
        C.eq(P.spores, (40 + 20 + 50 + 15 + 25) * 3, "the bank and the purchases, at today's rate")
        C.yes(Love.files["save.txt"]:find("^version 4\n"), "saved at once as this version")
        P.load()
        C.eq(P.spores, (40 + 20 + 50 + 15 + 25) * 3, "and not paid twice")
        C.yes(P.won.crack, "the rest is kept")
    end },

    { "a first run has the puffer, the bean and nothing else", function()
        fresh()
        for _, t in ipairs(D.TOWERS) do C.eq(P.owns(t.id), t.id == "puffer", t.id) end
        for _, sd in ipairs(D.SEEDS) do C.eq(P.ownsSeed(sd.id), sd.id == "bean", sd.id) end
    end },

    { "a node is grown a rank at a time, from what it grows from, for its price", function()
        fresh()
        C.eq(P.nodeState("needle"), "shut", "the needle grows off the puffer's sharper spores")
        P.spores = D.NET["puffer.power"].price[1]
        C.yes(P.buy("puffer.power"), "which are grown first")
        C.eq(P.nodeState("needle"), "poor", "then it can be, for its price")
        C.eq(P.nodeState("needle.power"), "shut", "its own nodes wait on it")
        P.spores = D.NET.needle.price[1] - 1
        C.no(P.buy("needle"), "too few spores")
        P.spores = D.NET.needle.price[1] + 3
        C.yes(P.buy("needle"), "grown")
        C.eq(P.spores, 3, "the price is paid")
        C.yes(P.owns("needle"), "the needle can be brought")
        C.eq(P.nodeState("needle"), "full", "a node of one rank")
        C.yes(P.nodeState("needle.power") ~= "shut", "its own nodes open")
        P.spores = 1000
        for r = 1, #D.NET["needle.power"].price do C.yes(P.buy("needle.power"), "rank " .. r) end
        C.no(P.buy("needle.power"), "no rank past the last")
        P.load()
        C.yes(P.owns("needle"), "kept")
        C.eq(P.net["needle.power"], #D.NET["needle.power"].price, "the ranks kept")
    end },

    { "a node waiting on a win opens with it, and field notes with what is met", function()
        fresh()
        P.spores = 1000
        C.eq(P.nodeState("stink"), "locked", "the stinkhorn waits on the Crack")
        P.won.crack = true
        C.eq(P.nodeState("stink"), "shut", "won, it waits on what it grows from")
        P.buy("mat"); P.buy("mat.power")
        C.eq(P.nodeState("stink"), "open", "and then it opens")
        C.eq(P.nodeState("notes.ants"), "unknown", "nothing met, nothing known")
        P.seen.ant = true
        C.eq(P.nodeState("notes.ants"), "open", "an ant met")
        local opens = {}
        for _, row in ipairs(P.opens("crack")) do opens[#opens + 1] = row.id end
        C.list(opens, { "stink", "slots.5", "oak" }, "what the Crack's first win opens")
    end },

    { "the whole network switched on grows it all, and off is as it was", function()
        fresh()
        P.spores = 100
        P.buy("puffer.power")
        P.setAll(true)
        for _, t in ipairs(D.TOWERS) do C.yes(P.owns(t.id), t.id .. " grown") end
        for _, sd in ipairs(D.SEEDS) do C.yes(P.ownsSeed(sd.id), sd.id .. " grown") end
        C.eq(P.nodeState("cordyceps"), "full", "even behind a win")
        C.no(P.buy("needle"), "nothing to buy")
        C.eq(P.spores, 98, "nothing spent")
        P.load()
        C.yes(P.all, "kept in the save")
        C.yes(P.owns("giant"), "and still all of it")
        P.setAll(false)
        C.no(P.owns("needle"), "off, the needle is not grown")
        C.eq(P.net["puffer.power"], 1, "what was bought is still there")
        P.load()
        C.no(P.all, "off is saved too")
    end },

    { "the whole network regrown gives every spore back", function()
        fresh()
        P.spores = 500
        P.buy("needle"); P.buy("needle.power"); P.buy("hyphae")
        local spent = 500 - P.spores
        C.yes(spent > 0, "spent")
        C.eq(P.regrow(), spent, "what came back")
        C.eq(P.spores, 500, "all of it")
        C.no(P.owns("needle"), "gone")
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

    { "what the guide has taught, and its tips, are kept", function()
        fresh()
        C.no(P.taught.tutorial, "a first run has the tutorial to come")
        C.yes(P.tips, "tips start on")
        P.teach("tutorial")
        P.teach("ant")
        P.tips = false
        P.save()
        P.load()
        C.yes(P.taught.tutorial, "the tutorial")
        C.yes(P.taught.ant, "a first meeting")
        C.no(P.taught.rain, "nothing else")
        C.no(P.tips, "tips off")
    end },

    { "a save from before the guide has nothing taught again", function()
        Love.clearFiles()
        Love.files["save.txt"] = "version 3\nwon crack\nspores 5\nseen ant pillbug\nend\n"
        P.load()
        C.yes(P.taught.tutorial, "no tutorial for one who has played")
        C.yes(P.taught.network, "nor the network's first visit")
        C.yes(P.taught.ant and P.taught.pillbug, "what was met")
        C.yes(P.taught.rain, "the weather of a level won")
        C.no(P.taught.night, "not one still to come")
        C.yes(Love.files["save.txt"]:find("^version 4\n"), "saved at once as this version")
        C.eq(P.spores, 5, "a version 3 save's spores are not paid back again")
    end },
}
