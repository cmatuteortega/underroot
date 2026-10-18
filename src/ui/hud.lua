-- A run's own screen: the HUD over the board -- the top strip, the toolbar,
-- the tip line, the boss's health, the mutation cards, the words when the
-- level is won or lost -- and what pointing, pressing and the keys do in it.

local T = require "src.tracer"
local World = require "src.world"
local Game = require "src.game"
local D = require "src.defs"
local Font = require "src.font"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Pixels = require "src.ui.pixels"
local Toolbar = require "src.ui.toolbar"
local Panel = require "src.ui.panel"
local View = require "src.ui.view"
local flair = require "src.ui.flair"
local Run = require "src.ui.run"
local Loadout = require "src.ui.loadout"
local Guide = require "src.ui.guide"

local floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt
local color, box, text, label, centred, wrapLines, say, inside =
    Draw.color, Draw.box, Draw.text, Draw.label, Draw.centred, Draw.wrapLines, Draw.say, Draw.inside
local blit, icon = Pixels.blit, Pixels.icon
local BUTTONS, buttonRect, waveRect, barTop, turnRect =
    Toolbar.BUTTONS, Toolbar.buttonRect, Toolbar.waveRect, Toolbar.barTop, Toolbar.turnRect
local info, freeSpan = Panel.info, Panel.freeSpan
local toHud, cursor, zoomBy, turnCamera = View.toHud, View.cursor, View.zoomBy, View.turnCamera
local sound, deny = flair.sound, flair.deny
local TOP, TURN_TIME = S.TOP, S.TURN_TIME

local function members(set)
    local k = 0
    for _ in pairs(set or {}) do k = k + 1 end
    return k
end

-- The mutation picker: three cards across the middle, or down it on a narrow screen.
local MW, MH = 118, 40
local function mutationCards()
    local list = S.game.choices or {}
    local n = #list
    local cards = {}
    if S.vw - S.inset.l - S.inset.r >= n * MW + (n - 1) * 6 + 8 then
        local x0 = floor((S.vw - (n * MW + (n - 1) * 6)) / 2)
        for k = 1, n do cards[k] = { x = x0 + (k - 1) * (MW + 6), y = floor(S.vh / 2) - 18, w = MW, h = MH, m = list[k] } end
    else
        local y0 = floor(S.vh / 2 - (n * MH + (n - 1) * 4) / 2)
        for k = 1, n do cards[k] = { x = floor((S.vw - MW) / 2), y = y0 + (k - 1) * (MH + 4), w = MW, h = MH, m = list[k] } end
    end
    return cards
end

