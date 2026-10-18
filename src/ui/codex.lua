-- The encyclopedia. Every enemy met, every species grown and every seed had,
-- each with its model painted big and all there is to know about it; one not
-- found yet is a dark cutout. Opened from the level picker's top left corner.
-- A page footnotes every status it names (D.GLOSSARY), and the last tab is the
-- glossary itself.

local T = require "src.tracer"
local D = require "src.defs"
local N = require "src.network"
local M = require "src.models"
local Font = require "src.font"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Pixels = require "src.ui.pixels"
local flair = require "src.ui.flair"

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local color, box, text, centred, wrapLines, number, inside, wide =
    Draw.color, Draw.box, Draw.text, Draw.centred, Draw.wrapLines, Draw.number, Draw.inside, Draw.wide
local blit, icon, CUT = Pixels.blit, Pixels.icon, Pixels.CUT
local sound = flair.sound

local codex = {}

codex.TABS = {
    { id = "enemies", name = "ENEMIES" },
    { id = "species", name = "SPECIES" },
    { id = "seeds", name = "SEEDS" },
    { id = "words", name = "STATUSES" },
}
-- The tab open, how far each tab's grid is scrolled, the entry whose page is
-- open (its place in the tab's list) and how far that page is scrolled.
codex.tab, codex.scroll, codex.page, codex.pageScroll = 1, { 0, 0, 0, 0 }, nil, 0
-- The way a model faces in its tile: a little to the right of towards you.
codex.FACE = 0.35
codex.TW, codex.TH = 60, 62

-- Its tables, made once at load.
function codex.init()
    codex.ids = { enemies = D.ENEMY_ORDER, species = {}, seeds = {} }
    for _, t in ipairs(D.TOWERS) do codex.ids.species[#codex.ids.species + 1] = t.id end
    for _, sd in ipairs(D.SEEDS) do codex.ids.seeds[#codex.ids.seeds + 1] = sd.id end
    -- A centipede's segments are enemies of their own: met, they are the centipede.
    codex.whole = {}
    for kind, d in pairs(D.ENEMIES) do if d.seg then codex.whole[d.seg] = kind end end
    -- Every glossary word's forms, longest first (CUT OFF before CUT), and the
    -- phrases that only look like one.
    codex.forms, codex.skips = {}, {}
    for n, g in ipairs(D.GLOSSARY) do
        for _, f in ipairs(g.forms) do codex.forms[#codex.forms + 1] = { f, n } end
        for _, sk in ipairs(g.skip or {}) do codex.skips[#codex.skips + 1] = sk end
    end
    table.sort(codex.forms, function(a, b) return #a[1] > #b[1] end)
end
-- Whatever is out on the board now has been met.
function codex.watch(g)
    local new = false
    for _, e in ipairs(g.enemies) do
        local k = codex.whole[e.kind] or e.kind
        if not e.hidden and not Profile.seen[k] then Profile.seen[k], new = true, true end
    end
    if new then Profile.save() end
end

function codex.list(tab) return codex.ids[codex.TABS[tab].id] end

function codex.found(tab, id)
    local t = codex.TABS[tab].id
    if t == "enemies" then return Profile.seen[id] == true end
    if t == "species" then return Profile.owns(id) end
    return Profile.ownsSeed(id)
end

function codex.name(tab, id)
    local t = codex.TABS[tab].id
    if t == "enemies" then return D.ENEMIES[id].name end
    if t == "species" then return D.TOWER[id].name end
    return D.SEED[id].name
end

-- How many of the three lists are found, and of how many.
function codex.count()
    local n, all = 0, 0
    for tab = 1, 3 do
        for _, id in ipairs(codex.list(tab)) do
            all = all + 1
            if codex.found(tab, id) then n = n + 1 end
        end
    end
    return n, all
end

-- Each enemy's model by heading and leg, as the board draws it walking.
codex.POSE = {
    ant = M.ant, gnat = M.gnat, moth = M.moth, slug = M.slug, spider = M.spider, knight = M.knight,
    springtail = M.springtail, queen = M.queen, stag = M.stag, waterbug = M.waterbug, click = M.click,
    bombardier = M.bombardier, mole = M.mole, centipede = M.centipede,
    pillbug = function(h) return M.pillbug(h, false) end,
    mite = function(h) return M.mite(h) end,
    brine = function(_, leg) return M.brine(leg) end,
    cricket = function(h, leg) return M.mole(h, leg, false, 1.35) end,
    centi = function(h, leg) return M.centipede(h, leg, 0.9) end,
    -- It walks backwards, pushing its ball.
    dung = function(h, leg) return M.dung(h + math.pi, leg) end,
    diver = M.diver, wireworm = M.wireworm, naiad = M.naiad, dragonfly = M.dragonfly, rhino = M.rhino, hornet = M.hornet,
    leafcutter = function(h, leg) return M.leafcutter(h, leg, true) end,
    mold = function(_, leg) return M.mold(leg) end,
}

-- An entry's model as layers { picture, i, j, depth } about its foot, painted
-- `s` times its size on the board, facing `h`, `a` (0..1) through its walk or
-- breath. A centipede brings some of its train, the dung beetle its ball and
-- the mites are a swarm.
function codex.figure(tab, id, s, h, a)
    local t = codex.TABS[tab].id
    if t == "species" then return { { M.scaled(s, M.tower, id, nil, 0, a), 0, 0, 0 } } end
    if t == "seeds" then return { { M.scaled(s, M.sprout, 0, id), 0, 0, 0 } } end
    local leg = floor(a * 4) % 2
    local layers = {}
    -- `back` room units behind it and `side` to its left.
    local function at(pic, back, side)
        local c, sn = math.cos(h), math.sin(h)
        local i, j, d = T.project((-back * c - side * sn) * s, 0, (-back * sn + side * c) * s)
        layers[#layers + 1] = { pic, floor(i + 0.5), floor(j + 0.5), d }
    end
    at(M.scaled(s, codex.POSE[id], h, leg), 0, 0)
    if id == "centi" or id == "centipede" then
        local d = D.ENEMIES[id]
        for k = 1, 3 do at(M.scaled(s, M.centseg, h, (leg + k) % 2, id == "centi" and 0.85 or nil), d.gap * k, 0) end
    elseif id == "dung" then
        at(M.scaled(s, M.ball, h, 0, false), -D.ENEMIES.dung.ballAhead, 0)
    elseif id == "mite" then
        at(M.scaled(s, M.mite, h + 0.9), 4, 4)
        at(M.scaled(s, M.mite, h - 0.6), 5, -4)
    end
    table.sort(layers, function(p, q) return p[4] < q[4] end)
    return layers
end

-- How big an entry's model is painted to fill a w x h box (no more than
-- `most` times its board size), and where its middle is then. `spin`: it goes
-- round, so it must fit facing any way.
codex.fits = {}
function codex.fit(tab, id, w, h, most, spin)
    local key = tab .. id .. ":" .. w .. "x" .. h .. ":" .. most .. (spin and "s" or "")
    local f = codex.fits[key]
    if f then return f end
    local i0, j0, i1, j1 = math.huge, math.huge, -math.huge, -math.huge
    for q = 0, spin and 7 or 0 do
        for _, l in ipairs(codex.figure(tab, id, 1, codex.FACE + q * math.pi / 4, 0)) do
            local pic = l[1]
            i0, j0 = min(i0, l[2] - pic.oi), min(j0, l[3] - pic.oj)
            i1, j1 = max(i1, l[2] - pic.oi + pic.w), max(j1, l[3] - pic.oj + pic.h)
        end
    end
    local s = min(most, w / (i1 - i0), h / (j1 - j0))
    -- In quarter steps, so a handful of sizes are ever painted.
    s = max(0.5, floor(s * 4) / 4)
    f = { s = s, ci = (i0 + i1) / 2 * s, cj = (j0 + j1) / 2 * s }
    codex.fits[key] = f
    return f
end

-- The model in the middle of a box, kept inside it.
function codex.drawFigure(tab, id, x, y, w, h, most, spin, heading, a, dark)
    local f = codex.fit(tab, id, w - 2, h - 2, most, spin)
    local px, py = floor(x + w / 2 - f.ci), floor(y + h / 2 - f.cj)
    local sx, sy, sw, sh = love.graphics.getScissor()
    love.graphics.intersectScissor(x, y, w, h)
    for _, l in ipairs(codex.figure(tab, id, f.s, heading, a)) do
        blit(l[1], px + l[2], py + l[3], dark and CUT or nil)
    end
    love.graphics.setScissor(sx, sy, sw, sh)
end

-- `str` with every glossary word in it footnoted, "STUNNED(2)": numbered in
-- the order the page first meets them, kept in `notes` ({ list, at }). What is
-- matched is held out of the string meanwhile, so nothing is matched twice.
function codex.footnote(str, notes)
    local held = {}
    local function hold(s)
        held[#held + 1] = s
        return "\1" .. #held .. "\2"
    end
    local function plain(s) return (s:gsub("%p", "%%%0")) end
    for _, s in ipairs(codex.skips) do str = str:gsub(plain(s), hold) end
    for _, f in ipairs(codex.forms) do
        str = str:gsub("%f[%w]" .. plain(f[1]) .. "%f[^%w]", function(m) return hold("\3" .. f[2] .. "\4" .. m) end)
    end
    return (str:gsub("\1(%d+)\2", function(k)
        local s = held[tonumber(k)]
        local e, m = s:match("^\3(%d+)\4(.*)$")
        if not e then return s end
        e = tonumber(e)
        if not notes.at[e] then
            notes.list[#notes.list + 1] = e
            notes.at[e] = #notes.list
        end
        return m .. "(" .. notes.at[e] .. ")"
    end))
end

-- Where an entry not found yet is found.
function codex.where(tab, id)
    local t = codex.TABS[tab].id
    if t == "enemies" then
        for _, l in ipairs(D.LEVELS) do
            for _, w in ipairs(l.waves) do
                for _, g in ipairs(w) do if g[1] == id then return "IT COMES ON " .. l.name end end
            end
        end
        if D.ENEMIES[id].from then return "IT HATCHES FROM THE " .. D.ENEMIES[D.ENEMIES[id].from].name end
        return "IT COMES IN CHALLENGE MODE, ON ANY LEVEL"
    end
    -- A species or a seed: grown on the network, once what it waits on is done.
    local row = Profile.nodeOf(id)
    local state, level = Profile.nodeState(row.id)
    if state == "locked" then return "WIN " .. level.name .. ", THEN GROW IT ON THE NETWORK WITH SPORES" end
    return "GROW IT ON THE NETWORK: " .. (N.price(Profile.ranks(), row.id) or 0) .. " SPORES"
end

-- A page's lines, `w` wide, each { s, k, x, h } as the info panel's, or
-- { icon } for an upgrade's picture beside the lines after it. The notes for
-- every glossary word on it come last.
codex.pages = {}
function codex.lines(tab, id, w)
    local found = codex.found(tab, id)
    local key = tab .. id .. ":" .. w .. (found and "f" or "") .. Profile.spores
    if codex.pages[key] then return codex.pages[key] end
    local out, notes = {}, { list = {}, at = {} }
    local function add(str, k, x, h)
        x = x or 0
        for _, l in ipairs(wrapLines(str, w - x)) do out[#out + 1] = { s = l, k = k, x = x, h = h or 7 } end
    end
    local function note(str, k, x) add(codex.footnote(str, notes), k, x) end
    local function gap(h) out[#out + 1] = { h = h } end
    local function head(str) gap(4); add(str, "t") end
    local function names(list, of)
        local s = {}
        for _, n in ipairs(list) do s[#s + 1] = of(n) end
        return table.concat(s, ", ")
    end

    local t = codex.TABS[tab].id
    add(found and codex.name(tab, id) or "???", found and "g" or "k", 0, 9)
    if not found then
        add(t == "enemies" and "NOT MET YET" or (t == "species" and "NOT GROWN YET" or "NOT PLANTED YET"), "r")
        gap(3)
        add(codex.where(tab, id), "s")
    elseif t == "enemies" then
        local d = D.ENEMIES[id]
        note(d.boss and "BOSS" or (d.fly and "FLIER" or "WALKER"), d.boss and "r" or "t")
        gap(3)
        note(d.about, "w")
        head("NUMBERS")
        local parts = { "HP " .. number(d.hp), "SPEED " .. number(d.speed), "ARMOR " .. number(d.armor) }
        if d.swarm then parts[#parts + 1] = d.swarm .. " TO A SWARM" end
        add(table.concat(parts, "  "), "l")
        add("HITS THE SPROUT FOR " .. number(d.heart) .. "  CORPSE WORTH " .. number(d.corpse), "l")
        local met = {}
        local kind = d.from or id -- a Dragonfly comes wherever its nymph does
        for _, l in ipairs(D.LEVELS) do
            local here = false
            for _, wave in ipairs(l.waves) do for _, g in ipairs(wave) do if g[1] == kind then here = true end end end
            if here then met[#met + 1] = l.name end
        end
        for _, c in ipairs(D.CHALLENGES) do
            for _, g in ipairs(c.wave) do if g[1] == kind then met[#met + 1] = "CHALLENGE MODE (" .. c.name .. ")" end end
        end
        head("COMES ON")
        add(#met > 0 and table.concat(met, ", ") or "NOWHERE YET", "w")
        if D.COUNTERS[id] then
            head("ANSWERED BY")
            add(names(D.COUNTERS[id], function(k) return D.TOWER[k].name end), "w")
        end
    elseif t == "species" then
        local d = D.TOWER[id]
        local at = (d.unlock or 0) > 0 and ("   FROM WAVE " .. d.unlock) or ""
        add(d.role .. "   COST " .. d.cost .. at, "t")
        add("THE NUMBERS FULLY GROWN ON THE NETWORK", "s")
        gap(3)
        note(d.blurb, "w")
        gap(3)
        note(d.about, "s")
        head("NUMBERS")
        local parts = {}
        if d.damage then parts[#parts + 1] = "DAMAGE " .. number(d.damage) end
        if d.every then parts[#parts + 1] = "EVERY " .. number(d.every) .. "S" end
        if d.range then parts[#parts + 1] = "RANGE " .. number(d.range) end
        if d.splash then parts[#parts + 1] = "SPLASH " .. number(d.splash) end
        if d.slow then parts[#parts + 1] = "SLOW " .. floor((1 - d.slow) * 100 + 0.5) .. "%" end
        if d.hp then parts[#parts + 1] = "HP " .. d.hp end
        if d.reserve then parts[#parts + 1] = "RESERVE " .. number(d.reserve) end
        add(table.concat(parts, "  "), "l")
        -- What it answers, of the enemies met; the rest only counted.
        local good, unmet = {}, 0
        for _, kind in ipairs(D.ENEMY_ORDER) do
            for _, k in ipairs(D.COUNTERS[kind] or {}) do
                if k == id and Profile.seen[kind] then good[#good + 1] = D.ENEMIES[kind].name
                elseif k == id then unmet = unmet + 1 end
            end
        end
        if unmet > 0 then good[#good + 1] = unmet .. (#good > 0 and " MORE" or "") .. " NOT MET YET" end
        if #good > 0 then head("GOOD AGAINST"); add(table.concat(good, ", "), "w") end
        head("UPGRADES")
        for b = 1, 2 do
            if b == 2 then add("OR", "s") end
            for tier = 1, 2 do
                local row = d.up[b][tier]
                local from = #out
                out[#out + 1] = { icon = { id, b, tier }, h = 0 }
                add((tier == 1 and "I  " or "II ") .. row.name .. "  " .. row.cost, "w", 24)
                note(row.blurb, "s", 24)
                local h = 0
                for k = from + 1, #out do h = h + out[k].h end
                gap(max(2, 30 - h))
            end
        end
    else
        local sd = D.SEED[id]
        add("SEED   " .. (sd.id == "bean" and "THE FIRST" or "GROWN ON THE NETWORK"), "t")
        gap(3)
        note(sd.blurb, "w")
        gap(3)
        note(sd.about, "s")
        head("ITS MUTATIONS")
        for _, m in ipairs(D.MUTATIONS) do
            if m.seed == id then
                add(m.name, "w")
                note(m.blurb, "s", 8)
            end
        end
    end
    if #notes.list > 0 then
        gap(6)
        add("NOTES", "t")
        for n, e in ipairs(notes.list) do
            local g = D.GLOSSARY[e]
            gap(1)
            add("(" .. n .. ") " .. g.name, "l")
            add(g.about, "s", 8)
        end
    end
    codex.pages[key] = out
    return out
end

-- The glossary tab: every word and what it means.
function codex.words(w)
    if codex.wordLines and codex.wordLines.w == w then return codex.wordLines end
    local out = { w = w }
    for _, g in ipairs(D.GLOSSARY) do
        out[#out + 1] = { s = g.name, k = "l", x = 0, h = 7 }
        for _, l in ipairs(wrapLines(g.about, w - 8)) do out[#out + 1] = { s = l, k = "s", x = 8, h = 7 } end
        out[#out + 1] = { h = 4 }
    end
    codex.wordLines = out
    return out
end

function codex.height(lines)
    local h = 0
    for _, l in ipairs(lines) do h = h + l.h end
    return h
end

-- The grid: BACK, the tabs, and a tile an entry, as many across as fit,
-- scrolled under the tabs. `scroll` is kept in reach.
function codex.layout()
    local L = { back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 }, tabs = {} }
    local gap, total = 3, 0
    for k, tb in ipairs(codex.TABS) do
        L.tabs[k] = { w = Font.width(tb.name) + 8, h = 11, y = S.inset.t + 21, tab = k }
        total = total + L.tabs[k].w + (k > 1 and gap or 0)
    end
    local x = floor((S.vw - total) / 2)
    for _, c in ipairs(L.tabs) do c.x = x; x = x + c.w + gap end
    L.top, L.bottom = S.inset.t + 37, S.vh - S.inset.b - 3
    L.left, L.right = S.inset.l + 4, S.vw - S.inset.r - 4
    local view = L.bottom - L.top
    local content
    if codex.TABS[codex.tab].id == "words" then
        L.words = codex.words(L.right - L.left - 8)
        content = codex.height(L.words) + 8
    else
        local TW, TH = codex.TW, codex.TH
        local cols = max(2, floor((L.right - L.left + 4) / (TW + 4)))
        local list = codex.list(codex.tab)
        local x0 = floor((S.vw - (cols * TW + (cols - 1) * 4)) / 2)
        content = ceil(#list / cols) * (TH + 4) + 1
        L.tiles = {}
        for k = 1, #list do
            local col, row = (k - 1) % cols, floor((k - 1) / cols)
            L.tiles[k] = { x = x0 + col * (TW + 4), dy = row * (TH + 4), w = TW, h = TH, n = k, id = list[k] }
        end
    end
    L.most = max(0, content - view)
    codex.scroll[codex.tab] = max(0, min(L.most, codex.scroll[codex.tab]))
    for _, c in ipairs(L.tiles or {}) do c.y = L.top + 1 + c.dy - codex.scroll[codex.tab] end
    return L
end

-- An entry's page: BACK and the arrows to the ones either side of it, the
-- model on the left and the words on the right on a wide screen; on a narrow
-- one the model heads the words and goes up with them.
function codex.pageLayout()
    local P = { back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 } }
    P.next = { x = S.vw - S.inset.r - 4 - 16, y = S.inset.t + 4, w = 16, h = 12, step = 1 }
    P.prev = { x = P.next.x - 19, y = S.inset.t + 4, w = 16, h = 12, step = -1 }
    local top, bottom = S.inset.t + 21, S.vh - S.inset.b - 3
    if wide() then
        local mw = min(170, floor((S.vw - S.inset.l - S.inset.r) * 0.42))
        P.model = { x = S.inset.l + 4, y = top, w = mw, h = bottom - top }
        P.text = { x = P.model.x + mw + 5, y = top, h = bottom - top }
        P.text.w = S.vw - S.inset.r - 4 - P.text.x
    else
        P.text = { x = S.inset.l + 4, y = top, w = S.vw - S.inset.l - S.inset.r - 8, h = bottom - top }
        P.model = { w = P.text.w - 4, h = min(130, floor(S.vh * 0.3)), inline = true }
    end
    P.id = codex.list(codex.tab)[codex.page]
    P.lines = codex.lines(codex.tab, P.id, P.text.w - 8)
    local content = codex.height(P.lines) + 8 + (P.model.inline and P.model.h + 4 or 0)
    P.most = max(0, content - P.text.h)
    codex.pageScroll = max(0, min(P.most, codex.pageScroll))
    return P
end

function codex.open()
    S.menu = "codex"
    codex.page = nil
    sound("panel")
end

function codex.back()
    sound("back")
    if codex.page then codex.page = nil else S.back() end
end

-- To the entry `d` along from the one open, round the ends.
function codex.step(d)
    local n = #codex.list(codex.tab)
    codex.page = (codex.page - 1 + d) % n + 1
    codex.pageScroll = 0
    sound("select")
end

function codex.toTab(k)
    if codex.tab == k and not codex.page then return end
    codex.tab, codex.page = k, nil
    sound("select")
end

-- What is pointed at: hover.cback, hover.ctab (a tab), hover.ctile (an entry)
-- or hover.cstep (an arrow, -1 or 1).
function codex.hover(mx, my)
    if codex.page then
        local P = codex.pageLayout()
        if inside(mx, my, P.back.x, P.back.y, P.back.w, P.back.h) then S.hover.cback = true end
        for _, b in ipairs({ P.prev, P.next }) do
            if inside(mx, my, b.x, b.y, b.w, b.h) then S.hover.cstep = b.step end
        end
        return
    end
    local L = codex.layout()
    if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then S.hover.cback = true return end
    for k, c in ipairs(L.tabs) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.ctab = k return end
    end
    if my < L.top or my >= L.bottom then return end
    for _, c in ipairs(L.tiles or {}) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.ctile = c.n return end
    end
end

-- The box of whatever is pointed at, to light up when it is pressed.
function codex.under()
    if S.hover.cback then return function() local b = codex.layout().back return b.x, b.y, b.w, b.h end end
    if S.hover.cstep then
        local d = S.hover.cstep
        return function()
            local P = codex.pageLayout()
            local b = d < 0 and P.prev or P.next
            return b.x, b.y, b.w, b.h
        end
    end
    if S.hover.ctab then
        local k = S.hover.ctab
        return function() local c = codex.layout().tabs[k] return c.x, c.y, c.w, c.h end
    end
end

function codex.click(b)
    if b == 2 or S.hover.cback then codex.back()
    elseif S.hover.ctab then codex.toTab(S.hover.ctab)
    elseif S.hover.cstep then codex.step(S.hover.cstep)
    elseif S.hover.ctile then
        codex.page, codex.pageScroll = S.hover.ctile, 0
        sound("panel")
    end
end

function codex.key(key)
    if key == "escape" or key == "backspace" then codex.back() return end
    if codex.page then
        if key == "left" or key == "a" then codex.step(-1)
        elseif key == "right" or key == "d" then codex.step(1) end
    else
        local n = tonumber(key)
        if n and codex.TABS[n] then codex.toTab(n) end
        if key == "left" or key == "a" then codex.toTab((codex.tab - 2) % #codex.TABS + 1)
        elseif key == "right" or key == "d" then codex.toTab(codex.tab % #codex.TABS + 1) end
    end
    if key == "up" or key == "w" then codex.scrollBy(-21) end
    if key == "down" or key == "s" then codex.scrollBy(21) end
    if key == "pageup" then codex.scrollBy(-floor(S.vh * 0.7)) end
    if key == "pagedown" or key == "space" then codex.scrollBy(floor(S.vh * 0.7)) end
end

-- Scrolling: whichever is open, the page or the grid. Each draw keeps it in reach.
function codex.getScroll() return codex.page and codex.pageScroll or codex.scroll[codex.tab] end
function codex.setScroll(v)
    if codex.page then codex.pageScroll = max(0, v) else codex.scroll[codex.tab] = max(0, v) end
end
function codex.scrollBy(d) codex.setScroll(codex.getScroll() + d) end

-- A button with its word in the middle.
function codex.btn(b, s, on, edge, k)
    box(b.x, b.y, b.w, b.h, on and "n" or "u", edge)
    text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + floor((b.h - 5) / 2), k or "w")
end

-- How far down a scrolled box is, as a thumb in its right edge.
function codex.thumb(x, y, h, at, most)
    if most <= 0 then return end
    local th = max(6, floor(h * h / (h + most)))
    color("k")
    love.graphics.rectangle("fill", x, y, 1, h)
    color("t")
    love.graphics.rectangle("fill", x, y + floor((h - th) * at / most), 1, th)
end

function codex.drawLines(lines, x, y)
    for _, l in ipairs(lines) do
        if l.s then text(l.s, x + l.x, y, l.k) end
        y = y + l.h
    end
end

function codex.draw()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local clock = flair.now()
    local n, all = codex.count()
    centred("ENCYCLOPEDIA", S.inset.t + 7, "g", "o")
    local found = "FOUND " .. n .. "/" .. all
    if codex.page then
        local P = codex.pageLayout()
        codex.btn(P.back, "BACK", S.hover.cback, S.hover.cback and "t" or "k")
        codex.btn(P.prev, "<", S.hover.cstep == -1, S.hover.cstep == -1 and "t" or "k")
        codex.btn(P.next, ">", S.hover.cstep == 1, S.hover.cstep == 1 and "t" or "k")
        local where = codex.page .. "/" .. #codex.list(codex.tab)
        text(where, P.prev.x - Font.width(where) - 4, P.prev.y + 3, "s")
        codex.drawPage(P, clock)
        return
    end
    local L = codex.layout()
    codex.btn(L.back, "BACK", S.hover.cback, S.hover.cback and "t" or "k")
    text(found, S.vw - S.inset.r - 4 - Font.width(found), S.inset.t + 7, "t")
    for k, c in ipairs(L.tabs) do
        local on = codex.tab == k
        codex.btn(c, codex.TABS[k].name, S.hover.ctab == k or on, on and "g" or (S.hover.ctab == k and "t" or "k"), on and "g" or "w")
    end
    love.graphics.setScissor(0, L.top, S.vw, L.bottom - L.top)
    local sc = codex.scroll[codex.tab]
    if L.words then
        box(L.left, L.top - sc, L.right - L.left, codex.height(L.words) + 8, "u", "c")
        codex.drawLines(L.words, L.left + 4, L.top + 4 - sc)
    else
        for _, c in ipairs(L.tiles) do
            if c.y + c.h > L.top and c.y < L.bottom then
                local own = codex.found(codex.tab, c.id)
                local on = S.hover.ctile == c.n
                local boss = codex.TABS[codex.tab].id == "enemies" and D.ENEMIES[c.id].boss
                box(c.x, c.y, c.w, c.h, on and "n" or "u", on and "w" or (own and (boss and "r" or "c") or "k"))
                -- Pointed at, it walks or breathes; the rest hold still.
                local name = own and codex.name(codex.tab, c.id) or "???"
                local lines = wrapLines(name, c.w - 4)
                codex.drawFigure(codex.tab, c.id, c.x, c.y + 1, c.w, c.h - 3 - 7 * #lines, 3, false, codex.FACE,
                    (own and on) and (clock * 0.7) % 1 or 0, not own)
                local y = c.y + c.h - 1 - 7 * #lines
                for _, l in ipairs(lines) do
                    text(l, c.x + floor((c.w - Font.width(l)) / 2), y, own and (boss and "r" or "w") or "k")
                    y = y + 7
                end
            end
        end
    end
    love.graphics.setScissor()
    codex.thumb(S.vw - S.inset.r - 2, L.top, L.bottom - L.top, sc, L.most)
end

function codex.drawPage(P, clock)
    local tab, id = codex.tab, P.id
    local own = codex.found(tab, id)
    local enemy = codex.TABS[tab].id == "enemies"
    -- Found, an enemy turns slowly round and walks on the spot; a species breathes.
    local heading = (own and enemy) and (codex.FACE - clock * 0.5) or codex.FACE
    local a = own and (enemy and clock * 1.2 or clock * 0.7) % 1 or 0
    local most = 4
    local B = P.text
    local sc = codex.pageScroll
    if not P.model.inline then
        local m = P.model
        box(m.x, m.y, m.w, m.h, "u", own and "c" or "k")
        codex.drawFigure(tab, id, m.x, m.y, m.w, m.h, most, enemy, heading, a, not own)
    end
    box(B.x, B.y, B.w, B.h, "u", "c")
    love.graphics.setScissor(B.x, B.y, B.w, B.h)
    local y = B.y + 4 - sc
    if P.model.inline then
        codex.drawFigure(tab, id, B.x + 2, y, P.model.w, P.model.h, most, enemy, heading, a, not own)
        y = y + P.model.h + 4
    end
    for _, l in ipairs(P.lines) do
        if l.icon then
            local sx, sy, sw, sh = love.graphics.getScissor()
            love.graphics.intersectScissor(B.x + 4, y, 22, 30)
            local kind, b, tier = l.icon[1], l.icon[2], l.icon[3]
            blit(icon(kind, b, tier, (clock * 0.7) % 1), B.x + 15, kind == "mat" and y + 20 or y + 27)
            love.graphics.setScissor(sx, sy, sw, sh)
        elseif l.s then
            text(l.s, B.x + 4 + l.x, y, l.k)
        end
        y = y + l.h
    end
    love.graphics.setScissor()
    codex.thumb(B.x + B.w - 2, B.y + 1, B.h - 2, sc, P.most)
end

return codex
