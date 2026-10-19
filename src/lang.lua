-- The languages the game is written in. English is the code's own: every
-- player-facing line is written in it where it is used, and that line is the
-- key a language's strings file (src/lang/<code>.lua) puts its own beside.
-- So a line with nothing written for it stays as it is, in English.
--
--   L.t("BACK")                       the line in the language up
--   L.f("WAVE %s OF %s", 3, 12)       a pattern, put into the language, then filled
--
-- What src/defs.lua writes (the species, the enemies, the levels, the
-- glossary...) is put into the language up in place, by L.set, the English
-- kept aside to go back to; a line defs builds out of others is built again
-- (L.compose).

local L = {}

-- The languages there are, each in its own words, in the order the settings
-- show them.
L.LANGS = {
    { code = "en", name = "ENGLISH" },
    { code = "es", name = "ESPAÑOL" },
}

L.code = "en"
local strings = {} -- the language up's lines, by the English
local own = {} -- the same lines, as a set: looked up again, they are no miss
local glossary = {} -- its glossary's forms, by the English name

local function load(code)
    if code == "en" then return {} end
    local ok, t = pcall(require, "src.lang." .. code)
    return ok and t or {}
end

-- Lines looked up that the language up has nothing for (the script prints
-- them, to find what is still in English).
L.missing = {}

-- A line in the language up. Anything that is not a string (a number, nil)
-- comes back as it is.
function L.t(s)
    if type(s) ~= "string" then return s end
    local line = strings[s]
    if line then return line end
    -- (A line with a number in it was put together, most likely, from one
    -- that was looked up.)
    if L.code ~= "en" and s:find("%u%u") and not own[s] and not s:find("%d") then L.missing[s] = true end
    return s
end

-- A pattern in the language up, filled with `...` (each as a string, so %s
-- takes a number as well as a word).
function L.f(pattern, ...)
    local args = { ... }
    for k = 1, select("#", ...) do args[k] = tostring(args[k]) end
    return (L.t(pattern):format(unpack(args, 1, select("#", ...))))
end

--- what src/defs.lua writes ----------------------------------------------------------------

-- The fields of defs' rows that are something to read.
local FIELDS = { name = true, short = true, blurb = true, role = true, about = true, idea = true, boss = true }

local data -- { { t, field, english } }, found the first time the language changes
local composed = {} -- { t, field, pattern, pieces }, set by L.compose
local skip = {} -- t = { field = true }: composed, not a line of its own
local forms -- { row, forms, skip } of the glossary, in English

-- A line defs builds out of others: `pattern` filled with `...`, each a line
-- that is put into the language too (a name), or a number. Written into
-- t[field] in English now, and again in the language up whenever it changes.
function L.compose(t, field, pattern, ...)
    local pieces = { ... }
    composed[#composed + 1] = { t = t, field = field, pattern = pattern, pieces = pieces, n = select("#", ...) }
    skip[t] = skip[t] or {}
    skip[t][field] = true
    local args = {}
    for k = 1, select("#", ...) do args[k] = tostring(pieces[k]) end
    t[field] = pattern:format(unpack(args, 1, select("#", ...)))
    return t[field]
end

-- Is t[field] one of those (for the tests)?
function L.composedAt(t, field) return skip[t] ~= nil and skip[t][field] == true end

local function gather(D)
    data, forms = {}, {}
    local seen = {}
    local function walk(t)
        if seen[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "string" and FIELDS[k] and not (skip[t] and skip[t][k]) then
                data[#data + 1] = { t = t, field = k, en = v }
            elseif type(v) == "table" then
                walk(v)
            end
        end
    end
    walk(D)
    for _, g in ipairs(D.GLOSSARY or {}) do forms[#forms + 1] = { row = g, forms = g.forms, skip = g.skip, name = g.name } end
end

local function retext(D)
    if not data then gather(D) end
    for _, d in ipairs(data) do d.t[d.field] = L.t(d.en) end
    for _, c in ipairs(composed) do
        local args = {}
        for k = 1, c.n do args[k] = tostring(L.t(c.pieces[k])) end
        c.t[c.field] = L.t(c.pattern):format(unpack(args, 1, c.n))
    end
    for _, g in ipairs(forms) do
        local own = glossary[g.name]
        g.row.forms = own and own.forms or g.forms
        g.row.skip = own and own.skip or g.skip
    end
end

--- the language up ---------------------------------------------------------------------------

function L.known(code)
    for _, l in ipairs(L.LANGS) do if l.code == code then return true end end
    return false
end

-- The language to start in where the player has not picked one: the
-- system's, if it is one there is, else English.
function L.detect()
    local list = {}
    if love and love.system and love.system.getPreferredLocales then
        local ok, locales = pcall(love.system.getPreferredLocales)
        if ok and locales then for _, l in ipairs(locales) do list[#list + 1] = l end end
    end
    list[#list + 1] = os.getenv("LC_ALL")
    list[#list + 1] = os.getenv("LC_MESSAGES")
    list[#list + 1] = os.getenv("LANG")
    for _, l in ipairs(list) do
        local code = l and l:lower():match("^(%a%a)")
        if code and L.known(code) then return code end
    end
    return "en"
end

-- The game in `code`: its lines, and defs' rows written in it.
function L.set(code)
    if not L.known(code) then code = "en" end
    local t = load(code)
    L.code = code
    strings = t.strings or {}
    glossary = t.glossary or {}
    own = {}
    for _, s in pairs(strings) do own[s] = true end
    retext(require "src.defs")
end

-- For the tests: the strings file of a language, as it is written.
L.file = load

return L
