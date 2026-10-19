-- src/lang.lua and the strings files: every line the code puts into the
-- language (tr, trf, Lang.t, Lang.f, a game's say) and everything defs
-- writes has its line in each language, the same %s in it, and only letters
-- the font can draw.

local C = require "tests.check"
local Lang = require "src.lang"
local Font = require "src.font"
local D = require "src.defs"

-- The calls whose string arguments are lines to put into the language.
local CALLS = { "tr", "trf", "Lang.t", "Lang.f", "Lang.compose", "self:say", "self:destroyTower", "self:gnawTower" }
-- Pieces that are put together with another word before they are looked up.
local PIECES = { [" POCKET"] = true }
-- Lines kept in a table and looked up where they are drawn: a table's
-- `name = "..."` and `text = "..."` in these files, the calls of `head(...)`,
-- and the tables below.
local TABLED = { "src/options.lua", "src/ui/home.lua", "src/ui/pause.lua", "src/ui/codex.lua", "src/ui/settings.lua" }
local OWN = { "SPECIES", "SEED", "DORMANT: LINK IT TO THE SPROUT", "STARVED: HALF PACE", "THIRSTY: FEED IT FROM A RELAY",
    "WEBBED SHUT", "WITHERING: DRAPE A LINK OVER IT", "PEBBLE", "LEAF", "CRUMB", "LILY", "STONE", "BEETLE",
    "RICH POCKET", "NORMAL POCKET", "POOR POCKET", "COMING" }
-- Whole tables of them: a file, and the line its table starts on.
local LISTS = { { "src/ui/loadout.lua", "local WORDS = {" }, { "src/ui/credits.lua", "credits.LINES = {" },
    { "src/ui/network.lua", "local NAME = {" }, { "src/ui/network.lua", "local WORLD = {" }, { "src/defs.lua", "local SLOTS = {" } }

local function source(path)
    local f = assert(io.open(path))
    local s = f:read("*a")
    f:close()
    return s
end

-- A call's argument text, from just after its "(" to its own ")".
local function args(s, at)
    local depth, k = 1, at
    while k <= #s and depth > 0 do
        local ch = s:sub(k, k)
        if ch == '"' then
            k = k + 1
            while s:sub(k, k) ~= '"' do if s:sub(k, k) == "\\" then k = k + 1 end k = k + 1 end
        elseif ch == "(" then depth = depth + 1
        elseif ch == ")" then depth = depth - 1 end
        k = k + 1
    end
    return s:sub(at, k - 2)
end

-- The string literals in `text`, those joined by `..` taken as one.
local function literals(text)
    local out = {}
    local k = 1
    while true do
        local a = text:find('"', k, true)
        if not a then break end
        local parts = {}
        local b = a
        while true do
            local e = b + 1
            while text:sub(e, e) ~= '"' do if text:sub(e, e) == "\\" then e = e + 1 end e = e + 1 end
            parts[#parts + 1] = text:sub(b + 1, e - 1):gsub('\\"', '"')
            local nxt = text:match("^%s*%.%.%s*()\"", e + 1)
            if not nxt then k = e + 1 break end
            b = nxt
        end
        out[#out + 1] = table.concat(parts)
    end
    return out
end

-- Every line the code looks up: { line = where it is }.
local function keys()
    local found = {}
    local files = {}
    for name in io.popen("find src main.lua -name '*.lua' -not -path 'src/lang/*'"):lines() do files[#files + 1] = name end
    for _, path in ipairs(files) do
        local s = source(path)
        for _, call in ipairs(CALLS) do
            local pat = "%f[%w_.:]" .. call:gsub("[%.%:]", "%%%0") .. "%("
            for at in s:gmatch(pat .. "()") do
                for _, lit in ipairs(literals(args(s, at))) do
                    if lit:find("%u%u") and not PIECES[lit] then found[lit] = found[lit] or path end
                end
            end
        end
    end
    for _, path in ipairs(TABLED) do
        local s = source(path)
        for lit in s:gmatch('[%s{,]name = "([^"]*)"') do if lit:find("%u%u") then found[lit] = found[lit] or path end end
        for lit in s:gmatch('[%s{,]text = "([^"]*)"') do if lit:find("%u%u") then found[lit] = found[lit] or path end end
        for lit in s:gmatch('head%("([^"]*)"%)') do found[lit] = found[lit] or path end
    end
    for _, l in ipairs(LISTS) do
        local s = source(l[1])
        local from = assert(s:find(l[2], 1, true), l[2])
        local body = s:sub(from, s:find("\n}", from, true) or s:find("}\n", from, true))
        for lit in body:gmatch('"([^"]*)"') do
            if lit:find("%u%u") and not lit:find("^%l") then found[lit] = found[lit] or l[1] end
        end
    end
    for _, lit in ipairs(OWN) do found[lit] = found[lit] or "tests/lang_test.lua" end
    -- An enemy with no short name goes by its id on the top strip; a
    -- species' numbers on the network by theirs.
    for kind, e in pairs(D.ENEMIES) do
        if not e.boss and not e.short then found[kind:upper()] = found[kind:upper()] or "src/ui/hud.lua" end
    end
    for _, row in ipairs(D.NETWORK) do
        for _, k in ipairs(row.stats or {}) do found[k:upper()] = found[k:upper()] or "src/ui/network.lua" end
    end
    return found
end

-- Every line defs writes, as English.
local function defsLines()
    Lang.set("en")
    local out = {}
    local seen = {}
    local FIELDS = { name = true, short = true, blurb = true, role = true, about = true, idea = true, boss = true }
    local function walk(t)
        if seen[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "string" and FIELDS[k] and not Lang.composedAt(t, k) then out[v] = true
            elseif type(v) == "table" then walk(v) end
        end
    end
    walk(D)
    return out
end

local function holes(s) local n = 0 for _ in s:gsub("%%%%", ""):gmatch("%%s") do n = n + 1 end return n end

return {
    { "the font draws every letter a strings file uses", function()
        for _, l in ipairs(Lang.LANGS) do
            local t = Lang.file(l.code)
            for en, s in pairs(t.strings or {}) do
                for ch in s:gmatch(Font.CHAR) do
                    C.yes(Font.has(ch) or ch == '"', l.code .. ": no letter for '" .. ch .. "' in " .. en)
                end
            end
            C.yes(Font.has("Ñ") and Font.has("¿") and Font.width("ESPAÑOL") == 7 * 4 - 1, "accented letters are one wide")
        end
    end },

    { "every line the code looks up has its own in each language", function()
        local found = keys()
        local missing = {}
        for _, l in ipairs(Lang.LANGS) do
            if l.code ~= "en" then
                local t = Lang.file(l.code).strings or {}
                for k, where in pairs(found) do
                    if not t[k] and not k:find("^[%d%s%p]*$") then missing[#missing + 1] = l.code .. " " .. where .. ": " .. k end
                end
            end
        end
        table.sort(missing)
        C.yes(#missing == 0, #missing .. " missing:\n" .. table.concat(missing, "\n"))
    end },

    { "every line defs writes has its own in each language", function()
        local missing = {}
        for _, l in ipairs(Lang.LANGS) do
            if l.code ~= "en" then
                local t = Lang.file(l.code).strings or {}
                for s in pairs(defsLines()) do
                    if not t[s] and s:find("%u%u") then missing[#missing + 1] = l.code .. ": " .. s end
                end
            end
        end
        table.sort(missing)
        C.yes(#missing == 0, #missing .. " missing:\n" .. table.concat(missing, "\n"))
    end },

    { "a pattern keeps its %s in every language", function()
        for _, l in ipairs(Lang.LANGS) do
            for en, s in pairs(Lang.file(l.code).strings or {}) do
                C.eq(holes(s), holes(en), l.code .. ": " .. en)
            end
        end
    end },

    { "the glossary's words are the language's own, and found in its lines", function()
        Lang.set("es")
        for _, g in ipairs(D.GLOSSARY) do
            C.yes(g.forms and #g.forms > 0, "forms for " .. g.name)
            C.no(g.about:find("^[A-Z ,.:]*THE "), "about put into Spanish: " .. g.name)
        end
        Lang.set("en")
        C.eq(D.GLOSSARY[1].name, "STUNNED", "back to English")
        C.eq(D.GLOSSARY[1].forms[1], "STUN", "English forms back")
    end },

    { "defs goes into the language and back", function()
        Lang.set("es")
        C.no(D.TOWER.puffer.name == "SPORE PUFFER", "a species' name")
        C.no(D.NET["slots.5"].name == "FIVE SPECIES", "a line built of others")
        C.yes(D.NET["slots.5"].name:find(Lang.t("FIVE"), 1, true), "built of the language's words")
        C.eq(Lang.f("WAVE %s/%s", 3, 12), Lang.t("WAVE %s/%s"):format("3", "12"), "a pattern filled")
        Lang.set("en")
        C.eq(D.TOWER.puffer.name, "SPORE PUFFER", "back")
        C.eq(D.NET["slots.5"].name, "FIVE SPECIES", "built again")
        C.eq(Lang.t("BACK"), "BACK", "English is the code's own")
        C.eq(Lang.f("WAVE %s/%s", 3, 12), "WAVE 3/12", "filled")
    end },

    { "an unknown language is English", function()
        Lang.set("xx")
        C.eq(Lang.code, "en", "english")
        C.eq(Lang.t("BACK"), "BACK", "as written")
    end },
}