-- What a won level offers, a button each across the middle under the words:
-- the next level (if there is one), endless, again, the levels. Two rows if
-- one does not fit across.
local function wonButtons()
    local list = {}
    local last = S.level == D.LEVELS[#D.LEVELS]
    if not last then list[#list + 1] = { id = "next", text = "NEXT LEVEL", key = "N" } end
    list[#list + 1] = { id = "endless", text = "GO ENDLESS", key = "E" }
    list[#list + 1] = { id = "again", text = "AGAIN", key = "R" }
    list[#list + 1] = { id = "levels", text = "LEVELS", key = "M" }
    local gap = 4
    local function width(from, to)
        local w = gap * (to - from)
        for k = from, to do w = w + list[k].w end
        return w
    end
    for _, b in ipairs(list) do
        if not S.touch then b.text = b.key .. ": " .. b.text end
        b.w, b.h = Font.width(b.text) + 10, 15
    end
    local rows = { { 1, #list } }
    if width(1, #list) > S.vw - S.inset.l - S.inset.r - 8 then
        local half = ceil(#list / 2)
        rows = { { 1, half }, { half + 1, #list } }
    end
    local y = floor(S.vh / 2) - 1
    for _, row in ipairs(rows) do
        local x = floor((S.vw - width(row[1], row[2])) / 2)
        for k = row[1], row[2] do list[k].x, list[k].y = x, y; x = x + list[k].w + gap end
        y = y + 15 + gap
    end
    list.bottom = y
    return list
end

local function nodeScreen(n)
    local i, j = S.world:toImage(n.x, n.y + (n.heart and 10 or 5), n.z)
    return i, j
end

local function waveSummary(wave)
    local count = {}
    for _, g in ipairs(wave) do
        count[g[1]] = count[g[1]] or 0
        count[g[1]] = count[g[1]] + g[2] * (g[1] == "mite" and D.ENEMIES.mite.swarm or 1)
    end
    local parts = {}
    if wave.weather then parts[1] = D.WEATHER[wave.weather].name .. ":" end
    for _, kind in ipairs(D.ENEMY_ORDER) do
        if count[kind] then
            local name = D.ENEMIES[kind].boss and D.ENEMIES[kind].name or D.ENEMIES[kind].short or kind:upper()
            parts[#parts + 1] = (D.ENEMIES[kind].boss and "" or (count[kind] .. " ")) .. name
        end
    end
    return table.concat(parts, "  ")
end

-- A tower's name at its tier: the upgrade's, once it has one.
local function towerName(t)
    if t.branch then return D.TOWER[t.kind].up[t.branch][t.tier].name end
    return D.TOWER[t.kind].name
end

-- What to say at the bottom when nothing is hovered: the next thing to learn.
local function hint()
    if S.game.phase ~= "build" then
        local brine = false
        for _, e in ipairs(S.game.enemies) do if e.kind == "brine" and e.slide then brine = true end end
        if brine then return say("BRINE IN THE NETWORK! PRUNE (X) THE LINK IT IS ON", "BRINE IN THE NETWORK! PRUNE THE LINK IT IS ON"), "r" end
        return nil
    end
    local living = 0
    for _, l in ipairs(S.game.links) do if l.state ~= "cut" then living = living + 1 end end
    local towers = 0
    for _, n in ipairs(S.game.nodes) do if n.tower then towers = towers + 1 end end
    if living == 0 then return "DRAG FROM THE SPROUT TO A POCKET TO GROW A LINK", "g" end
    if towers == 0 then return say("PICK A FRUITING BODY BELOW, THEN CLICK A LINKED POCKET", "PICK A FRUITING BODY BELOW, THEN TAP A LINKED POCKET"), "g" end
    local nxt = S.game:nextWave()
    if nxt then
        for _, g in ipairs(nxt) do
            local e = D.ENEMIES[g[1]]
            if e.boss then return "BOSS NEXT: " .. e.name .. ". " .. e.blurb, "r" end
        end
    end
    if S.game.newSpecies then
        local kind = S.game.newSpecies
        local grown = false
        for _, n in ipairs(S.game.nodes) do if n.tower and n.tower.kind == kind then grown = true end end
        for _, m in ipairs(S.game.mats) do if m.kind == kind then grown = true end end
        if not grown then return "NEW SPECIES: " .. D.TOWER[kind].name .. ". " .. D.TOWER[kind].blurb, "l" end
    end
    if nxt then
        for _, g in ipairs(nxt) do
            if not S.game.seen[g[1]] then return "NEW: " .. D.ENEMIES[g[1]].name .. ". " .. D.ENEMIES[g[1]].blurb, "t" end
        end
        if nxt.weather then
            local wx = D.WEATHER[nxt.weather]
            return wx.name .. " NEXT WAVE: " .. wx.blurb, "s"
        end
    end
    if S.selected and S.game:upgrades(S.selected)[1] and S.game.wave <= 2 then
        return say("UPGRADES: CLICK ONE IN THE PANEL, OR Z / C", "UPGRADES: TAP ONE IN THE PANEL"), "l"
    end
    if S.game.wave == 0 then return say("SPACE TO START THE FIRST WAVE", "TAP START FOR THE FIRST WAVE"), "g" end
end

local function tooltip()
    if S.hover.mutation then
        local m = S.game.choices[S.hover.mutation]
        return (m.seed and (S.game.seed.short .. " ") or "") .. m.name .. ": " .. m.blurb, m.seed and "g" or "l"
    end
    if S.game.phase == "mutate" then return say("THE NETWORK MUTATES. PICK ONE (1 2 3)", "THE NETWORK MUTATES. PICK ONE"), "l" end
    if S.hover.up then
        local ok, why = S.game:canUpgrade(S.selected, S.hover.up.branch)
        return "GROW " .. S.hover.up.row.name .. ": " .. S.hover.up.cost .. (ok and "" or ("  (" .. why .. ")")), ok and "l" or "r"
    end
    if S.hover.button then
        local b = BUTTONS[S.hover.button]
        if b.tower and not S.game:unlocked(b.mode) then
            return b.name .. ": UNLOCKS AFTER WAVE " .. S.game:unlockAt(b.mode), "r"
        end
        if b.action then
            local list, cost = S.game:repairable(), 0
            for _, l in ipairs(list) do cost = cost + S.game:repairCost(l) end
            if #list == 0 then return "REGROW ALL: NO CUT LINKS", "s" end
            return "REGROW " .. #list .. " CUT LINK" .. (#list > 1 and "S" or "") .. ", NEAREST THE SPROUT FIRST: " .. cost,
                S.game.nutrients >= cost and "l" or "r"
        end
        if b.tower and b.mode == S.mode then return say(b.name .. ": CLICK AGAIN TO READ IT", b.name .. ": TAP AGAIN TO READ IT"), "w" end
        return b.name .. (b.cost and (" (" .. b.cost .. ")") or "") .. ": " .. b.blurb, "w"
    end
    if S.hover.turn == 1 then return say("TURN THE BOARD (E)", "TURN THE BOARD"), "w" end
    if S.hover.turn == -1 then return say("TURN THE BOARD BACK (Q)", "TURN THE BOARD BACK"), "w" end
    if S.hover.wave then
        return S.game.phase == "build" and say("START THE NEXT WAVE (SPACE)", "START THE NEXT WAVE") or say("GAME SPEED (F)", "GAME SPEED"), "w"
    end
    if S.mode == "grow" and S.drag and S.hover.node and S.hover.node ~= S.drag then
        local ok, cost, why = S.game:canLink(S.drag, S.hover.node)
        if ok then return "GROW LINK: " .. cost, "l" end
        return (why or "") .. (cost and ("  (" .. cost .. ")") or ""), "r"
    end
    if S.mode == "pulse" and S.hover.node then
        if S.game.pulseCd > 0 then return "PULSE REGROWING: " .. math.ceil(S.game.pulseCd) .. "S", "r" end
        if not S.hover.node.conn then return "NOT FED: THE PULSE CANNOT REACH IT", "r" end
        return "SEND THE PULSE HERE", "l"
    end
    if S.hover.node and S.hover.node.tower then
        local t = S.hover.node.tower
        local s = towerName(t)
        if S.mode == "prune" then return "CLEAR " .. s .. ": +" .. floor(t.spent * D.SELL), "r" end
        if t.webbed > 0 then s = s .. ": WEBBED SHUT"
        elseif t.stun > 0 then s = s .. ": STUNNED"
        elseif t.hunger == "dormant" then s = s .. ": DORMANT, NO NUTRIENTS"
        elseif not S.hover.node.conn then s = s .. ": CUT OFF, ON ITS RESERVE"
        elseif t.thirsty then s = s .. ": THIRSTY, NEEDS A RELAY BESIDE IT"
        elseif t.hunger == "starved" then s = s .. ": STARVED" end
        if t.hp < S.game:maxHp(t) then s = s .. "  HP " .. math.ceil(t.hp) end
        if t.kind == "puffer" then s = s .. "  PUFFS " .. max(1, min(4, S.game:degree(S.hover.node))) end
        if t.kind == "needle" and S.game:degree(S.hover.node) == 1 then s = s .. "  DEAD END X1.8" end
        if t.kind == "lamp" then s = s .. "  GLOW " .. floor(t.glow or 0) end
        if t.kind == "mane" then s = s .. "  TENDS " .. members(t.care) .. " NODES" end
        if t.kind == "relay" then s = s .. "  PUMPS INTO " .. #S.game:neighbours(S.hover.node) end
        if t.kind == "inky" then s = s .. "  FEEDS " .. #S.game:neighbours(S.hover.node) .. " FIRST" end
        if t.kind == "cordyceps" then s = s .. "  HOLD X" .. string.format("%.1f", S.game:deepHold(t)) end
        if t.kind == "stink" then s = s .. "  REEKS DOWN " .. S.game:degree(S.hover.node) .. " LINKS" end
        if t.kind == "mortar" and S.hover.node.pocket.high then s = s .. "  HIGH: NO MIN RANGE" end
        if t.kind == "agaric" then
            local k = S.game:degree(S.hover.node)
            s = s .. (k == 2 and "  BRIDGE X1.5" or "  X0.75: NEEDS TWO LINKS")
        end
        if t.kind == "earthstar" then s = s .. "  HEARS " .. floor(S.game:towerRange(t)) end
        if t.kind == "oyster" then
            local d = D.TOWER.oyster
            s = s .. "  X" .. string.format("%.2f", max(d.outer, d.inner - d.perHop * (S.game:depth(S.hover.node) - 1)))
        end
        if t.kind == "tooth" then s = s .. "  SAPS " .. members(S.game:touches(t)) .. " NODES" end
        if t.kind == "truffle" then s = s .. "  " .. (t.streak or 0) .. " WAVES UNCUT" end
        if t.kind == "turkey" then s = s .. "  HASTENS " .. members(t.care) end
        if (t.haste or 1) > 1 then s = s .. "  +" .. floor((t.haste - 1) * 100 + 0.5) .. "% PACE" end
        if t.kind == "giant" then
            local k = S.game:rooted(t)
            if t.grown < 1 then s = s .. "  GROWING " .. floor(t.grown * 100) .. "%"
            else s = s .. "  " .. k .. " NODES: HITS " .. floor(S.game:stat(t, "damage") + S.game:stat(t, "perNode") * k) end
        end
        if S.hover.node.ringed then s = s .. "  RING" end
        if (t.amp or 1) > 1 then s = s .. "  AMPED" end
        return s .. "  " .. S.hover.node.quality:upper() .. " POCKET", "w"
    end
    if S.hover.node then
        local n = S.hover.node
        if n.heart then
            -- The seed it grew from, and what it has left to give.
            local sd = S.game.seed
            local s = sd.name .. ": " .. (sd.id ~= "bean" and sd.blurb or "IF IT DIES, YOU LOSE")
            if S.game.regrows > 0 then s = s .. ". REGROWS " .. S.game.regrows .. " MORE" end
            if S.game.pods > 0 then s = s .. ". " .. S.game.pods .. " FREE LINKS" end
            return s, "g"
        end
        local s = n.pocket.kind:upper() .. ": " .. n.quality:upper() .. " POCKET"
        if (n.salted or 0) > 0 then s = s .. ", SALTED" end
        if n.quality == "rich" then s = s .. ". +30% POWER, PAYS SUGAR" elseif n.quality == "poor" then s = s .. ". -25% POWER" end
        if n.pocket.high then s = s .. ". HIGH GROUND" elseif n.pocket.low then s = s .. ". LOW: RAIN WASHES IT" end
        if D.TOWER[S.mode] and not D.TOWER[S.mode].onTrail then
            local ok, why = S.game:canBuild(S.mode, n)
            if ok then return "GROW " .. D.TOWER[S.mode].name .. " HERE: " .. S.game:towerCost(S.mode), "l" end
            if why then return why, "r" end
        end
        return s, "w"
    end
    if S.hover.link then
        local l = S.hover.link
        if S.mode == "prune" then
            return "PRUNE LINK: +" .. floor(l.cost * (l.state == "alive" and D.LINK.prune or D.LINK.prune * 0.5)), "r"
        end
        if l.state == "cut" then
            if l.salted then return "SALTED LINK. IT WILL NOT REGROW: PRUNE IT", "w" end
            if l.hand then return "REGROWING", "l" end
            return say("CUT LINK. CLICK TO REGROW: ", "CUT LINK. TAP TO REGROW: ") .. S.game:repairCost(l), "l"
        end
        if l.state == "grow" then return "GROWING", "l" end
        local s = "LINK " .. floor(l.hp) .. "/" .. floor(S.game:linkHp()) .. "  FLOW " .. (l.cap or D.LINK.cap)
        if l.thick then s = s .. " (RELAY)" end
        if not l.a.conn then s = s .. "  NOT FED" end
        return s, "w"
    end
    if D.TOWER[S.mode] and D.TOWER[S.mode].onTrail and S.hover.c then
        local d = D.TOWER[S.mode]
        local ok, why = S.game:canLay(S.mode, S.hover.c, S.hover.r)
        if ok then return "GROW " .. d.name .. ": " .. S.game:towerCost(d.id), "l" end
        if not S.world:distAt(S.hover.c, S.hover.r) then return d.name .. " GOES ON THE TRAIL", "r" end
        return why or "", "r"
    end
    if S.mode == "prune" and S.hover.mat then return "LIFT " .. D.TOWER[S.hover.mat.kind].name .. ": +" .. S.game:liftValue(S.hover.mat), "r" end
    if S.hover.mat and S.mode == "grow" then
        local m = S.hover.mat
        local s = towerName(m)
        if m.kind == "mat" then
            s = s .. (m.fed and (": " .. m.draped .. " LINK" .. (m.draped > 1 and "S" or "") .. " OVER IT")
                or ": WITHERING " .. math.ceil(m.life) .. "S")
            s = s .. "  SLOW " .. floor((1 - S.game:matSlow(m)) * 100) .. "%"
        else s = s .. "  HP " .. math.ceil(m.hp) .. "/" .. S.game:maxHp(m) end
        return s, "w"
    end
    if S.mode == "grow" and S.drag then return say("LET GO OVER A GLOWING POCKET", "LET GO OVER A GLOWING POCKET"), "l" end
    if S.mode == "pulse" then
        if S.game.pulseCd > 0 then return "PULSE REGROWING: " .. math.ceil(S.game.pulseCd) .. "S", "r" end
        return say("CLICK A FED NODE TO SEND THE PULSE", "TAP A FED NODE TO SEND THE PULSE"), "l"
    end
end

-- A turn button: a ring of ground going round, an arrowhead on its end, and
-- a mark on the ring for the side the camera is on. d = -1 is the clockwise
-- one mirrored.
local function drawTurnButton(d)
    local x, y, w, h = turnRect(d)
    local going = S.turning and S.turning.d == d
    box(x, y, w, h, (S.hover.turn == d or going) and "n" or "u", S.hover.turn == d and "t" or "o")
    local cx, cy = x + floor(w / 2), y + floor(h / 2) + 1
    local spin = S.turning and S.turning.t / TURN_TIME * (S.turning.angle > 0 and 1 or -1) * d or 0
    local function at(a, rx, ry) return cx + floor(d * math.cos(a) * rx + 0.5), cy + floor(math.sin(a) * ry + 0.5) end
    -- The ring is the ground seen from the camera: twice as wide as it is deep.
    color("k")
    for s = 0, 23 do
        local i, j = at(s / 24 * 2 * math.pi, 7, 4)
        love.graphics.rectangle("fill", i, j, 1, 1)
    end
    color("w")
    local a0 = (spin - 0.15) * math.pi * 0.5
    for s = 0, 12 do
        local i, j = at(a0 + s / 24 * 2 * math.pi, 7, 4)
        love.graphics.rectangle("fill", i, j, 1, 1)
    end
    -- The arrowhead at the end of the arc, pointing on round.
    local ae = a0 + 12 / 24 * 2 * math.pi
    local i, j = at(ae, 7, 4)
    love.graphics.rectangle("fill", i - 1, j - 1, 3, 1)
    love.graphics.rectangle("fill", i, j - 2, 1, 1)
    love.graphics.rectangle("fill", i - d, j - 1, 1, 3)
    -- Which side: a dot per view, the one shown lit.
    for q = 0, World.TURNS - 1 do
        color(q == S.world.turn and "l" or "k")
        love.graphics.rectangle("fill", x + 3 + q * 2, y + 2, 1, 1)
    end
    if not S.touch then text(d == 1 and "E" or "Q", x + w - 4, y + 1, "s") end
end

local function draw()
    -- The top strip.
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.inset.t + TOP - 1)
    local ty = S.inset.t + 3
    local inc = S.game.income or 0
    local s = "NUTRIENTS " .. floor(S.game.nutrients)
    -- Short of them: red, and a shiver. A lot just in: bright.
    local nk, nx = "l", 0
    if flair.nut.t > 0 then
        nk = flair.nut.k
        if nk == "r" then nx = floor(flair.nut.t * 30) % 2 == 0 and 1 or -1 end
    end
    text(s, S.inset.l + 3 + nx, ty, nk)
    local x = S.inset.l + 3 + Font.width(s) + 2
    if S.game.phase == "wave" then
        local i = (inc >= 0 and "+" or "") .. string.format("%.1f", inc)
        text(i, x + 2, ty, inc >= 0 and "c" or "r")
        x = x + Font.width(i) + 4
    end
    s = "SPROUT " .. math.ceil(S.game.heartHp) .. "/" .. S.game.heartMax
    text(s, x + 8, ty, S.game.heartHp < S.game.heartMax * 0.4 and "r" or "g")
    local w = "WAVE " .. S.game.wave .. "/" .. #S.game.waves
    if S.game.endless then w = "ENDLESS WAVE " .. S.game.wave .. "  BEST " .. max(S.game.best, S.game.cleared) end
    local nxt = S.game:nextWave()
    local right = w
    if nxt and S.game.phase == "build" then right = "NEXT: " .. waveSummary(nxt) .. "   " .. w end
    if S.game.phase == "wave" then
        local left = #S.game.queue
        for _ in ipairs(S.game.enemies) do left = left + 1 end
        right = left .. " LEFT   " .. w
        if S.game.weather then right = D.WEATHER[S.game.weather].name .. "   " .. right end
    end
    local leftEnd = x + 8 + Font.width(s) + 8
    local rx = S.vw - S.inset.r - Font.width(right) - 3
    -- A narrow screen keeps the wave count and lets the forecast go: the
    -- gates still say how many come in at each.
    if rx < leftEnd and right ~= w then right = w; rx = S.vw - S.inset.r - Font.width(w) - 3 end
    text(right, rx, ty, "w")
    -- Where the weather's name landed, if it is there: the whole strip's
    -- height and a little either side, to be easy to hover or tap.
    S.weatherBox = nil
    local sky = S.game.phase == "wave" and S.game.weather or (S.game.phase == "build" and nxt and nxt.weather)
    if sky and right ~= w then
        local name = D.WEATHER[sky].name
        local nx = S.game.phase == "build" and rx + Font.width("NEXT: ") or rx
        S.weatherBox = { x = nx - 3, y = 0, w = Font.width(name) + 6, h = S.inset.t + TOP, kind = sky, next = S.game.phase == "build" }
    end
    if S.weatherTip and not (S.weatherBox and S.weatherBox.kind == S.weatherTip) then S.weatherTip = nil end
    if S.weatherBox and (S.weatherTip or (not S.touch and S.hover.weather)) then
        local wb = S.weatherBox
        local nm = D.WEATHER[wb.kind].name
        text(nm, wb.x + 3, ty, "t")
    end
    if S.paused then
        if S.touch then centred("PAUSED. TAP THE TOP BAR TO GO ON", floor(S.vh / 2) - 40, "r")
        else text("PAUSED", floor((S.vw - Font.width("PAUSED")) / 2), ty, "r") end
    end

    -- Gates: where the next wave comes in.
    if nxt and S.game.phase == "build" then
        local per = {}
        for _, g in ipairs(nxt) do per[g[4]] = (per[g[4]] or 0) + g[2] * (g[1] == "mite" and D.ENEMIES.mite.swarm or 1) end
        for gate, n in pairs(per) do
            local e = S.world.entrances[gate]
            if e then
                local i, j = S.world:toImage(e.x - 6, S.world:groundAt(e.x, e.z) + 6, e.z)
                local sx, sy = toHud(i, j)
                if floor(S.game.clock * 2) % 2 == 0 then label(n .. " IN", sx - 6, sy - 10, "w", "r") end
            end
        end
    end

    -- The sprout pointed at (or tapped): the seed it grew from, over it.
    if S.hover.node == S.game.heart then
        local h = S.game.heart
        local sx, sy = toHud(S.world:toImage(h.x, h.y + 30, h.z))
        local name = S.game.seed.name
        label(name, sx - floor(Font.width(name) / 2), sy - 4, "g", "o")
    end

    -- Words in the world.
    for _, t in ipairs(S.game.texts) do
        local i, j = S.world:toImage(t.x, t.y, t.z)
        local sx, sy = toHud(i, j)
        sx = sx - floor(Font.width(t.text) / 2)
        text(t.text, sx, sy + 1, "o")
        text(t.text, sx, sy, t.k)
    end

    -- The toolbar.
    for n, b in ipairs(BUTTONS) do
        local bx, by, bw, bh = buttonRect(n)
        local on = S.mode == b.mode
        box(bx, by, bw, bh, on and "n" or "u", on and "l" or (S.hover.button == n and "t" or "o"))
        local cx = bx + floor(bw / 2)
        if b.action then
            -- A thread with a gap in it, the two ends lit while there are cuts
            -- to mend; how many, and what it all costs.
            local list, cost = S.game:repairable(), 0
            for _, l in ipairs(list) do cost = cost + S.game:repairCost(l) end
            local any = #list > 0
            for s = 0, 14 do
                if s < 5 or s > 9 then
                    color("d")
                    love.graphics.rectangle("fill", bx + 8 + s, by + 15 - floor(s / 2) + 1, 1, 1)
                    color(any and ((s == 4 or s == 10) and "r" or "c") or "k")
                    love.graphics.rectangle("fill", bx + 8 + s, by + 15 - floor(s / 2), 1, 1)
                end
            end
            if any then
                local c = tostring(cost)
                text(c, bx + bw - Font.width(c) - 1, by + bh - 6, S.game.nutrients >= cost and "l" or "r")
                local k = tostring(#list)
                text(k, bx + bw - Font.width(k) - 1, by + 1, "w")
            end
        elseif b.mode == "prune" then
            text("X", cx - 1, by + 9, "r")
        elseif b.mode == "pulse" then
            local ready = S.game.pulseCd <= 0
            local k = ready and (floor(S.game.clock * 3) % 2 == 0 and "w" or "l") or "d"
            color(k)
            for s = -4, 4 do love.graphics.rectangle("fill", cx + s, by + 12 - floor(abs(s) / 2) * ((s % 2 == 0) and 1 or -1), 1, 1) end
            love.graphics.rectangle("fill", cx - 1, by + 10, 3, 3)
            if not ready then
                local c = tostring(math.ceil(S.game.pulseCd))
                text(c, bx + bw - Font.width(c) - 1, by + bh - 6, "r")
            end
        else
            local open = S.game:unlocked(b.mode)
            local pic = icon(b.mode, nil, 0, on and (S.game.clock * 0.7) % 1 or 0)
            local afford = S.game.nutrients >= (b.cost or 0)
            blit(pic, cx, b.mode == "mat" and by + 14 or by + 21, (not afford or not open) and T.DARKER2 or nil)
        end
        if not S.touch then text(b.key, bx + 1, by + 1, "s") end
        if b.tower and not S.game:unlocked(b.mode) then
            local c = "W" .. S.game:unlockAt(b.mode)
            text(c, bx + bw - Font.width(c) - 1, by + bh - 6, "k")
        elseif b.cost then
            local c = tostring(b.cost)
            text(c, bx + bw - Font.width(c) - 1, by + bh - 6, S.game.nutrients >= b.cost and "l" or "r")
        end
    end
    local wx, wy, ww, wh = waveRect()
    if S.game.phase == "build" then
        box(wx, wy, ww, wh, S.hover.wave and "m" or "d", "g")
        text("START", wx + floor((ww - Font.width("START")) / 2), wy + 5, "g")
        local s2 = "WAVE " .. (S.game.wave + 1)
        text(s2, wx + floor((ww - Font.width(s2)) / 2), wy + 13, "w")
        if not S.touch then text("SPACE", wx + floor((ww - Font.width("SPACE")) / 2), wy + 20, "s") end
    else
        box(wx, wy, ww, wh, "u", S.hover.wave and "t" or "o")
        local s2 = "SPEED X" .. S.speed
        text(s2, wx + floor((ww - Font.width(s2)) / 2), wy + 9, "w")
        if not S.touch then text("F", wx + floor((ww - 3) / 2), wy + 18, "s") end
    end
    drawTurnButton(1)
    drawTurnButton(-1)

    local tipBase = barTop()

    -- A boss on the board: its name and its health across the top.
    local boss
    for _, e in ipairs(S.game.enemies) do if e.boss then boss = e break end end
    if boss then
        local d = D.ENEMIES[boss.kind]
        local fl, fr = freeSpan()
        local w = min(170, fr - fl - 20)
        local bx, by = floor((fl + fr - w) / 2), S.inset.t + TOP + 3
        -- A train's health is all of its segments'.
        local hp, top = boss.hp, boss.maxHp
        if boss.train then
            hp, top = 0, boss.train.max
            for _, e in ipairs(S.game.enemies) do if e.train == boss.train and not e.dead then hp = hp + e.hp end end
        end
        box(bx, by, w, 4, "u", "o")
        color("r")
        love.graphics.rectangle("fill", bx, by, floor(w * max(0, hp / top)), 4)
        if boss.ballHp and boss.ballHp > 0 then
            box(bx, by + 6, w, 2, "u", "o")
            color("t")
            love.graphics.rectangle("fill", bx, by + 6, floor(w * boss.ballHp / boss.ballMax), 2)
        end
        local name = d.name .. (boss.under and (boss.kind == "mole" and " (UNDERGROUND)" or " (UNDER WATER)") or "")
        text(name, floor(bx + (w - Font.width(name)) / 2), by + (boss.ballHp and boss.ballHp > 0 and 11 or 7), "w")
    end
    if S.game.bossIntro then
        local d = D.ENEMIES[S.game.bossIntro.kind]
        if floor(S.game.bossIntro.t * 4) % 4 ~= 0 or S.game.bossIntro.t < 2.5 then
            centred(d.name, S.inset.t + TOP + 22, "r", "o")
        end
        centred(d.blurb, S.inset.t + TOP + 33, "w", "o")
    end

    -- One line of help above the toolbar.
    local tip, k = tooltip()
    -- The guide says it already, at the top.
    if not tip and not Guide.talking() then tip, k = hint() end
    if tip then
        -- Too long for the screen (a phone held upright): broken at a word onto
        -- a second line above, rather than cut off.
        local fl, fr = freeSpan()
        local room = fr - fl - 8
        local lines = { tip }
        if Font.width(tip) > room then
            local cut
            for i = #tip, 1, -1 do
                if tip:sub(i, i) == " " and Font.width(tip:sub(1, i - 1)) <= room then cut = i break end
            end
            if cut then lines = { tip:sub(1, cut - 1), tip:sub(cut + 1) } end
        end
        for n, l in ipairs(lines) do
            if Font.width(l) > room then l = l:sub(1, floor(room / 4)) end
            centred(l, tipBase - 11 - (#lines - n) * 10, k, nil, floor((fl + fr) / 2))
        end
    end

    local P = info()
    if P then Panel.draw(P) end

    -- What the weather does, dropped from its name in the top strip.
    local wb = S.weatherBox
    if wb and (S.weatherTip or (not S.touch and S.hover.weather)) then
        local d = D.WEATHER[wb.kind]
        local tw = min(150, S.vw - S.inset.l - S.inset.r - 8)
        local lines = wrapLines(d.blurb, tw - 8)
        local head = d.name .. (wb.next and " NEXT WAVE" or "")
        local th = 13 + 7 * #lines
        local tx = max(S.inset.l + 4, min(S.vw - S.inset.r - 4 - tw, wb.x + floor(wb.w / 2) - floor(tw / 2)))
        local ty = S.inset.t + TOP + 3
        box(tx, ty, tw, th, "u", "t")
        text(head, tx + 4, ty + 3, "t")
        for n, l in ipairs(lines) do text(l, tx + 4, ty + 6 + 7 * n, "w") end
        if S.touch then text("X", tx + tw - 7, ty + 3, "s") end
    end

    if S.game.phase == "mutate" then
        local cs = mutationCards()
        centred("THE NETWORK MUTATES", cs[1].y - 14, "l", "o")
        for k, c in ipairs(cs) do
            -- The seed's own is in its green.
            local own = c.m.seed ~= nil
            box(c.x, c.y, c.w, c.h, S.hover.mutation == k and "n" or "u", S.hover.mutation == k and "l" or (own and "g" or "c"))
            text(c.m.name, c.x + 4, c.y + 4, own and "g" or "l")
            if not S.touch then text(tostring(k), c.x + c.w - 6, c.y + 4, "s") end
            -- The blurb, broken into lines that fit the card.
            local line, y = "", c.y + 14
            for word in c.m.blurb:gmatch("%S+") do
                local try = line == "" and word or line .. " " .. word
                if Font.width(try) > c.w - 8 then
                    text(line, c.x + 4, y, "w")
                    line, y = word, y + 7
                else
                    line = try
                end
            end
            text(line, c.x + 4, y, "w")
        end
    end

    if S.game.phase == "won" then
        centred(S.level.name .. (S.game.challenge and " (CHALLENGE)" or "") .. ": THE SPROUT LIVES", floor(S.vh / 2) - 24, "g")
        centred("KILLS " .. S.game.stats.kills .. "   BOSSES " .. S.game.stats.bosses .. "   DRUNK " .. floor(S.game.stats.drunk) .. "   CUTS " .. S.game.stats.cuts, floor(S.vh / 2) - 12, "w")
        local buttons = wonButtons()
        for _, b in ipairs(buttons) do
            local on = S.hover.won == b.id
            local endless = b.id == "endless"
            box(b.x, b.y, b.w, b.h, on and "n" or "u", endless and "r" or (on and "l" or "c"))
            text(b.text, b.x + 5, b.y + 5, endless and "r" or "w")
        end
        local y = buttons.bottom + 1
        if Profile.records[S.level.id] then centred("ENDLESS BEST: " .. Profile.records[S.level.id] .. " WAVES", y, "t"); y = y + 10 end
        centred("+" .. S.game.spores .. " SPORES   " .. Profile.spores .. " IN THE BANK", y, "t"); y = y + 10
        -- A first win opens more of the network: what, by name.
        for _, row in ipairs(S.game.opened or {}) do centred("NEW ON THE NETWORK: " .. row.name, y, "g"); y = y + 10 end
        for _, c in ipairs(D.CHALLENGES) do
            if c.won == S.level.id and not S.game.challenge then centred("CHALLENGE MODE IS OPEN: THE " .. c.name, y, "r"); y = y + 10 end
        end
        if (S.game.opened or {})[1] then centred("GROW IT ON THE NETWORK, FROM THE HOME SCREEN", y, "s") end
    elseif S.game.phase == "lost" then
        centred("THE SPROUT HAS WILTED", floor(S.vh / 2) - 24, "r")
        if S.game.endless then
            centred("ENDLESS: YOU HELD " .. S.game.cleared .. " WAVES", floor(S.vh / 2) - 12, "w")
            centred(S.game.record and "A NEW RECORD!" or ("BEST " .. S.game.best), floor(S.vh / 2) + 12, S.game.record and "g" or "t")
        else
            centred("YOU HELD " .. (S.game.wave - 1) .. " WAVES OF " .. #S.game.waves, floor(S.vh / 2) - 12, "w")
        end
        centred(say("R: TRY AGAIN   M: LEVELS", "TAP FOR THE LEVELS"), floor(S.vh / 2), "l")
        centred("+" .. S.game.spores .. " SPORES   " .. Profile.spores .. " IN THE BANK", floor(S.vh / 2) + 24, "t")
        centred("SPORES GROW THE NETWORK, FROM THE HOME SCREEN", floor(S.vh / 2) + 34, "s")
    end
    Guide.draw("run")
end

-- What is pointed at: a won level's button, a mutation card, the panel and its
-- upgrades, a tool, the wave button, a turn button, the weather's word, the
-- top strip; else on the board, the node, link and ground under it.
local function hover(mx, my)
    if Guide.hover(mx, my, "run") then return end
    if S.game.phase == "won" then
        for _, b in ipairs(wonButtons()) do
            if inside(mx, my, b.x, b.y, b.w, b.h) then S.hover.won = b.id return end
        end
    end
    if S.game.phase == "mutate" then
        for k, c in ipairs(mutationCards()) do
            if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.mutation = k return end
        end
    end
    local P = info()
    if P and inside(mx, my, P.x, P.y, P.w, P.h) then
        S.hover.info = true
        for _, l in ipairs(P.lines) do
            if l.up and inside(mx, my, P.x + 3, l.y, P.w - 6, l.h - 3) then S.hover.up = l.up end
        end
        return
    end
    for n = 1, #BUTTONS do
        if inside(mx, my, buttonRect(n)) then S.hover.button = n return end
    end
    if inside(mx, my, waveRect()) then S.hover.wave = true return end
    if inside(mx, my, turnRect(1)) then S.hover.turn = 1 return end
    if inside(mx, my, turnRect(-1)) then S.hover.turn = -1 return end
    local wb = S.weatherBox
    if wb and inside(mx, my, wb.x, wb.y, wb.w, wb.h) then S.hover.weather = wb.kind return end
    if my < S.inset.t + TOP then S.hover.strip = true return end
    local ci, cj = cursor()
    local best, bd = nil, 9
    for _, n in ipairs(S.game.nodes) do
        local i, j = nodeScreen(n)
        local d = sqrt((i - ci) ^ 2 + (j - cj) ^ 2)
        if d < bd then best, bd = n, d end
    end
    S.hover.node = best
    local x, _, z = S.world:pick(ci, cj)
    if x then
        S.hover.x, S.hover.z = x, z
        S.hover.c, S.hover.r = floor(x / World.TILE), floor(z / World.TILE)
        S.hover.mat = S.game:matAt(S.hover.c, S.hover.r)
    end
    if not best then
        local bl, bdist = nil, 3.5
        for _, l in ipairs(S.game.links) do
            local ai, aj = S.world:toImage(l.a.x, l.a.y, l.a.z)
            local bi, bj = S.world:toImage(l.b.x, l.b.y, l.b.z)
            local d = Game.segDist(ci, cj, ai, aj, bi, bj)
            if d < bdist then bl, bdist = l, d end
        end
        S.hover.link = bl
    end
end

-- The box of whatever is pointed at, to light up when it is pressed.
local function under()
    if S.hover.guide then return Guide.under("run") end
    if S.hover.mutation then
        local c = mutationCards()[S.hover.mutation]
        return function() return c.x, c.y, c.w, c.h end
    end
    if S.hover.won then
        local id = S.hover.won
        return function()
            for _, b in ipairs(wonButtons()) do if b.id == id then return b.x, b.y, b.w, b.h end end
            return 0, 0, 0, 0
        end
    end
    if S.hover.button then
        local n = S.hover.button
        return function() return buttonRect(n) end
    end
    if S.hover.wave then return waveRect end
    if S.hover.turn then
        local d = S.hover.turn
        return function() return turnRect(d) end
    end
end

-- Won: one of the buttons, or its key.
local function afterWin(id)
    if id == "endless" then sound("go"); S.game:goEndless()
    elseif id == "again" then sound("go"); Run.start()
    elseif id == "levels" then sound("back"); S.openMenu()
    elseif id == "next" then
        for k, l in ipairs(D.LEVELS) do
            if l == S.level and D.LEVELS[k + 1] then sound("select"); Loadout.open(k + 1) return end
        end
    end
end

local function click(b)
    if b == 1 and Guide.click("run") then return end
    if Guide.holding() then return end
    if S.weatherTip and not S.hover.weather then S.weatherTip = nil end
    if b == 2 then
        if S.mode ~= "grow" or S.drag or S.selected then sound("back") end
        S.mode, S.drag, S.selected = "grow", nil, nil
        return
    end
    if S.game.phase == "mutate" then
        -- The picker holds the game until a mutation is chosen.
        if S.hover.mutation then S.game:mutate(S.hover.mutation) end
        return
    end
    if S.hover.up then
        if not S.game:upgrade(S.selected, S.hover.up.branch) then deny() end
        return
    end
    if S.hover.info then return end
    if S.hover.button then
        -- The tool already in hand, picked again, is put down: the one way to
        -- cancel there is without a right button. A species not yet unlocked
        -- stays in its slot, dark.
        local bt = BUTTONS[S.hover.button]
        if bt.action then
            if S.game:repairAll() == 0 then deny() end
            return
        end
        if bt.tower and not S.game:unlocked(bt.mode) then deny() return end
        local m = bt.mode
        S.drag = nil
        if bt.tower and m == S.mode then
            -- The species in hand, picked again: its panel opens, or shuts. It
            -- stays in hand; a tap on the ground puts it down.
            S.peek, S.selected = S.peek ~= m and m or nil, nil
            sound(S.peek and "panel" or "back")
            return
        end
        S.mode, S.peek = (m == S.mode and m ~= "grow") and "grow" or m, nil
        if S.mode ~= "grow" then S.selected = nil end
        sound(S.mode == "grow" and "back" or "select")
        return
    end
    if S.hover.wave then
        if S.game.phase ~= "build" then S.speed = S.speed % 3 + 1; sound("speed", 0.8 + 0.2 * S.speed)
        elseif Guide.allows("start") then S.game:startWave()
        else deny() end
        return
    end
    if S.hover.turn then turnCamera(S.hover.turn) return end
    if S.game.phase == "won" then
        if S.hover.won then afterWin(S.hover.won) end
        return
    end
    if S.game.phase == "lost" then sound("click"); S.openMenu() return end
    if S.hover.weather then
        -- Not the pause: on a phone a tap opens what the weather does, and
        -- another shuts it. With a mouse, hovering is enough.
        if S.touch then
            S.weatherTip = S.weatherTip ~= S.hover.weather and S.hover.weather or nil
            sound(S.weatherTip and "panel" or "back")
        end
        return
    end
    if S.hover.strip then
        -- No P key on a phone: the top strip is the pause button.
        if S.touch then S.paused = not S.paused; sound(S.paused and "pause" or "unpause") end
        return
    end
    if S.mode == "grow" then
        if S.hover.node then
            if S.drag and S.drag ~= S.hover.node then
                if not S.game:grow(S.drag, S.hover.node) then deny() end
                S.drag, S.selected = nil, nil
            else
                -- A node is picked up as the end of a thread. Its tower is only
                -- selected (and the camera only goes to it) once it is let go
                -- where it was: pulled on to another node, it was a link.
                S.drag, S.tapped = S.hover.node, S.hover.node
            end
        elseif S.hover.link and S.hover.link.state == "cut" then
            if not S.game:repair(S.hover.link) then deny() end
        elseif S.hover.mat then
            S.drag, S.selected = nil, S.hover.mat
            sound("panel")
        else
            if S.selected then sound("back") end
            S.drag, S.selected = nil, nil
        end
    elseif S.mode == "prune" then
        if S.hover.node and S.hover.node.tower then
            S.game:sell(S.hover.node)
        elseif S.hover.link then
            S.game:prune(S.hover.link)
        elseif S.hover.mat then
            S.game:liftMat(S.hover.mat)
        else
            sound("back")
            S.letGo()
        end
    elseif D.TOWER[S.mode] and D.TOWER[S.mode].onTrail then
        -- Off the trail (or off the board) there is nowhere to lay it.
        if S.hover.c and S.world:distAt(S.hover.c, S.hover.r) then
            local m = S.game:lay(S.mode, S.hover.c, S.hover.r)
            if m then S.selected, S.peek = m, nil else deny() end
        else
            sound("back")
            S.letGo()
        end
    elseif S.mode == "pulse" then
        if not S.hover.node then sound("back"); S.letGo()
        elseif S.game:pulse(S.hover.node) then S.mode = "grow"
        else deny() end
    else
        if S.hover.node then
            local t = S.game:build(S.mode, S.hover.node)
            -- Planted, the species is put down: back to growing, with the new
            -- tower selected.
            if t then S.selected, S.peek, S.mode = t, nil, "grow" else deny() end
        else
            sound("back")
            S.letGo()
        end
    end
end

local function key(key)
    if Guide.key(key, "run") then return end
    if key == "=" or key == "+" or key == "kp+" then zoomBy(1) end
    if key == "-" or key == "kp-" then zoomBy(-1) end
    if S.game.phase == "mutate" then
        local n = tonumber(key)
        if n then S.game:mutate(n) end
        return
    end
    if key == "escape" then
        -- Never quits: one key too many and a run is gone. The window's close does that.
        if S.drag or S.mode ~= "grow" or S.selected then
            S.mode, S.drag, S.selected = "grow", nil, nil
            sound("back")
        else
            S.paused = not S.paused
            sound(S.paused and "pause" or "unpause")
        end
    end
    for n, b in ipairs(BUTTONS) do
        if key == b.key:lower() then
            flair.pressed = { t = 0.18, rect = function() return buttonRect(n) end }
            if b.action then
                if S.game:repairAll() == 0 then deny() end
            elseif not (b.tower and not S.game:unlocked(b.mode)) then
                -- Prune or the pulse, its key again, is put down, as its button does.
                local down = not b.tower and S.mode == b.mode
                S.mode, S.drag, S.selected, S.peek = down and "grow" or b.mode, nil, nil, nil
                sound(down and "back" or "select")
            else
                deny()
            end
        end
    end
    if (key == "z" or key == "c") and S.selected then
        local ups = S.game:upgrades(S.selected)
        local u = ups[key == "z" and 1 or #ups]
        if not (u and S.game:upgrade(S.selected, u.branch)) then deny() end
    end
    if key == "space" then
        if S.game.phase == "build" then
            flair.pressed = { t = 0.18, rect = waveRect }
            if Guide.allows("start") then S.game:startWave() else deny() end
        end
    end
    if key == "f" then S.speed = S.speed % 3 + 1; sound("speed", 0.8 + 0.2 * S.speed) end
    if key == "e" and S.game.phase == "won" then afterWin("endless") return end
    if key == "e" then turnCamera(love.keyboard.isDown("lshift", "rshift") and -1 or 1) end
    if key == "q" then turnCamera(-1) end
    if key == "p" then S.paused = not S.paused; sound(S.paused and "pause" or "unpause") end
    if key == "r" and S.game.phase == "won" then afterWin("again")
    elseif key == "r" and (S.game.phase == "lost" or love.keyboard.isDown("lshift")) then sound("go"); Run.start() end
    if key == "m" then
        if S.game.phase == "won" then afterWin("levels") else sound("back"); S.openMenu() end
    end
    -- Won: on to the next level.
    if key == "n" and S.game.phase == "won" then afterWin("next") end
end

return {
    draw = draw,
    hover = hover,
    under = under,
    click = click,
    key = key,
}
