-- The guide: what teaches the game, a thing at a time, as it comes up.
--
-- The first run is the tutorial: straight from the title into the Crack with
-- only the Spore Puffer, the game pausing on a card to say what is what, and a
-- hand (a cursor with a mouse) pointing at the one thing to do next while a
-- line at the top says it -- grow a link, plant a puffer, start the wave,
-- regrow what gets cut, prune. SKIP leaves it at any step; the settings play
-- it again.
--
-- After it, each idea gets its moment the first time it matters: a link cut,
-- the network mutating, a Fairy Ring, rich and poor pockets, high and low
-- ground, the Spore Pulse once it is grown. The first time an enemy, a boss or
-- a weather is coming, a card with its picture says what it does and what
-- answers it. A run over, the Spore Bank and what it can grow now; the
-- network's first visit, where to start on it. Each is shown once, kept in
-- the save (Profile.taught), and the lessons and cards switch off in the
-- settings (Profile.tips).
--
-- A card holds the run while it is up (src/ui/run.lua asks `holding`); the
-- line at the top and the hand never do. Nothing here runs in the shots.

local D = require "src.defs"
local Font = require "src.font"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Toolbar = require "src.ui.toolbar"
local Panel = require "src.ui.panel"
local View = require "src.ui.view"
local flair = require "src.ui.flair"
local codex = require "src.ui.codex"
local N = require "src.network"

local floor, max, min, sin = math.floor, math.max, math.min, math.sin
local color, box, text, wrapLines, say, inside = Draw.color, Draw.box, Draw.text, Draw.wrapLines, Draw.say, Draw.inside
local BUTTONS, buttonRect, waveRect = Toolbar.BUTTONS, Toolbar.buttonRect, Toolbar.waveRect
local toHud = View.toHud
local sound = flair.sound
local TOP = S.TOP

local G = {}

G.card = nil -- the card up: { where, head, body, pic, boss, buttons = { { id, text } }, point, act }
G.queue = {} -- the cards waiting their turn
G.coach = nil -- the tutorial's line and hand: { where, text, at, drag, done }
G.lesson = nil -- a lesson's own line and hand, shown over the tutorial's
G.step = nil -- the tutorial's step, while it runs
G.game = nil -- the run the guide is following

--- where things are -------------------------------------------------------------------------

-- A node, a link's middle, a tool on the toolbar, in HUD pixels.
local function nodeAt(n)
    return toHud(S.world:toImage(n.x, n.y + (n.heart and 10 or 5), n.z))
end
local function linkAt(l)
    return toHud(S.world:toImage((l.a.x + l.b.x) / 2, (l.a.y + l.b.y) / 2 + 3, (l.a.z + l.b.z) / 2))
end
local function buttonAt(mode)
    for n, b in ipairs(BUTTONS) do
        if b.mode == mode then
            local x, y, w, h = buttonRect(n)
            return x + floor(w / 2), y + floor(h / 2)
        end
    end
end

-- The pocket nearest the sprout that a link can reach from it.
local function nearestPocket(g)
    local best, bd
    for _, n in ipairs(g.nodes) do
        if not n.heart and g:canLink(g.heart, n) then
            local d = (n.x - g.heart.x) ^ 2 + (n.z - g.heart.z) ^ 2
            if not bd or d < bd then best, bd = n, d end
        end
    end
    return best
end

-- A linked pocket with nothing on it, fed first.
local function freeLinked(g)
    local best
    for _, n in ipairs(g.nodes) do
        if not n.heart and not n.tower and #n.links > 0 and (not best or (n.conn and not best.conn)) then best = n end
    end
    return best
end

local function towers(g)
    local k = 0
    for _, n in ipairs(g.nodes) do if n.tower then k = k + 1 end end
    return k
end

local function living(g)
    for _, l in ipairs(g.links) do if l.state ~= "cut" then return l end end
end

-- A link cut by an enemy, waiting to be regrown.
local function cutLink(g)
    for _, l in ipairs(g.links) do if l.state == "cut" and not l.salted and not l.hand then return l end end
end

