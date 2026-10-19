-- The 3x5 face, lifted from Survive School's src/font.lua by way of the frog
-- prototype (caps, digits and a little punctuation). LÖVE's vector font would break the pixel grid inside a
-- canvas this small, so lettering is plotted a pixel at a time like everything
-- else. Text is UTF-8: the accented capitals Spanish wants (src/lang.lua)
-- carry their mark on a sixth row, one pixel above the letter.

local Font = {}

local GW, GH, ADVANCE = 3, 5, 4

local GLYPHS = {
    A = { ".#.", "#.#", "###", "#.#", "#.#" },
    B = { "##.", "#.#", "##.", "#.#", "##." },
    C = { ".##", "#..", "#..", "#..", ".##" },
    D = { "##.", "#.#", "#.#", "#.#", "##." },
    E = { "###", "#..", "##.", "#..", "###" },
    F = { "###", "#..", "##.", "#..", "#.." },
    G = { ".##", "#..", "#.#", "#.#", ".##" },
    H = { "#.#", "#.#", "###", "#.#", "#.#" },
    I = { "###", ".#.", ".#.", ".#.", "###" },
    J = { "..#", "..#", "..#", "#.#", ".#." },
    K = { "#.#", "##.", "#..", "##.", "#.#" },
    L = { "#..", "#..", "#..", "#..", "###" },
    M = { "#.#", "###", "###", "#.#", "#.#" },
    N = { "#.#", "##.", "###", ".##", "#.#" },
    O = { ".#.", "#.#", "#.#", "#.#", ".#." },
    P = { "##.", "#.#", "##.", "#..", "#.." },
    Q = { ".#.", "#.#", "#.#", "##.", ".##" },
    R = { "##.", "#.#", "##.", "#.#", "#.#" },
    S = { ".##", "#..", ".#.", "..#", "##." },
    T = { "###", ".#.", ".#.", ".#.", ".#." },
    U = { "#.#", "#.#", "#.#", "#.#", "###" },
    V = { "#.#", "#.#", "#.#", "#.#", ".#." },
    W = { "#.#", "#.#", "###", "###", "#.#" },
    X = { "#.#", "#.#", ".#.", "#.#", "#.#" },
    Y = { "#.#", "#.#", ".#.", ".#.", ".#." },
    Z = { "###", "..#", ".#.", "#..", "###" },
    ["0"] = { "###", "#.#", "#.#", "#.#", "###" },
    ["1"] = { ".#.", "##.", ".#.", ".#.", "###" },
    ["2"] = { "##.", "..#", ".#.", "#..", "###" },
    ["3"] = { "##.", "..#", ".#.", "..#", "##." },
    ["4"] = { "#.#", "#.#", "###", "..#", "..#" },
    ["5"] = { "###", "#..", "##.", "..#", "##." },
    ["6"] = { ".##", "#..", "###", "#.#", "###" },
    ["7"] = { "###", "..#", ".#.", ".#.", ".#." },
    ["8"] = { "###", "#.#", "###", "#.#", "###" },
    ["9"] = { "###", "#.#", "###", "..#", "##." },
    [":"] = { "...", ".#.", "...", ".#.", "..." },
    ["."] = { "...", "...", "...", "...", ".#." },
    ["-"] = { "...", "...", "###", "...", "..." },
    ["/"] = { "..#", "..#", ".#.", "#..", "#.." },
    ["!"] = { ".#.", ".#.", ".#.", "...", ".#." },
    ["?"] = { "##.", "..#", ".#.", "...", ".#." },
    ["+"] = { "...", ".#.", "###", ".#.", "..." },
    [" "] = { "...", "...", "...", "...", "..." },
    ["'"] = { ".#.", ".#.", "...", "...", "..." },
    [","] = { "...", "...", "...", ".#.", "#.." },
    [";"] = { "...", ".#.", "...", ".#.", "#.." },
    ["("] = { ".#.", "#..", "#..", "#..", ".#." },
    [")"] = { ".#.", "..#", "..#", "..#", ".#." },
    ["%"] = { "#.#", "..#", ".#.", "#..", "#.#" },
    ["="] = { "...", "###", "...", "###", "..." },
    ["<"] = { "..#", ".#.", "#..", ".#.", "..#" },
    [">"] = { "#..", ".#.", "..#", ".#.", "#.." },
    ["¡"] = { ".#.", "...", ".#.", ".#.", ".#." },
    ["¿"] = { ".#.", "...", ".#.", "#..", ".##" },
}

-- An accented capital: the letter, under a row for its mark.
local MARK = { ACUTE = "..#", DIAERESIS = "#.#", TILDE = "###" }
for ch, m in pairs({ ["Á"] = { "A", "ACUTE" }, ["É"] = { "E", "ACUTE" }, ["Í"] = { "I", "ACUTE" },
    ["Ó"] = { "O", "ACUTE" }, ["Ú"] = { "U", "ACUTE" }, ["Ü"] = { "U", "DIAERESIS" }, ["Ñ"] = { "N", "TILDE" } }) do
    local g = { MARK[m[2]] }
    for _, row in ipairs(GLYPHS[m[1]]) do g[#g + 1] = row end
    GLYPHS[ch] = g
end
-- Their small letters, written as the capitals (every line is upper case).
local UPPER = { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ü"] = "Ü", ["ñ"] = "Ñ" }

-- A character at a time, the bytes of one UTF-8 character together.
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

function Font.has(ch) return GLYPHS[UPPER[ch] or ch:upper()] ~= nil end
Font.CHAR = CHAR

-- How many characters, not bytes.
function Font.length(text)
    local n = 0
    for _ in text:gmatch(CHAR) do n = n + 1 end
    return n
end

-- The first `n` characters.
function Font.cut(text, n)
    local out, k = {}, 0
    for ch in text:gmatch(CHAR) do
        k = k + 1
        if k > n then break end
        out[k] = ch
    end
    return table.concat(out)
end

function Font.width(text)
    return Font.length(text) * ADVANCE - 1
end

-- Plotted with the colour already set by the caller.
function Font.print(text, x, y)
    local n = 0
    for ch in text:gmatch(CHAR) do
        local g = GLYPHS[UPPER[ch] or ch:upper()]
        if g then
            local top = #g - GH -- a mark's row above the letter
            for r = 1, #g do
                local row = g[r]
                for c = 1, GW do
                    if row:sub(c, c) == "#" then
                        love.graphics.rectangle("fill", x + n * ADVANCE + c - 1, y + r - 1 - top, 1, 1)
                    end
                end
            end
        end
        n = n + 1
    end
end

return Font
