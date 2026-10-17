-- The info panel: everything about one species, or one fruiting body as it
-- has grown, or a seed. Down the right side on a wide screen; across the top
-- of the board (or the bottom of the loadout) on a narrow one. Shown for
-- whatever is selected in a run, and for the card tapped in the loadout.

local D = require "src.defs"
local M = require "src.models"
local Font = require "src.font"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Pixels = require "src.ui.pixels"
local Toolbar = require "src.ui.toolbar"
local flair = require "src.ui.flair"

local floor, max, min = math.floor, math.max, math.min
local box, text, wrapLines, number, wide = Draw.box, Draw.text, Draw.wrapLines, Draw.number, Draw.wide
local blit, icon, CUT = Pixels.blit, Pixels.icon, Pixels.CUT
local turnRect, barTop = Toolbar.turnRect, Toolbar.barTop
local TOP = S.TOP

local function infoWidth() return wide() and min(150, floor(S.vw * 0.36)) or S.vw - S.inset.l - S.inset.r - 6 end

-- The panel of one still locked: no name, no numbers, only how to get it.
local function lockedLines(what, by, w)
    local out, height = {}, 0
    local function add(str, k, x, h)
        x = x or 0
        for _, l in ipairs(wrapLines(str, w - x)) do
            out[#out + 1] = { s = l, k = k, x = x, h = h or 7 }
            height = height + (h or 7)
        end
    end
    add("???", "k", 24, 8)
    add(what .. "   LOCKED", "k", 24)
    if height < 22 then out[#out + 1] = { h = 22 - height }; height = 22 end
    add("WIN " .. by .. " TO PUT IT UP FOR SALE.", "s")
    return out, height
end

-- The panel's lines, each { s, k (colour), x, h }: the name and role beside
-- the picture, the long account, the numbers (live, for one on the board),
-- and both upgrade branches with what is grown, open or shut.
local function infoLines(kind, t, w)
    local d = D.TOWER[kind]
    if not t and not Profile.known(kind) then return lockedLines("SPECIES", Profile.prizeOf(kind).name, w) end
    local out, height = {}, 0
    local function add(str, k, x, h)
        x = x or 0
        for _, l in ipairs(wrapLines(str, w - x)) do
            out[#out + 1] = { s = l, k = k, x = x, h = h or 7 }
            height = height + (h or 7)
        end
    end
    local function gap(h) out[#out + 1] = { h = h }; height = height + h end
    local function get(k) if t then return S.game:stat(t, k) end return d[k] end

    add(t and t.branch and d.up[t.branch][t.tier].name or d.name, "w", 24, 8)
    add(d.role .. "   " .. (t and ("SPENT " .. t.spent) or ("COST " .. d.cost)), "t", 24)
    if height < 22 then gap(22 - height) end

    -- On the board: what is wrong with it, if anything.
    if t then
        local why
        if t.hunger == "dormant" then why = "DORMANT: LINK IT TO THE SPROUT"
        elseif t.hunger == "starved" then why = "STARVED: HALF PACE"
        elseif t.thirsty then why = "THIRSTY: FEED IT FROM A RELAY"
        elseif (t.webbed or 0) > 0 then why = "WEBBED SHUT"
        elseif kind == "mat" and not t.fed then why = "WITHERING: DRAPE A LINK OVER IT" end
        if why then add(why, "r"); gap(2) end
    end

    -- A species read about first; one on the board puts its numbers and its
    -- upgrades first, so a short panel still has them.
    if not t then add(d.about, "w"); gap(3) end
    local parts = {}
    if get("damage") then parts[#parts + 1] = "DAMAGE " .. number(get("damage")) end
    if get("every") then parts[#parts + 1] = "EVERY " .. number(get("every")) .. "S" end
    local r = (t and t.node) and S.game:towerRange(t) or get("range")
    if r then parts[#parts + 1] = "RANGE " .. floor(r + 0.5) end
    if get("splash") then parts[#parts + 1] = "SPLASH " .. number(get("splash")) end
    if kind == "mat" then parts[#parts + 1] = "SLOW " .. floor((1 - (t and S.game:matSlow(t) or d.slow)) * 100 + 0.5) .. "%" end
    if kind == "relay" then
        parts[#parts + 1] = "FLOW X" .. number(get("capMul"))
        parts[#parts + 1] = "DAMAGE +" .. floor(((get("amp") or 1) - 1) * 100 + 0.5) .. "%"
    end
    if t and t.hp and kind ~= "mat" then parts[#parts + 1] = "HP " .. math.ceil(t.hp) .. "/" .. S.game:maxHp(t)
    elseif not t and d.hp then parts[#parts + 1] = "HP " .. d.hp end
    -- A number never parted from its name: lines broken between them.
    local line = ""
    for _, part in ipairs(parts) do
        local try = line == "" and part or line .. "  " .. part
        if Font.width(try) > w and line ~= "" then add(line, "l"); line = part else line = try end
    end
    if line ~= "" then add(line, "l") end

    -- On the board, what it can grow into next is a button: the upgrade itself.
    local open = {}
    if t then for _, u in ipairs(S.game:upgrades(t)) do open[u.branch * 10 + u.tier] = u end end
    gap(4)
    add("UPGRADES", "t")
    for b = 1, 2 do
        if b == 2 then add("OR", "s") end
        local shut = t and t.branch and t.branch ~= b
        for tier = 1, 2 do
            local row = d.up[b][tier]
            local u = open[b * 10 + tier]
            if u then
                local blurb = wrapLines(row.blurb, w - 8)
                local h = 11 + 7 * #blurb
                out[#out + 1] = { up = u, row = row, blurb = blurb, h = h + 3 }
                height = height + h + 3
            else
                local grown = t and t.branch == b and t.tier >= tier
                local k = grown and "g" or (shut and "k" or "w")
                add((tier == 1 and "I  " or "II ") .. row.name .. "  " .. (grown and "GROWN" or row.cost), k)
                -- On the board only what it can grow now says what it does.
                if not t then add(row.blurb, "s", 12) end
            end
        end
    end
    if t then gap(4); add(d.about, "s") end
    return out, height
end

-- A seed's panel in the loadout: what it changes, and the mutations it brings.
local function seedLines(id, w)
    local sd = D.SEED[id]
    if not Profile.seedKnown(id) then return lockedLines("SEED", D.LEVEL[sd.after].name, w) end
    local out, height = {}, 0
    local function add(str, k, x, h)
        x = x or 0
        for _, l in ipairs(wrapLines(str, w - x)) do
            out[#out + 1] = { s = l, k = k, x = x, h = h or 7 }
            height = height + (h or 7)
        end
    end
    local function gap(h) out[#out + 1] = { h = h }; height = height + h end
    add(sd.name, "w", 24, 8)
    add("SEED   " .. (sd.price and ("PRICE " .. sd.price) or "FREE"), "t", 24)
    if height < 22 then gap(22 - height) end
    add(sd.about, "w")
    gap(3)
    add(sd.blurb, "l")
    gap(4)
    add("ITS MUTATIONS", "t")
    for _, m in ipairs(D.MUTATIONS) do
        if m.seed == id then
            add(m.name, "w")
            add(m.blurb, "s", 8)
        end
    end
    return out, height
end

-- The panel open now, laid out: nil if there is none.
local function info()
    local kind, t, seed
    if S.menu == "loadout" then
        kind, seed = S.pick and S.pick.info, S.pick and S.pick.seedInfo
    elseif not S.menu and S.game and (S.game.phase == "build" or S.game.phase == "wave") then
        if S.selected then kind, t = S.selected.kind, S.selected
        elseif S.peek and S.peek == S.mode then kind = S.peek end
    end
    if not kind and not seed then return end
    local w = infoWidth()
    local lines, h
    if seed then lines, h = seedLines(seed, w - 8) else lines, h = infoLines(kind, t, w - 8) end
    local P = { kind = kind, seed = seed, t = t, lines = lines, w = w,
        locked = S.menu == "loadout" and not (seed and Profile.seedKnown(seed) or (not seed and Profile.known(kind))) }
    if S.menu == "loadout" then
        if wide() then
            P.x, P.y, P.h = S.vw - S.inset.r - w - 3, S.inset.t + 3, S.vh - S.inset.t - S.inset.b - 6
        else
            -- Room for the BRING / LEAVE button under the words.
            P.h = min(h + 28, floor(S.vh * 0.55))
            P.x, P.y = S.inset.l + 3, S.vh - S.inset.b - 3 - P.h
        end
        P.button = { x = P.x + 4, y = P.y + P.h - 18, w = w - 8, h = 14 }
    else
        local top = S.inset.t + TOP + 2
        if wide() then
            local _, ty = turnRect(1)
            P.x, P.y, P.h = S.vw - S.inset.r - w - 3, top, ty - 4 - top
        else
            P.x, P.y, P.h = S.inset.l + 3, top, min(h + 8, floor((barTop() - top) * 0.6))
        end
    end
    -- Where each line sits, so an upgrade's button can be hit; one cut off by
    -- the bottom of the panel cannot.
    local y = P.y + 4
    for _, l in ipairs(lines) do
        l.y = y
        y = y + l.h
        if l.up and y > P.y + P.h then l.up = nil end
    end
    return P
end

-- What the panel leaves free across the screen, as left and right edges.
local function freeSpan()
    local P = info()
    if P and wide() then return S.inset.l, P.x - 3 end
    return S.inset.l, S.vw - S.inset.r
end

-- The info panel, its lines kept inside it (a short screen cuts the end).
local function draw(P)
    box(P.x, P.y, P.w, P.h, "u", "c")
    love.graphics.setScissor(P.x, P.y, P.w, P.h)
    local clock = flair.now()
    local t = P.t
    local pic = P.seed and M.sprout(0, P.seed) or icon(P.kind, t and t.branch, t and t.tier or 0, (clock * 0.7) % 1)
    love.graphics.setScissor(P.x, P.y, 22, 24)
    -- The sprout is taller than the corner: its leaves and the top of its stem,
    -- the top few pixels cut off, fewer for a low one (the flytrap).
    blit(pic, P.x + 12, P.seed and P.y + pic.oj - min(7, max(0, pic.h - 24))
        or (P.kind == "mat" and P.y + 16 or P.y + 22), P.locked and CUT or nil)
    love.graphics.setScissor(P.x, P.y, P.w, P.h - (P.button and 20 or 0))
    for _, l in ipairs(P.lines) do
        local y = l.y
        if l.up then
            -- An upgrade it can grow now: a button, its key beside the cost.
            local can = S.game:canUpgrade(P.t, l.up.branch)
            local on = S.hover.up and S.hover.up.branch == l.up.branch
            local bx, bw = P.x + 3, P.w - 6
            box(bx, y, bw, l.h - 3, on and "n" or (can and "d" or "o"), can and "l" or "k")
            text((l.up.tier == 1 and "I  " or "II ") .. l.row.name, bx + 2, y + 2, "w")
            local cost = tostring(l.row.cost)
            if not S.touch then
                local ups = S.game:upgrades(P.t)
                cost = (#ups == 1 and "Z/C" or (l.up.branch == ups[1].branch and "Z" or "C")) .. " " .. cost
            end
            text(cost, bx + bw - Font.width(cost) - 2, y + 2, can and "l" or "r")
            for n, s in ipairs(l.blurb) do text(s, bx + 2, y + 2 + 2 + 7 * n, can and "s" or "k") end
        elseif l.s then
            text(l.s, P.x + 4 + l.x, y, l.k)
        end
    end
    love.graphics.setScissor()
end

return {
    infoWidth = infoWidth,
    info = info,
    freeSpan = freeSpan,
    draw = draw,
}
