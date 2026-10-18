-- src/options.lua: the settings, kept in save.txt only where they differ from
-- where they start, and the keys moved off their usual places.

local Love = require "tests.love"
local C = require "tests.check"
local O = require "src.options"
local P = require "src.profile"

local function fresh()
    Love.clearFiles()
    P.load()
end

return {
    { "a first run has every setting where it starts", function()
        fresh()
        C.eq(O.get("effects"), 1, "effects")
        C.eq(O.get("auto"), false, "the next wave waits")
        C.eq(O.get("shake"), true, "the screen shakes")
        C.eq(O.line(), nil, "nothing to write")
        C.no(Love.files["save.txt"] and Love.files["save.txt"]:find("\nsettings"), "no settings line")
    end },

    { "settings are saved and loaded", function()
        fresh()
        O.set("effects", 0.5)
        O.set("auto", true)
        O.set("text", "large")
        O.set("cap", 60)
        O.set("shake", true) -- where it starts: not written
        P.save()
        C.yes(Love.files["save.txt"]:find("\nsettings effects=0.5 auto=1 text=large cap=60\n"), "one line, what differs")
        O.reset()
        P.load()
        C.eq(O.get("effects"), 0.5, "effects")
        C.eq(O.get("auto"), true, "auto")
        C.eq(O.get("text"), "large", "text")
        C.eq(O.get("cap"), 60, "frame cap")
    end },

    { "a setting with a value it does not have is left where it starts", function()
        Love.clearFiles()
        Love.files["save.txt"] = "version 5\nsettings effects=7 hats=red speed=3\nend\n"
        P.load()
        C.eq(O.get("effects"), 1, "no such level")
        C.eq(O.get("speed"), 3, "the rest still read")
    end },

    { "a version 4 save reads, and gets the settings' defaults", function()
        Love.clearFiles()
        Love.files["save.txt"] = "version 4\nwon crack\nspores 9\nsound 0.5\ntips 0\nend\n"
        P.load()
        C.eq(P.spores, 9, "spores")
        C.eq(P.sound, 0.5, "the sound keeps its line")
        C.no(P.tips, "and the tips theirs")
        C.eq(O.get("ambience"), 1, "a new setting where it starts")
        C.yes(Love.files["save.txt"]:find("^version 5\n"), "saved as this version")
    end },

    { "a key moved, and swapped with the one it lands on", function()
        fresh()
        C.eq(O.translate("space"), "space", "the usual key")
        C.yes(O.bind("start", "k"), "moved")
        C.eq(O.translate("k"), "space", "the new key starts the wave")
        C.eq(O.translate("space"), nil, "the old one no longer does")
        C.eq(O.label("space"), "K", "and it says so")
        C.yes(O.bind("speed", "k"), "onto a key taken")
        C.eq(O.key("speed"), "k", "speed moved")
        C.eq(O.key("start"), "f", "start took speed's old key")
        C.no(O.bind("pause", "escape"), "back cannot be moved onto")
        C.no(O.bind("pause", "t", { t = true }), "nor a species' key")
        P.save()
        O.reset()
        P.load()
        C.eq(O.key("speed"), "k", "kept")
        C.eq(O.key("start"), "f", "kept too")
        O.bind("start", "space")
        O.bind("speed", "f")
        C.eq(O.keysLine(), nil, "all back: nothing to write")
    end },
}
