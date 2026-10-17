-- The toolbar along the bottom of a run, the wave button at its end and the
-- buttons that take the camera round over it: what is on it and where.

local D = require "src.defs"
local S = require "src.ui.state"

local floor, ceil, min = math.floor, math.ceil, math.min

-- The toolbar: regrow-all, the species the run brought (in their usual order,
-- each on its usual key), prune and the pulse. Laid out again for each run.
local BUTTONS = {}
local function layTools(g)
    for k = #BUTTONS, 1, -1 do BUTTONS[k] = nil end
    -- Not a tool: a press regrows every cut link at once (links are grown by
    -- dragging, with nothing in hand).
    BUTTONS[1] = { mode = "regrow", key = "1", name = "REGROW ALL", action = true }
    for _, t in ipairs(D.TOWERS) do
        if not g or g:brought(t.id) then
            BUTTONS[#BUTTONS + 1] = { mode = t.id, key = t.key, name = t.name, blurb = t.blurb, cost = t.cost, tower = true }
        end
    end
    BUTTONS[#BUTTONS + 1] = { mode = "prune", key = "X", name = "PRUNE", blurb = "CUT YOUR OWN LINK (HALF BACK) OR CLEAR A TOWER" }
    BUTTONS[#BUTTONS + 1] = { mode = "pulse", key = "Q", name = "SPORE PULSE",
        blurb = "PICK A FED NODE: EVERY TOWER ON THE WAY THERE OVERCHARGES" }
end
layTools()

-- The toolbar sits along the bottom with the wave button at
-- its end. A screen too narrow for both (a phone held upright) narrows the
-- buttons first and then lifts the wave button onto a row of its own, at the
-- right, where a thumb is.
-- Too narrow even for that, the tools go onto two rows.
local BH, WW = 27, 44
local function bar()
    local avail = S.vw - S.inset.l - S.inset.r - 4
    local n = #BUTTONS
    local y = S.vh - S.inset.b - BH - 3
    local bw = min(30, floor((avail - 8 - WW + 2) / n) - 2)
    if bw >= 22 then
        local tools = n * (bw + 2) - 2
        local x0 = S.inset.l + 2 + floor((avail - tools - 8 - WW) / 2)
        return { rows = { { x0 = x0, y = y, from = 1, to = n } }, bw = bw, wx = x0 + tools + 8, wy = y, top = y }
    end
    bw = min(30, floor((avail + 2) / n) - 2)
    if bw >= 22 then
        local tools = n * (bw + 2) - 2
        local x0 = S.inset.l + 2 + floor((avail - tools) / 2)
        return { rows = { { x0 = x0, y = y, from = 1, to = n } }, bw = bw, wx = S.vw - S.inset.r - 2 - WW, wy = y - BH - 4, top = y - BH - 4 }
    end
    local per = ceil(n / 2)
    bw = min(30, floor((avail + 2) / per) - 2)
    local x0 = S.inset.l + 2 + floor((avail - (per * (bw + 2) - 2)) / 2)
    local y1 = y - BH - 3
    return { rows = { { x0 = x0, y = y1, from = 1, to = per }, { x0 = x0, y = y, from = per + 1, to = n } },
        bw = bw, wx = S.vw - S.inset.r - 2 - WW, wy = y1 - BH - 4, top = y1 - BH - 4 }
end
local function buttonRect(n)
    local b = bar()
    for _, r in ipairs(b.rows) do
        if n >= r.from and n <= r.to then return r.x0 + (n - r.from) * (b.bw + 2), r.y, b.bw, BH end
    end
end
local function waveRect()
    local b = bar()
    return b.wx, b.wy, WW, BH
end
-- The top of everything the toolbar puts down: the tip line sits above it.
local function barTop() return bar().top end
-- The buttons that take the camera round the board, over the toolbar:
-- clockwise (d = 1) in the bottom right corner, back (d = -1) in the left.
local RW, RH = 22, 18
local function turnRect(d)
    local x = d == -1 and S.inset.l + 2 or S.vw - S.inset.r - 2 - RW
    return x, barTop() - RH - 5, RW, RH
end

return {
    BUTTONS = BUTTONS,
    layTools = layTools,
    buttonRect = buttonRect,
    waveRect = waveRect,
    barTop = barTop,
    turnRect = turnRect,
}
