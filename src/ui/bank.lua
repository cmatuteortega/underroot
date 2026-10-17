-- The Spore Bank's screen after a first win (what it has and sells is
-- src/profile.lua), and where a won level's buttons go on to: through the
-- bank first when the win put something up for sale.

local D = require "src.defs"
local Font = require "src.font"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Pixels = require "src.ui.pixels"
local flair = require "src.ui.flair"
local Run = require "src.ui.run"
local Loadout = require "src.ui.loadout"

local floor, min = math.floor, math.min
local color, box, text, centred, wrap, say, inside = Draw.color, Draw.box, Draw.text, Draw.centred, Draw.wrap, Draw.say, Draw.inside
local blit, icon = Pixels.blit, Pixels.icon
local sound, deny = flair.sound, flair.deny

-- `offer`: the species a first win put up for sale, shown on the way on:
-- { kind, after = button, bought }.
local bank = {}

-- The Spore Bank after a first win: the species it put up for sale, BUY and
-- ON (LATER until it is bought) under it, all down the middle.
function bank.layout()
    local mid = floor(S.vw / 2)
    local w = min(200, S.vw - S.inset.l - S.inset.r - 8)
    local top = floor(S.vh / 2) - 60
    local card = { x = floor(mid - w / 2), y = top + 24, w = w, h = 48 }
    local by = card.y + card.h + 20
    local L = { mid = mid, top = top, card = card }
    if bank.offer.bought then
        L.on = { x = mid - 32, y = by, w = 64, h = 16 }
    else
        L.buy = { x = mid - 68, y = by, w = 64, h = 16 }
        L.on = { x = mid + 4, y = by, w = 64, h = 16 }
    end
    return L
end

-- Won: one of the buttons, or its key.
function bank.afterWin(id)
    -- A first win put a species up for sale: the Spore Bank shows it first.
    if S.game.offer then
        bank.offer = { kind = S.game.offer, after = id }
        S.game.offer = nil
        S.menu = "bank"
        S.mode, S.drag, S.selected = "grow", nil, nil
        sound("offer")
        return
    end
    if id == "endless" then sound("go"); S.game:goEndless()
    elseif id == "again" then sound("go"); Run.start()
    elseif id == "levels" then sound("back"); S.openMenu()
    elseif id == "next" then
        for k, l in ipairs(D.LEVELS) do
            if l == S.level and D.LEVELS[k + 1] then sound("select"); Loadout.open(k + 1) return end
        end
    end
end

-- Out of the Spore Bank, on to what the won level's button was for.
function bank.leave()
    local id = bank.offer.after
    bank.offer, S.menu = nil, nil
    bank.afterWin(id)
end

function bank.buyOffer()
    if bank.offer.bought then return end
    if Profile.buy(bank.offer.kind) then bank.offer.bought = true; sound("unlock") else deny() end
end

-- The Spore Bank after a first win: the species it put up for sale, and BUY.
function bank.draw()
    color("o")
    love.graphics.rectangle("fill", 0, 0, S.vw, S.vh)
    local L = bank.layout()
    local t = D.TOWER[bank.offer.kind]
    centred("THE SPORE BANK", L.top, "g", "o", L.mid)
    centred(S.level.name .. " WON: A NEW SPECIES FOR SALE", L.top + 11, "t", "o", L.mid)
    local c = L.card
    box(c.x, c.y, c.w, c.h, "u", bank.offer.bought and "g" or "t")
    local pic = icon(t.id, nil, 0, (flair.now() * 0.7) % 1)
    love.graphics.setScissor(c.x, c.y, 24, c.h)
    blit(pic, c.x + 12, t.id == "mat" and c.y + c.h - 8 or c.y + c.h - 6)
    love.graphics.setScissor()
    text(t.name, c.x + 26, c.y + 4, "w")
    text(t.role, c.x + 26, c.y + 12, "t")
    love.graphics.setScissor(c.x, c.y, c.w, c.h - 2)
    wrap(t.about, c.x + 26, c.y + 21, c.w - 30, "s")
    love.graphics.setScissor()
    local y = c.y + c.h + 6
    if bank.offer.bought then
        centred(t.name .. " IS YOURS. BRING IT FROM THE LOADOUT", y, "g", "o", L.mid)
    else
        local can = Profile.spores >= t.price
        centred("PRICE " .. t.price .. " SPORES   YOU HAVE " .. Profile.spores, y, can and "w" or "r", "o", L.mid)
        local b = L.buy
        box(b.x, b.y, b.w, b.h, S.hover.buy and "n" or (can and "d" or "u"), can and "t" or "k")
        local s = say("B: BUY IT", "BUY IT")
        text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 5, can and "t" or "k")
        centred(can and "OR BUY IT LATER, BEFORE ANY LEVEL" or "NOT ENOUGH YET: IT WAITS IN THE LOADOUT",
            b.y + b.h + 6, "s", "o", L.mid)
    end
    local b = L.on
    box(b.x, b.y, b.w, b.h, S.hover.on and "n" or "u", "c")
    local s = bank.offer.bought and say("ENTER: ON", "ON") or say("ENTER: LATER", "LATER")
    text(s, b.x + floor((b.w - Font.width(s)) / 2), b.y + 5, "w")
end

function bank.hover(mx, my)
    local L = bank.layout()
    if L.buy and inside(mx, my, L.buy.x, L.buy.y, L.buy.w, L.buy.h) then S.hover.buy = true end
    if inside(mx, my, L.on.x, L.on.y, L.on.w, L.on.h) then S.hover.on = true end
end

function bank.under()
    local L = bank.layout()
    local b = S.hover.buy and L.buy or (S.hover.on and L.on)
    if b then return function() return b.x, b.y, b.w, b.h end end
end

function bank.click(b)
    if S.hover.buy then bank.buyOffer()
    elseif S.hover.on or b == 2 then sound("click"); bank.leave() end
end

function bank.key(key)
    if key == "b" then bank.buyOffer()
    elseif key == "return" or key == "kpenter" or key == "space" or key == "escape" then sound("click"); bank.leave() end
end

return bank