--- cards ------------------------------------------------------------------------------------

-- A card up, or after the ones already waiting. `act(id)` hears the button.
function G.show(c)
    c.where = c.where or "run"
    c.buttons = c.buttons or { { id = "ok", text = "OK" } }
    c.t0 = flair.now()
    if G.card then G.queue[#G.queue + 1] = c else G.card = c; sound("panel") end
end

local function close(id)
    local c = G.card
    G.card = table.remove(G.queue, 1)
    if G.card then G.card.t0 = flair.now() end
    sound(id == "ok" and "select" or "back")
    if c.act then c.act(id) end
end

-- Is the run held for a card?
function G.holding() return G.card ~= nil and G.card.where == "run" end
-- Is the guide saying something on the board: a card, or its line at the top?
function G.talking()
    return G.holding() or (G.coach ~= nil and G.coach.where == "run") or (G.lesson ~= nil and G.lesson.where == "run")
end

local PIC = 44
local function cardLayout(c)
    -- In the room the panel leaves, on the board; across the middle elsewhere.
    local fl, fr = S.inset.l, S.vw - S.inset.r
    if c.span then fl, fr = c.span() elseif c.where == "run" then fl, fr = Panel.freeSpan() end
    local w = min(214, fr - fl - 12)
    local tx = c.pic and PIC + 6 or 0
    local lines = wrapLines(c.body, w - 10 - tx)
    if c.answer then
        for _, l in ipairs(wrapLines(c.answer, w - 10 - tx)) do lines[#lines + 1] = { s = l, k = "l" } end
    end
    local h = max(15 + 7 * #lines, c.pic and PIC + 4 or 0) + 4 + 13 + 5
    local x = floor((fl + fr - w) / 2)
    -- Under the banner a wave's end puts up, and clear of what it points at:
    -- under it if that is high, over it if low.
    local at = 0.56
    if c.point then
        local _, py = c.point()
        if py then at = py < S.vh / 2 and 0.66 or 0.3 end
    end
    local y = max(S.inset.t + TOP + 4, min(S.vh - S.inset.b - h - 4, floor(S.vh * at - h / 2)))
    local L = { x = x, y = y, w = w, h = h, tx = x + 5 + tx, lines = lines, buttons = {} }
    local bx = x + w - 5
    for k = #c.buttons, 1, -1 do
        local b = c.buttons[k]
        local bw = Font.width(b.text) + 10
        bx = bx - bw
        L.buttons[k] = { x = bx, y = y + h - 5 - 13, w = bw, h = 13, id = b.id, text = b.text }
        bx = bx - 4
    end
    return L
end

-- The hand, or a cursor with a mouse: its tip at (x, y), pointing up and in.
local HAND = {
    "  oo      ",
    " owwo     ",
    " owwo     ",
    " owwooo   ",
    " owwwwwoo ",
    "oowwwwwwwo",
    "owwwwwwwwo",
    "owwwwwwwwo",
    " owwwwwwo ",
    "  oooooo  ",
}
local ARROW = {
    "o     ",
    "oo    ",
    "owo   ",
    "owwo  ",
    "owwwo ",
    "owwwwo",
    "owwooo",
    "oowo  ",
    "o owo ",
    "   oo ",
}
local function drawHand(x, y, pressed)
    local pic = S.touch and HAND or ARROW
    local ox = S.touch and 2 or 0
    if pressed then
        color("l")
        love.graphics.circle("line", x + 0.5, y + 0.5, 4)
    end
    for j, row in ipairs(pic) do
        for i = 1, #row do
            local ch = row:sub(i, i)
            if ch ~= " " then
                color(ch == "o" and "o" or "w")
                love.graphics.rectangle("fill", x + i - 1 - ox, y + j - 1 + (pressed and 1 or 0), 1, 1)
            end
        end
    end
end

-- A blinking ring round the thing pointed at, and the hand bobbing beside it.
local function point(x, y)
    if not x then return end
    x = max(S.inset.l + 4, min(S.vw - S.inset.r - 12, x))
    y = max(S.inset.t + 4, min(S.vh - S.inset.b - 12, y))
    local now = flair.now()
    if floor(now * 3) % 2 == 0 then
        color("l")
        love.graphics.circle("line", x + 0.5, y + 0.5, 7)
    end
    local bob = floor(2 + 2 * sin(now * 6))
    drawHand(x + bob, y + 3 + bob)
end

-- From one place to another and again: a drag, shown.
local function drag(x0, y0, x1, y1)
    if not (x0 and x1) then return end
    local f = (flair.now() % 2) / 2
    local m = min(1, max(0, (f - 0.15) / 0.6))
    m = m * m * (3 - 2 * m)
    local x, y = x0 + (x1 - x0) * m, y0 + (y1 - y0) * m
    color("l")
    love.graphics.circle("line", x1 + 0.5, y1 + 0.5, 7)
    if f > 0.1 and f < 0.85 then
        color("c")
        love.graphics.line(x0 + 0.5, y0 + 0.5, x + 0.5, y + 0.5)
    end
    drawHand(floor(x), floor(y), f > 0.1 and f < 0.85)
end

-- The line at the top and its SKIP, under the strip, in the room the panel leaves.
local function coachLayout(c)
    local fl, fr = Panel.freeSpan()
    local w = min(232, fr - fl - 8)
    local lines = wrapLines(c.text(), w - 8)
    local h = 4 + 7 * #lines + 1
    local x = floor((fl + fr - w) / 2)
    local y = S.inset.t + TOP + 3
    local L = { x = x, y = y, w = w, h = h, lines = lines }
    if c.skip then
        local s = "SKIP TUTORIAL"
        L.skip = { x = x + w - Font.width(s) - 8, y = y + h + 3, w = Font.width(s) + 8, h = 11, s = s }
    end
    return L
end

-- What the guide draws on the screen `where` ("run" or "network"): the line
-- and the hand under any card, the card on top.
function G.draw(where)
    local c = G.lesson and G.lesson.where == where and G.lesson or (G.coach and G.coach.where == where and G.coach)
    if c and not (G.card and G.card.where == where) then
        if c.text then
            local L = coachLayout(c)
            box(L.x, L.y, L.w, L.h, "u", "l")
            for n, l in ipairs(L.lines) do text(l, L.x + 4, L.y + 3 + (n - 1) * 7, "l") end
            if L.skip then
                local k = L.skip
                box(k.x, k.y, k.w, k.h, S.hover.guide == "skip" and "n" or "u", S.hover.guide == "skip" and "t" or "k")
                text(k.s, k.x + 4, k.y + 3, "s")
            end
        end
        if c.drag then drag(c.drag())
        elseif c.at then point(c.at()) end
    end
    local card = G.card
    if not card or card.where ~= where then return end
    local L = cardLayout(card)
    if card.point then point(card.point()) end
    box(L.x, L.y, L.w, L.h, "u", card.boss and "r" or "l")
    if card.pic then
        box(L.x + 5, L.y + 5, PIC, PIC, "o", "k")
        codex.drawFigure(1, card.pic, L.x + 5, L.y + 5, PIC, PIC, 6, false, codex.FACE, (flair.now() * 0.8) % 1)
    end
    text(card.head, L.tx, L.y + 5, card.boss and "r" or "t")
    for n, l in ipairs(L.lines) do
        if type(l) == "table" then text(l.s, L.tx, L.y + 8 + n * 7, l.k) else text(l, L.tx, L.y + 8 + n * 7, "w") end
    end
    for k, b in ipairs(L.buttons) do
        local on = S.hover.guide == b.id
        local first = k == 1
        box(b.x, b.y, b.w, b.h, on and "n" or (first and "d" or "u"), on and "t" or (first and "l" or "k"))
        text(b.text, b.x + 5, b.y + 4, first and "l" or "s")
    end
end

-- What is pointed at of the guide's, on `where`: true if the guide takes the
-- pointer (a card takes all of it).
function G.hover(mx, my, where)
    local card = G.card
    if card and card.where == where then
        for _, b in ipairs(cardLayout(card).buttons) do
            if inside(mx, my, b.x, b.y, b.w, b.h) then S.hover.guide = b.id return true end
        end
        S.hover.guide = "card"
        return true
    end
    local c = G.coach
    if c and c.where == where and c.skip and c.text and not G.lesson then
        local k = coachLayout(c).skip
        if inside(mx, my, k.x, k.y, k.w, k.h) then S.hover.guide = "skip" return true end
    end
    return false
end

-- The box to light up when it is pressed.
function G.under(where)
    local id = S.hover.guide
    if not id or id == "card" then return end
    return function()
        if id == "skip" and G.coach then
            local k = coachLayout(G.coach).skip
            if k then return k.x, k.y, k.w, k.h end
        elseif G.card and G.card.where == where then
            for _, b in ipairs(cardLayout(G.card).buttons) do if b.id == id then return b.x, b.y, b.w, b.h end end
        end
        return 0, 0, 0, 0
    end
end

-- A press: true if the guide took it.
function G.click(where)
    local id = S.hover.guide
    if G.card and G.card.where == where then
        if id and id ~= "card" then close(id) end
        return true
    end
    if id == "skip" then G.skip() return true end
    return false
end

-- A key: with a card up, RETURN, SPACE or ESCAPE is its first button, and
-- nothing else gets through.
function G.key(key, where)
    if not (G.card and G.card.where == where) then return false end
    if key == "return" or key == "kpenter" or key == "space" or key == "escape" then close(G.card.buttons[1].id) end
    return true
end

--- the tutorial ------------------------------------------------------------------------------

-- Straight into the Crack, the Spore Puffer the one species, the guide at
-- every step. From the title on a first run, or the settings.
function G.tutorial()
    S.tutorial = true
    S.challenge, S.chosen = false, { "puffer" }
    Profile.taught.cut = nil
    G.game = nil
    require("src.ui.run").play(1)
end

-- Done with it, by the end or a SKIP: kept, never shown again unless asked.
function G.skip()
    if not S.tutorial then return end
    S.tutorial, G.step, G.coach = false, nil, nil
    G.queue = {}
    if G.card and G.card.tutorial then G.card = nil end
    sound("back")
    Profile.teach("tutorial")
end

local function coach(t)
    t.where, t.skip = "run", true
    return t
end

-- The steps: a card to read (shown once `ready`), or a line and a hand that
-- stay until the thing is `done`.
local STEPS = {
    { card = function(g)
        return { head = S.level.name, body = "YOU ARE THE MYCELIUM UNDER THIS SPROUT. BUGS COME DOWN THE TRAIL TO EAT IT: "
            .. "HOLD THEM OFF FOR " .. #g.waves .. " WAVES AND IT LIVES. THIS FIRST TIME, THE SPORE PUFFER IS ALL YOU HAVE.",
            buttons = { { id = "ok", text = "SHOW ME" }, { id = "skip", text = "SKIP TUTORIAL" } } }
    end },
    { coach = function(g)
        return coach({ text = function()
            return say("DRAG FROM THE SPROUT TO THE POCKET IT POINTS AT: A LINK GROWS OUT TO IT",
                "DRAG YOUR FINGER FROM THE SPROUT TO THE POCKET IT POINTS AT: A LINK GROWS OUT TO IT")
        end, drag = function()
            local n = nearestPocket(g)
            if not n then return end
            local x0, y0 = nodeAt(g.heart)
            local x1, y1 = nodeAt(n)
            return x0, y0, x1, y1
        end })
    end, done = function(g) return living(g) ~= nil end },
    { coach = function(g)
        return coach({ text = function()
            if S.mode ~= "puffer" then return "PICK THE SPORE PUFFER, DOWN ON THE BAR" end
            return say("NOW CLICK THE POCKET YOU LINKED: THE PUFFER GROWS THERE", "NOW TAP THE POCKET YOU LINKED: THE PUFFER GROWS THERE")
        end, at = function()
            if S.mode ~= "puffer" then return buttonAt("puffer") end
            local n = freeLinked(g)
            if n then return nodeAt(n) end
        end })
    end, done = function(g) return towers(g) > 0 end },
    { card = function()
        return { head = "NUTRIENTS", body = "LINKS AND TOWERS ARE PAID FOR IN NUTRIENTS, THE COUNT TOP LEFT. A LONGER LINK COSTS "
            .. "MORE. THE SPROUT MAKES MORE WHILE A WAVE IS ON, AND EVERY WAVE CLEARED PAYS A BONUS.",
            point = function() return S.inset.l + 22, S.inset.t + 9 end }
    end },
    { coach = function()
        return coach({ text = function()
            return say("PRESS START (OR SPACE) FOR THE FIRST WAVE. THE BUGS COME IN WHERE IT BLINKS \"IN\"",
                "TAP START FOR THE FIRST WAVE. THE BUGS COME IN WHERE IT BLINKS \"IN\"")
        end, at = function() local x, y, w, h = waveRect() return x + floor(w / 2), y + floor(h / 2) end })
    end, done = function(g) return g.wave >= 1 end, start = true },
    { coach = function()
        return coach({ text = function()
            return "THE PUFFER HITS EVERYTHING NEAR IT, AND PUFFS ONCE MORE FOR EACH LINK IT HAS, UP TO FOUR. "
                .. say("THE SAME BUTTON (OR F) SPEEDS THE GAME UP", "THE SAME BUTTON SPEEDS THE GAME UP")
        end, at = function() local x, y, w, h = waveRect() return x + floor(w / 2), y + floor(h / 2) end })
    end, done = function(g) return g.phase ~= "wave" end },
    { card = function()
        return { head = "WAVE CLEARED", body = "IT PAID A BONUS IN NUTRIENTS, AND " .. D.SPORES.wave .. " SPORES INTO THE "
            .. "SPORE BANK, KEPT FOR GOOD. SPEND THE NUTRIENTS NOW: MORE LINKS, MORE PUFFERS. "
            .. say("CLICK", "TAP") .. " A TOWER TO SEE ITS UPGRADES." }
    end, ready = function(g) return g.phase == "build" end },
    { coach = function(g)
        return coach({ text = function()
            if S.mode ~= "prune" then
                return say("PRUNE (X) CUTS ONE OF YOUR OWN LINKS FOR HALF ITS COST BACK, OR CLEARS A TOWER. PICK IT",
                    "PRUNE CUTS ONE OF YOUR OWN LINKS FOR HALF ITS COST BACK, OR CLEARS A TOWER. PICK IT")
            end
            return say("CLICK A LINK TO PRUNE IT, OR X AGAIN TO PUT IT DOWN. BRINE SLIDES DOWN LINKS: PRUNE AHEAD OF IT",
                "TAP A LINK TO PRUNE IT, OR PRUNE AGAIN TO PUT IT DOWN. BRINE SLIDES DOWN LINKS: PRUNE AHEAD OF IT")
        end, at = function()
            if S.mode ~= "prune" then return buttonAt("prune") end
            local l = living(g)
            if l then return linkAt(l) end
        end })
    end, done = function(g)
        if S.mode == "prune" then G.pruning = true end
        return (G.pruning and S.mode ~= "prune") or g.phase ~= "build"
    end },
    { card = function()
        return { head = "THE NETWORK IS YOURS", body = "GROW IT AS YOU LIKE, AND START EACH WAVE WHEN YOU ARE READY. "
            .. "WHAT IS NEW IS EXPLAINED AS IT COMES. " .. say("P OR ESCAPE PAUSES.", "TAP THE TOP BAR TO PAUSE.") }
    end, last = true },
}

local function nextStep()
    G.step, G.coach, G.shown = G.step + 1, nil, nil
    if not STEPS[G.step] then
        S.tutorial, G.step = false, nil
        Profile.teach("tutorial")
    end
end

-- The tutorial's step, done or shown.
local function tutorial(g)
    local st = STEPS[G.step]
    if not st then return end
    if st.card then
        if G.shown or (st.ready and not st.ready(g)) then return end
        G.shown = true
        local c = st.card(g)
        c.tutorial = true
        c.act = function(id) if id == "skip" then G.skip() else nextStep() end end
        G.show(c)
        return
    end
    if st.done(g) then nextStep() return tutorial(g) end
    G.coach = G.coach or st.coach(g)
end

-- Is this allowed yet? The first wave waits until the tutorial gets to it.
function G.allows(what)
    if what ~= "start" or not S.tutorial or not G.step then return true end
    for k = G.step + 1, #STEPS do if STEPS[k].start then return false end end
    return true
end

--- lessons and first meetings ----------------------------------------------------------------

local function teach(id) Profile.teach(id) end

-- An enemy or boss, or a weather, the first time it is coming.
local function meet(kind)
    local d = D.ENEMIES[kind]
    local answer
    if D.COUNTERS[kind] then
        local names = {}
        for _, k in ipairs(D.COUNTERS[kind]) do names[#names + 1] = D.TOWER[k].name end
        answer = "ANSWERED BY: " .. table.concat(names, ", ")
    end
    G.show({ head = (d.boss and "BOSS: " or "NEW: ") .. d.name, body = d.blurb, answer = answer, pic = kind, boss = d.boss })
    teach(kind)
end
local function weather(id, soon)
    local w = D.WEATHER[id]
    G.show({ head = w.name .. (soon and " NEXT WAVE" or ""), body = w.blurb .. ". IT LASTS THE ONE WAVE." })
    teach(id)
end

local function hasGround(g, key)
    for _, n in ipairs(g.nodes) do if n.pocket and n.pocket[key] then return true end end
    return false
end
local function hasQuality(g)
    for _, n in ipairs(g.nodes) do if n.pocket and n.quality ~= "normal" then return true end end
    return false
end

-- Each idea, the first time it matters: `when` it does, the card it gets,
-- and in `build` only between waves.
local LESSONS = {
    { id = "cut", always = true, when = function(g) return cutLink(g) ~= nil end, show = function(g)
        local l = cutLink(g)
        G.show({ head = "A LINK WAS CUT", body = "BUGS CHEW THE LINKS THAT CROSS THEIR TRAIL. PAST A CUT NOTHING IS FED: "
            .. "TOWERS THERE FIRE ON THEIR RESERVE, THEN GO DORMANT.", point = function() return linkAt(l) end,
            act = function()
                G.lesson = { where = "run", text = function()
                    return say("CLICK THE CUT LINK TO REGROW IT, OR REGROW ALL (1) FOR EVERY CUT AT ONCE",
                        "TAP THE CUT LINK TO REGROW IT, OR REGROW ALL FOR EVERY CUT AT ONCE")
                end, at = function() return linkAt(l) end, done = function() return l.state ~= "cut" or l.hand end }
            end })
    end },
    { id = "mutate", when = function(g) return g.phase == "mutate" end, show = function()
        G.show({ head = "THE NETWORK MUTATES", body = "EVERY FEW WAVES, PICK ONE OF THREE CHANGES. IT LASTS THE REST OF "
            .. "THE RUN. THE NETWORK CAN GROW MORE OF THEM TO PICK FROM." })
    end },
    { id = "quality", build = true, when = hasQuality, show = function()
        G.show({ head = "RICH AND POOR POCKETS", body = "A RICH POCKET (A DEAD BEETLE) GIVES ITS TOWER +30% POWER AND "
            .. "PAYS SUGAR WHILE IT IS FED. A POOR ONE (A PEBBLE) GIVES -25%. " .. say("POINT AT", "TAP") .. " A POCKET TO READ IT." })
    end },
    { id = "ring", build = true, when = function(g) return #g.rings > 0 or g.level.ringNodes ~= nil end, show = function(g)
        local k = g.level.ringNodes or D.RING.nodes
        G.show({ head = "FAIRY RINGS", body = k .. " OR MORE FED POCKETS LINKED IN A LOOP ROUND THE TRAIL CLOSE A FAIRY "
            .. "RING: ITS TOWERS HIT X" .. D.RING.damage .. ", AND WHAT WALKS INSIDE IT WADES AT X" .. D.RING.slow .. "."
            .. (g.level.ringNodes and (" HERE ONLY " .. k .. " ARE NEEDED.") or "") })
    end },
    -- High ground as soon as there is some; low ground once rain is coming to it.
    { id = "high", build = true, when = function(g) return hasGround(g, "high") end, show = function()
        G.show({ head = "HIGH GROUND", body = "A STONE IS HIGH GROUND: THE GIANT WATER BUG CANNOT REACH WHAT GROWS "
            .. "ON IT, AND A MORTAR THERE HAS NO LEAST RANGE." })
    end },
    { id = "low", build = true, when = function(g)
        local nxt = g:nextWave()
        return hasGround(g, "low") and nxt ~= nil and nxt.weather == "rain"
    end, show = function()
        G.show({ head = "LOW GROUND", body = "A LEAF OR A LILY PAD LIES LOW: RAIN WASHES THE RESERVE OFF ITS TOWER. "
            .. "RAIN IS COMING NEXT WAVE." })
    end },
    { id = "ford", build = true, when = function() return S.world.fords end, show = function()
        G.show({ head = "THE FORD", body = "OPEN WATER CUTS THE TRAIL HERE. A DROUGHT DRIES IT TO MUD, AND THE BUGS TAKE "
            .. "THE SHORTCUT ACROSS: LOOK AT THE FORECAST." })
    end },
    { id = "pulse", build = true, when = function(g) return g:hasPulse() end, show = function()
        G.show({ head = "THE SPORE PULSE", body = "IT IS ON THE BAR NOW. PICK IT, THEN A FED NODE: THE TOWERS ON THE WAY "
            .. "THERE FROM THE SPROUT FIRE X" .. D.PULSE.rate .. " AS OFTEN FOR X" .. D.PULSE.damage .. " DAMAGE, FOR "
            .. D.PULSE.duration .. "S. THEN IT REGROWS.", point = function() return buttonAt("pulse") end })
    end },
}

-- What the Spore Bank can grow now: the cheapest open nodes, species first.
function G.openNodes(most)
    local list = {}
    for k, row in ipairs(D.NETWORK) do
        local st = Profile.nodeState(row.id)
        if st == "open" or st == "poor" then
            list[#list + 1] = { row = row, k = k, price = N.price(Profile.ranks(), row.id) or 0, open = st == "open",
                species = row.species ~= nil }
        end
    end
    table.sort(list, function(a, b)
        if a.open ~= b.open then return a.open end
        if a.species ~= b.species then return a.species end
        if a.price ~= b.price then return a.price < b.price end
        return a.k < b.k
    end)
    local out = {}
    for k = 1, min(most or #list, #list) do out[k] = list[k] end
    return out
end

-- The run over: the bank, and what it opens on the network.
local function bank(g)
    local open = G.openNodes(3)
    local names = {}
    for _, o in ipairs(open) do if o.open then names[#names + 1] = o.row.name .. " (" .. o.price .. ")" end end
    local body = "THIS RUN EARNED " .. g.spores .. " SPORES, AND THE BANK HOLDS " .. Profile.spores .. ". THEY STAY, WIN "
        .. "OR LOSE, AND GROW THE NETWORK UNDER THE SPROUT: NEW SPECIES, TOUGHER LINKS, THE SPORE PULSE."
    if #names > 0 then body = body .. " OPEN NOW: " .. table.concat(names, ", ") .. "."
    elseif open[1] then body = body .. " NEXT: " .. open[1].row.name .. " FOR " .. open[1].price .. "." end
    -- No new species open yet: the nearest, and what it grows off.
    if not (open[1] and open[1].species) then
        for _, row in ipairs(D.NETWORK) do
            local up = row.at and D.NET[row.at]
            if row.species and Profile.nodeState(row.id) == "shut" and up then
                local st = Profile.nodeState(up.id)
                if st == "open" or st == "poor" then
                    body = body .. " A NEW SPECIES, THE " .. row.name .. ", GROWS OFF " .. up.name .. "."
                    break
                end
            end
        end
    end
    G.show({ head = "THE SPORE BANK", body = body,
        buttons = { { id = "network", text = "SEE THE NETWORK" }, { id = "later", text = "LATER" } },
        act = function(id) if id == "network" then require("src.ui.network").open() end end })
    teach("bank")
end

-- Each frame of a run: the tutorial's steps, then whatever is new.
function G.update(g)
    if S.script then return end
    if g ~= G.game then
        G.game, G.card, G.queue, G.coach, G.lesson, G.pruning = g, nil, {}, nil, nil, nil
        G.step, G.shown = S.tutorial and 1 or nil, nil
    end
    if G.card then return end
    if G.lesson and G.lesson.where == "run" and G.lesson.done(g) then G.lesson = nil end
    local over = g.phase == "won" or g.phase == "lost"
    if S.tutorial and over then
        S.tutorial, G.step, G.coach = false, nil, nil
        Profile.teach("tutorial")
    end
    if S.tutorial and G.step then
        tutorial(g)
        if G.card then return end
    end
    local tips = Profile.tips or S.tutorial
    if over then
        if tips and not Profile.taught.bank and Profile.spores > 0 then bank(g) end
        return
    end
    if not tips then return end
    -- Not before the tutorial has got to the first wave: one thing at a time.
    local early = S.tutorial and not G.allows("start")
    for _, l in ipairs(LESSONS) do
        if not Profile.taught[l.id] and (l.always or not S.tutorial) and (not l.build or g.phase == "build")
            and not (early and not l.always) and l.when(g) then
            teach(l.id)
            l.show(g)
            return
        end
    end
    if early then return end
    if g.phase == "build" then
        local nxt = g:nextWave()
        if not nxt then return end
        if nxt.weather and not Profile.taught[nxt.weather] then weather(nxt.weather, true) end
        local shown = {}
        for _, kind in ipairs(D.ENEMY_ORDER) do
            for _, row in ipairs(nxt) do
                if row[1] == kind and not shown[kind] and not Profile.taught[kind] then shown[kind] = true; meet(kind) end
            end
        end
    elseif g.phase == "wave" then
        -- What comes out of what was sent: met as it shows.
        for _, e in ipairs(g.enemies) do
            local k = codex.whole[e.kind] or e.kind
            if not e.hidden and not Profile.taught[k] and D.ENEMIES[k] then meet(k) end
        end
        if g.weather and not Profile.taught[g.weather] then weather(g.weather, false) end
    end
end

--- the network's first visit ---------------------------------------------------------------

-- The first time the network is up: what spores are, and where to start --
-- the cheapest useful node picked and pointed at.
function G.network(net)
    if S.script or Profile.taught.network then return end
    Profile.teach("network")
    local first = G.openNodes(1)[1]
    local body = "SPORES (TOP LEFT) COME FROM EVERY RUN: " .. D.SPORES.wave .. " A WAVE CLEARED, MORE FOR A WIN. "
        .. "EACH NODE HERE GROWS FROM THE ONE ABOVE IT, A RANK AT A TIME, AND STAYS GROWN FOR EVERY RUN AFTER."
    if first then
        net.sel = first.row.id
        net.centre(first.row.id)
        body = body .. " A GOOD FIRST: " .. first.row.name .. ". " .. say("CLICK", "TAP") .. " IT AGAIN, OR ITS BUTTON, TO GROW IT."
        local id = first.row.id
        G.lesson = { where = "network", at = function()
            local L = net.layout()
            if L.panel and net.sel == id then
                local b = L.panel.button
                return b.x + floor(b.w / 2), b.y + floor(b.h / 2)
            end
        end, done = function() return net.sel ~= id or N.rank(Profile.ranks(), id) > 0 end }
    end
    G.show({ where = "network", head = "THE NETWORK", body = body, span = function()
        local L = net.layout()
        return L.area.x, L.area.x + L.area.w
    end })
end

-- Each frame the network is up: its pointer, until it is done with.
function G.networkUpdate()
    if G.lesson and G.lesson.where == "network" and G.lesson.done() then G.lesson = nil end
end

return G
