-- Dev only: `love . --sheet` paints every look of every model onto one sheet,
-- writes it to the save directory as sheet.png (four times up) and quits. The
-- "paint it at every heading and look at it before the game does" step from
-- Survive School's 3dmethod.md.

local T = require "src.tracer"
local M = require "src.models"
local Font = require "src.font"

local S = {}

function S.run()
    local rows = M.sheetRows()
    local function headings(name, fn, n)
        local row = { name }
        for k = 0, n - 1 do row[#row + 1] = fn(k / n * 2 * math.pi) end
        rows[#rows + 1] = row
    end
    headings("ant", function(h) return M.ant(h, 0) end, 6)
    headings("gnat", function(h) return M.gnat(h, 0) end, 6)
    headings("slug", function(h) return M.slug(h, 0) end, 6)
    headings("spider", function(h) return M.spider(h, 0) end, 6)
    headings("knight", function(h) return M.knight(h, 0) end, 6)
    headings("queen", function(h) return M.queen(h, 0) end, 5)
    headings("stag", function(h) return M.stag(h, 0) end, 4)
    rows[#rows + 1] = { "stag", M.stag(0.6, 1, true), M.stag(2.4, 0, true), M.corpse("stag", 0.4), M.corpse("queen", 1) }
    headings("dung", function(h) return M.dung(h, 0) end, 4)
    rows[#rows + 1] = { "ball", M.ball(0, 0), M.ball(0, 1), M.ball(0, 2, true), M.corpse("ball", 0), M.corpse("dung", 1) }
    headings("moth", function(h) return M.moth(h, 0) end, 6)
    rows[#rows + 1] = { "moth", M.moth(0.4, 1), M.corpse("moth", 0) }
    headings("w.bug", function(h) return M.waterbug(h, 0) end, 4)
    rows[#rows + 1] = { "w.bug", M.waterbug(0.6, 1, true), M.waterbug(2.4, 0, true), M.corpse("waterbug", 0.4) }
    headings("centi", function(h) return M.centipede(h, 0) end, 6)
    headings("seg", function(h) return M.centseg(h, 0) end, 6)
    rows[#rows + 1] = { "centi", M.centipede(0.5, 1), M.centseg(0.5, 1), M.corpse("centipede", 0), M.corpse("centseg", 1) }
    headings("spring", function(h) return M.springtail(h, 0) end, 6)
    rows[#rows + 1] = { "spring", M.springtail(0.5, 1), M.springtail(0.5, 0, true), M.springtail(3.6, 0, true), M.corpse("springtail", 0) }
    headings("click", function(h) return M.click(h, 0) end, 4)
    rows[#rows + 1] = { "click", M.click(0.6, 1, "belly"), M.click(0.6, 0, "leap", 1), M.click(0.6, 0, "leap", 3), M.corpse("click", 0.4) }
    headings("bomb", function(h) return M.bombardier(h, 0) end, 4)
    rows[#rows + 1] = { "bomb", M.bombardier(0.6, 1, true), M.bombardier(3.8, 0, true), M.corpse("bombardier", 0.4) }
    headings("mole", function(h) return M.mole(h, 0) end, 4)
    rows[#rows + 1] = { "mole", M.mole(0.6, 0, true), M.mole(0.6, 1, true), M.corpse("mole", 0.4) }
    rows[#rows + 1] = { "dead", M.corpse("ant", 0, true), M.corpse("spider", 1), M.corpse("knight", 2), M.corpse("slug", 0.5),
        M.corpse("gnat", 0), M.corpse("pillbug", 0, true) }

    local pad, label = 6, 40
    local W, H = label, 0
    local heights = {}
    for r, row in ipairs(rows) do
        local w, h = label, 0
        for k = 2, #row do w, h = w + row[k].w + pad, math.max(h, row[k].h) end
        W, heights[r] = math.max(W, w), h + pad
        H = H + h + pad
    end
    local canvas = love.graphics.newCanvas(W, H)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(T.RGB[T.IDX.n])
    local y = 0
    for r, row in ipairs(rows) do
        love.graphics.setColor(T.RGB[T.IDX.w])
        Font.print(row[1], 2, y + 2)
        local x = label
        for k = 2, #row do
            local p = row[k]
            for pj = 0, p.h - 1 do
                for pi = 0, p.w - 1 do
                    local key = p.key[pj * p.w + pi]
                    if key ~= 0 then
                        love.graphics.setColor(T.RGB[key])
                        love.graphics.rectangle("fill", x + pi, y + pj, 1, 1)
                    end
                end
            end
            x = x + p.w + pad
        end
        y = y + heights[r]
    end
    love.graphics.setCanvas()
    local data = canvas:newImageData()
    local big = love.image.newImageData(W * 4, H * 4)
    big:mapPixel(function(x, yy) return data:getPixel(math.floor(x / 4), math.floor(yy / 4)) end)
    big:encode("png", "sheet.png")
    print("sheet", W, H, "pictures", M.count())
    love.event.quit()
end

return S
