-- The loadout, picked before each level: the seed to plant and the species to
-- bring, with what the level sends to answer. Only what the network has
-- grown can come; the rest says where on the network it grows (N opens it).

local T = require "src.tracer"
local D = require "src.defs"
local N = require "src.network"
local Font = require "src.font"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Pixels = require "src.ui.pixels"
local Panel = require "src.ui.panel"
local flair = require "src.ui.flair"
local Run = require "src.ui.run"
local Network = require "src.ui.network"
local Lang = require "src.lang"
local tr, trf = Lang.t, Lang.f

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local color, box, text, centred, wrap, say, inside, wide =
    Draw.color, Draw.box, Draw.text, Draw.centred, Draw.wrap, Draw.say, Draw.inside, Draw.wide
local blit, icon, CUT = Pixels.blit, Pixels.icon, Pixels.CUT
local info = Panel.info
local sound, deny = flair.sound, flair.deny

-- The loadout picker: what the level sends (a chip an enemy, bosses last),
-- a card a species under it, and GROW under those (top right, across from
-- BACK, when the screen is too short for it there), all centred down the
-- screen; BACK top left, as on every screen, the spores beside it. A narrow
-- screen takes fewer cards a row.
local SW, SH = 62, 26
local function enemiesOf(lv)
    local seen = {}
    for _, w in ipairs(lv.waves) do for _, g in ipairs(w) do seen[g[1]] = true end end
    if S.challenge then for _, g in ipairs(D.CHALLENGE[S.challenge].wave) do seen[g[1]] = true end end
    -- What hatches out of what is sent comes too.
    for kind, e in pairs(D.ENEMIES) do if e.from and seen[e.from] then seen[kind] = true end end
    local list = {}
    for _, kind in ipairs(D.ENEMY_ORDER) do if seen[kind] then list[#list + 1] = kind end end
    return list
end

local function layout()
    local lv = D.LEVELS[S.pick.n]
    -- With the panel open the picker keeps to the room it leaves: the left on a
    -- wide screen, the top on a narrow one.
    local open = S.pick.info ~= nil or S.pick.seedInfo ~= nil
    local left, right = S.inset.l, S.vw - S.inset.r
    if open and wide() then right = S.vw - S.inset.r - Panel.infoWidth() - 6 end
    local mid = floor((left + right) / 2)
    local avail = right - left - 8
    local cols = 6
    while cols > 2 and cols * SW + (cols - 1) * 4 > avail do cols = cols == 6 and 4 or cols - 1 end
    local rows = ceil(#D.TOWERS / cols)

    -- The chips, flowed into rows as wide as the cards.
    local width = max(cols * SW + (cols - 1) * 4, min(avail, 300))
    local chips, lines, x = {}, 1, 0
    -- One not met yet has no name until it is faced.
    local function name(kind) return Profile.seen[kind] and D.ENEMIES[kind].name or "???" end
    for _, kind in ipairs(enemiesOf(lv)) do
        local w = Font.width(name(kind)) + 6
        if x > 0 and x + w > width then lines, x = lines + 1, 0 end
        chips[#chips + 1] = { kind = kind, line = lines, dx = x, w = w, h = 9, name = name(kind) }
        x = x + w + 3
    end
    -- The seeds, chips too: a name each, "???" for one still waiting on a win.
    local seeds, seedRows = {}, 1
    x = 0
    for _, sd in ipairs(D.SEEDS) do
        local s = (Profile.ownsSeed(sd.id) or not Network.hidden(sd.id)) and sd.short or "???"
        local w = Font.width(s) + 8
        if x > 0 and x + w > width then seedRows, x = seedRows + 1, 0 end
        seeds[#seeds + 1] = { seed = sd, line = seedRows, dx = x, w = w, h = 11, name = s }
        x = x + w + 3
    end

    -- GROW goes under the cards when it fits there with a line of tip under
    -- it; on a short screen (a phone or tablet on its side) it goes top right,
    -- across from BACK, so it is never off the bottom.
    local height = 22 + 10 + lines * 12 + 6 + 8 + seedRows * 14 + 8 + rows * (SH + 4)
    local corner = S.inset.t + 20 + height + 6 + 16 + 6 + 8 > S.vh - S.inset.b
    if not corner then height = height + 6 + 16 end
    local y = max(S.inset.t + 20, floor((S.vh - S.inset.b - 12 - height) / 2))
    if open and not wide() then y = S.inset.t + 20 end
    local top = y
    y = y + 32
    -- Each chip row centred on its own.
    local function flow(list, y0, step)
        local ends = {}
        for _, c in ipairs(list) do ends[c.line] = c.dx + c.w end
        for _, c in ipairs(list) do
            c.x = floor(mid - ends[c.line] / 2) + c.dx
            c.y = y0 + (c.line - 1) * step
        end
    end
    flow(chips, y, 12)
    y = y + lines * 12 + 6
    local seedsY = y + 8
    flow(seeds, seedsY, 14)
    y = seedsY + seedRows * 14 + 8

    local x0 = floor(mid - (cols * SW + (cols - 1) * 4) / 2)
    local cards = {}
    local cardsY = y
    for k, t in ipairs(D.TOWERS) do
        local col, row = (k - 1) % cols, floor((k - 1) / cols)
        cards[k] = { x = x0 + col * (SW + 4), y = y + row * (SH + 4), w = SW, h = SH, t = t }
    end
    y = y + rows * (SH + 4)
    local back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 }
    local go
    if corner then
        go = { x = right - 4 - 50, y = S.inset.t + 4, w = 50, h = 12 }
        y = y + 2
    else
        go = { x = mid - 25, y = y + 6, w = 50, h = 16 }
        y = go.y + go.h + 6
    end
    return { top = top, chips = chips, chipsY = top + 32, seeds = seeds, seedsY = seedsY, cards = cards, cardsY = cardsY,
        back = back, go = go, mid = mid, tipY = y }
end

-- How many can come: as many as the network has made room for.
local function room() return N.slots(Profile.grown()) end
local WORDS = { "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT" }

local function picked()
    local list = {}
    for _, t in ipairs(D.TOWERS) do if S.pick.set[t.id] then list[#list + 1] = t.id end end
    return list
end

-- A species in or out of the loadout. Full, it says so rather than drop one.
local function toggleSpecies(id)
    -- Not grown yet: its panel says where on the network it grows.
    if not Profile.owns(id) then S.pick.info = id; deny() return end
    if S.pick.set[id] then S.pick.set[id] = nil; sound("off")
    elseif #picked() >= room() then S.pick.full = 1.5; sound("deny")
    else S.pick.set[id] = true; sound("on") end
end

-- The panel's button: brings or leaves what is grown; for what is not, opens
-- the network on the node it grows on.
local function bringOrGrow(id)
    if Profile.owns(id) then toggleSpecies(id) else Network.open(id) end
end

-- A seed card or its panel's button: plants what is grown, or opens the
-- network on it.
local function plantOrGrow(id)
    if Profile.ownsSeed(id) then
        if S.pick.seed ~= id then S.pick.seed = id; sound("on") end
    else
        Network.open(id)
    end
end

-- Before level `n`: pick what to bring, starting from what was brought last
-- time (or the level's own suggestion the first time).
local function open(n)
    local lv = D.LEVELS[n]
    S.menu = "loadout"
    S.mode, S.drag, S.selected = "grow", nil, nil
    -- The seed planted here last time, if it is still had; else the bean.
    local seed = Profile.sown[lv.id]
    S.pick = { n = n, set = {}, full = 0, seed = seed and Profile.ownsSeed(seed) and seed or D.SEEDS[1].id }
    local dropped = false
    -- As many as there is room for: the suggestion is longer than a new network's.
    for _, id in ipairs(Profile.loadouts[lv.id] or lv.loadout or {}) do
        if #picked() >= room() then break end
        if Profile.owns(id) then S.pick.set[id] = true else dropped = true end
    end
    -- A species not had yet stays home, and the next one had takes its place.
    for _, t in ipairs(D.TOWERS) do
        if not dropped or #picked() >= room() then break end
        if Profile.owns(t.id) then S.pick.set[t.id] = true end
    end
end

-- Off into the level with what was picked, remembered for next time.
local function setOff()
    local list = picked()
    if #list == 0 then sound("deny") return end
    sound("go")
    Profile.loadouts[D.LEVELS[S.pick.n].id] = list
    Profile.sown[D.LEVELS[S.pick.n].id] = S.pick.seed
    Profile.save()
    S.chosen = list
    Run.play(S.pick.n)
end

-- The panel's button in the loadout: plant a seed, bring or leave a species,
-- or for one not grown yet, off to the network to grow it.
local function drawPanelButton(P)
    local b = P.button
    local id = P.seed or P.kind
    if b and not (P.seed and Profile.ownsSeed(id) or (not P.seed and Profile.owns(id))) then
        local s = tr("GROW IT ON THE NETWORK")
        box(b.x, b.y, b.w, b.h, S.hover.bring and "n" or "u", "t")
        text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 4, "t")
    elseif b and P.seed then
        local on = S.pick.seed == id
        local s = tr(on and "PLANTED" or "PLANT IT")
        box(b.x, b.y, b.w, b.h, S.hover.bring and "n" or (on and "u" or "d"), on and "t" or "g")
        text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 4, on and "w" or "g")
    elseif b then
        local inn = S.pick.set[P.kind]
        local full = not inn and #picked() >= room()
        local s = inn and tr("LEAVE IT AT HOME") or (full and trf("%s ALREADY: DROP ONE", tr(WORDS[room()])) or tr("BRING IT"))
        box(b.x, b.y, b.w, b.h, S.hover.bring and "n" or (inn and "u" or "d"), full and "k" or (inn and "t" or "g"))
        text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 4, full and "k" or (inn and "w" or "g"))
    end
end

local function draw()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local lv = D.LEVELS[S.pick.n]
    local L = layout()
    local list = picked()
    local clock = flair.now()
    centred(S.challenge and trf("%s (CHALLENGE)", lv.name) or lv.name, L.top, "g", "o", L.mid)
    text(trf("SPORES %s", Profile.spores) .. say(tr("   N: NETWORK"), ""), L.back.x + L.back.w + 6, S.inset.t + 7, "t")
    local count = #list .. "/" .. room()
    centred(trf("PICK A SEED AND THE SPECIES TO BRING  %s", count), L.top + 11, #list >= room() and "l" or "t", "o", L.mid)
    for _, h in ipairs({ { "COMING", L.chipsY - 9 }, { "SEED", L.seedsY - 7 }, { "SPECIES", L.cardsY - 7 } }) do
        local s = tr(h[1])
        text(s, floor(L.mid - Font.width(s) / 2), h[2], "s")
    end

    -- The seeds: the planted one lit green, one grown in white, one the
    -- network could grow tan, one still waiting on a win dark.
    for _, c in ipairs(L.seeds) do
        local sd = c.seed
        local own, inn, on = Profile.ownsSeed(sd.id), S.pick.seed == sd.id, S.hover.seed == sd.id
        local sale = not own and not Network.hidden(sd.id)
        local edge = inn and "g" or "k"
        if on or S.pick.seedInfo == sd.id then edge = inn and "w" or "t" end
        box(c.x, c.y, c.w, c.h, inn and "d" or (on and "n" or "u"), edge)
        text(c.name, c.x + 4, c.y + 3, inn and "g" or (own and "w" or (sale and "t" or "k")))
    end

    -- The enemy pointed at (or pinned) lights up what answers it.
    local enemy = S.hover.enemy or S.pick.enemy
    local met = enemy and Profile.seen[enemy]
    local answers = {}
    for _, id in ipairs(met and D.COUNTERS[enemy] or {}) do answers[id] = true end
    for _, c in ipairs(L.chips) do
        local boss = D.ENEMIES[c.kind].boss and Profile.seen[c.kind]
        local on = enemy == c.kind
        box(c.x, c.y, c.w, c.h, on and "n" or "u", on and "w" or (boss and "r" or "k"))
        text(c.name, c.x + 3, c.y + 2, boss and "r" or (Profile.seen[c.kind] and "w" or "k"))
    end

    for _, c in ipairs(L.cards) do
        local t = c.t
        local inn, on, ans = S.pick.set[t.id], S.hover.species == t.id, answers[t.id]
        local edge = inn and "l" or "k"
        if ans and floor(clock * 4) % 2 == 0 then edge = "w" end
        if on or S.pick.info == t.id then edge = inn and "w" or "t" end
        box(c.x, c.y, c.w, c.h, (inn or on) and "n" or "u", edge)
        -- The picture kept to its corner of the card: a shelf or the giant is wider.
        local pic = icon(t.id, nil, 0, inn and (clock * 0.7) % 1 or 0)
        love.graphics.setScissor(c.x, c.y, 21, c.h)
        local known = Profile.owns(t.id) or not Network.hidden(t.id)
        blit(pic, c.x + 11, t.id == "mat" and c.y + c.h - 8 or c.y + c.h - 3, not known and CUT or (not inn and T.DARKER2 or nil))
        love.graphics.setScissor()
        local own = Profile.owns(t.id)
        wrap(known and t.name or "???", c.x + 22, c.y + 3, c.w - 24, inn and "w" or (own and "s" or "k"))
        -- Not grown yet: on the network, or locked behind a win.
        if not own then
            text(tr(known and "NETWORK" or "LOCKED"), c.x + 22, c.y + c.h - 7, known and "t" or "k")
        else
            local cost = floor(N.value(Profile.grown(), t.id, "cost", t.cost) + 0.5)
            text(tostring(cost), c.x + 22, c.y + c.h - 7, inn and "l" or "k")
        end
        -- The wave it comes in, given what else is brought.
        local at = D.unlockAt(lv, t.id, S.pick.set)
        if own and at > 0 then
            local s = trf("W%s", at)
            text(s, c.x + c.w - Font.width(s) - 2, c.y + c.h - 7, "k")
        end
        if not S.touch then text(t.key, c.x + 1, c.y + 1, "s") end
        if ans then text("!", c.x + c.w - 4, c.y + 2, "w") end
    end

    local b, g = L.back, L.go
    box(b.x, b.y, b.w, b.h, S.hover.back and "n" or "u", S.hover.back and "t" or "k")
    text(tr("BACK"), b.x + floor((b.w - Font.width(tr("BACK"))) / 2), b.y + 4, "w")
    local ready = #list > 0
    box(g.x, g.y, g.w, g.h, ready and (S.hover.go and "m" or "d") or "u", ready and "g" or "k")
    text(tr("GROW"), g.x + floor((g.w - Font.width(tr("GROW"))) / 2), g.y + (g.h > 12 and 5 or 4), ready and "g" or "k")

    local P = info()
    if P then
        Panel.draw(P)
        drawPanelButton(P)
        if S.pick.full > 0 then centred(trf("ONLY %s COME. DROP ONE FIRST", room()), L.tipY, "r", "o", L.mid) end
        return
    end

    -- One line under it all: what is pointed at, or how it works.
    local tip, k
    if S.pick.full > 0 then
        tip, k = trf("ONLY %s COME. DROP ONE FIRST", room()), "r"
    elseif S.hover.seed then
        local sd = D.SEED[S.hover.seed]
        if Profile.ownsSeed(sd.id) then tip, k = sd.name .. ": " .. sd.blurb, "w"
        else tip, k = Network.howTo(sd.id), Network.hidden(sd.id) and "k" or "t" end
    elseif S.hover.species and not Profile.owns(S.hover.species) then
        local id = S.hover.species
        tip, k = Network.howTo(id), Network.hidden(id) and "k" or "t"
    elseif S.hover.species then
        local t = D.TOWER[S.hover.species]
        tip, k = t.name .. ": " .. t.blurb, "w"
    elseif enemy and not met then
        tip, k = tr("???: NOT MET YET. FACE IT TO LEARN WHAT ANSWERS IT"), "k"
    elseif enemy then
        local names = {}
        for _, id in ipairs(D.COUNTERS[enemy] or {}) do names[#names + 1] = D.TOWER[id].name end
        tip, k = D.ENEMIES[enemy].name .. ": " .. D.ENEMIES[enemy].blurb:gsub("%.?$", ".") .. tr(" ANSWER: ") .. table.concat(names, ", "), "t"
    elseif not ready then
        tip, k = tr("BRING AT LEAST ONE"), "r"
    else
        tip, k = tr(say("CLICK A SEED TO PLANT IT. CLICK A SPECIES TO READ IT, AGAIN TO BRING OR LEAVE IT. POINT AT AN ENEMY FOR ITS ANSWER",
            "TAP A SEED TO PLANT IT. TAP A SPECIES TO READ IT, AGAIN TO BRING OR LEAVE IT. TAP AN ENEMY FOR ITS ANSWER")), "s"
    end
    local room = S.vw - S.inset.l - S.inset.r - 8
    local y = L.tipY
    -- Too long for one line: broken at words, as many lines as it takes.
    local line = ""
    for word in tip:gmatch("%S+") do
        local try = line == "" and word or line .. " " .. word
        if Font.width(try) > room then
            centred(line, y, k, "o")
            line, y = word, y + 9
        else
            line = try
        end
    end
    centred(line, y, k, "o")
end

-- What is pointed at: the panel and its button, an enemy, a seed, a card, BACK or GROW.
local function hover(mx, my)
    local P = info()
    if P then
        if inside(mx, my, P.button.x, P.button.y, P.button.w, P.button.h) then S.hover.bring = true return end
        if inside(mx, my, P.x, P.y, P.w, P.h) then S.hover.info = true return end
    end
    local L = layout()
    for _, c in ipairs(L.chips) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.enemy = c.kind return end
    end
    for _, c in ipairs(L.seeds) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.seed = c.seed.id return end
    end
    for _, c in ipairs(L.cards) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.species = c.t.id return end
    end
    if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then S.hover.back = true end
    if inside(mx, my, L.go.x, L.go.y, L.go.w, L.go.h) then S.hover.go = true end
end

-- The box of whatever is pointed at, to light up when it is pressed.
local function under()
    local L = layout()
    if S.hover.back then return function() return L.back.x, L.back.y, L.back.w, L.back.h end end
    if S.hover.go then return function() return L.go.x, L.go.y, L.go.w, L.go.h end end
    if S.hover.species then
        for _, c in ipairs(L.cards) do
            if c.t.id == S.hover.species then return function() return c.x, c.y, c.w, c.h end end
        end
    end
    if S.hover.seed then
        for _, c in ipairs(L.seeds) do
            if c.seed.id == S.hover.seed then return function() return c.x, c.y, c.w, c.h end end
        end
    end
end

local function click(b)
    -- A card opens its panel; the same card again (or the panel's button)
    -- brings it or leaves it, or buys it. Anywhere else shuts the panel.
    if S.hover.bring then
        if S.pick.seedInfo then plantOrGrow(S.pick.seedInfo) else bringOrGrow(S.pick.info) end
        return
    end
    if S.hover.info then return end
    if b == 2 then
        sound("back")
        if S.pick.info or S.pick.seedInfo then S.pick.info, S.pick.seedInfo = nil, nil else S.openMenu() end
        return
    elseif S.hover.species then
        S.pick.seedInfo = nil
        if S.pick.info == S.hover.species then toggleSpecies(S.hover.species) else S.pick.info = S.hover.species; sound("panel") end
        return
    elseif S.hover.seed then
        -- One grown is planted at once, and its panel opens; one not grown
        -- only opens its panel, whose button goes to the network.
        S.pick.info = nil
        local id = S.hover.seed
        if Profile.ownsSeed(id) and S.pick.seed ~= id then S.pick.seed = id; sound("on")
        elseif S.pick.seedInfo ~= id then sound("panel")
        elseif not Profile.ownsSeed(id) then deny() end
        S.pick.seedInfo = id
        return
    elseif S.hover.back then sound("back"); S.openMenu()
    elseif S.hover.go then setOff()
    elseif S.hover.enemy then
        -- Pinned, so a finger (which has no hover) can see the answers too.
        S.pick.enemy = S.pick.enemy ~= S.hover.enemy and S.hover.enemy or nil
        sound(S.pick.enemy and "select" or "back")
    elseif S.pick and (S.pick.info or S.pick.seedInfo) then
        sound("back")
    end
    if S.pick then S.pick.info, S.pick.seedInfo = nil, nil end
end

local function key(key)
    if key == "escape" or key == "backspace" then
        if S.pick.info or S.pick.seedInfo then S.pick.info, S.pick.seedInfo = nil, nil else S.openMenu() end
        return
    end
    if key == "return" or key == "kpenter" or key == "space" then setOff() return end
    if key == "n" then Network.open() return end
    for _, t in ipairs(D.TOWERS) do
        if key == t.key:lower() then toggleSpecies(t.id) end
    end
end

return {
    open = open,
    draw = draw,
    hover = hover,
    under = under,
    click = click,
    key = key,
}
