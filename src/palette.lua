-- The whole palette: thirteen colours, and nothing is drawn outside this list.
--
-- Survive School's rule, kept: a pixel's colour is *chosen* off a short ramp of
-- these, never blended, and there is no alpha anywhere. What changed is the
-- list itself. That game is ink on an exercise book; this one is a patio seen
-- from ant height, so the colours are the design doc's -- warm browns and mossy
-- greens for the world, teal for the network, one bright green that only the
-- sprout is allowed to be, and rust for anything that wants it dead.
--
-- Each key also names the key one step darker (`darker`). That one column does
-- the work Survive School's overprint table did: a shadow is the ground under it
-- one step darker, a starved mushroom is its own picture one step darker, a
-- dormant one two.

local function hex(s)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end

local Palette = {}

-- key, colour, the key one step darker. The colours are the Apollo palette's
-- (the one the board's tileset is painted in, assets/tiles/isometric.png), one
-- per role, so a mushroom or a beetle sits in the same world as the tiles.
-- Three keep their own: the network's teal and glow (nothing in Apollo is that
-- colour, and the threads must never be mistaken for the pond), and cream,
-- which Apollo has only as a cold near-white.
Palette.list = {
    { "o", "241527", "o" }, -- ink: outlines, the darkest thing there is
    { "u", "4d2b32", "o" }, -- umber: deep soil, shadow
    { "n", "7a4841", "u" }, -- brown: soil
    { "t", "c09473", "n" }, -- tan: lit soil, the trail, mushroom flesh in shade
    { "w", "e8d6b0", "t" }, -- cream: glints, mushroom caps, salt
    { "s", "a8b5b2", "k" }, -- stone: the patio
    { "k", "577277", "u" }, -- ash: stone in shade
    { "d", "25562e", "u" }, -- dark moss
    { "m", "468232", "d" }, -- moss
    { "g", "a8ca58", "m" }, -- sprout: the most saturated thing on screen, always
    { "c", "23a69a", "d" }, -- teal: the network
    { "l", "a3f5e3", "c" }, -- glow: nutrients moving, the network lit
    { "r", "cf573c", "u" }, -- rust: enemies, damage, anything that went wrong
}

Palette.key, Palette.darker = {}, {}
for _, row in ipairs(Palette.list) do
    Palette.key[row[1]] = hex(row[2])
    Palette.darker[row[1]] = row[3]
end

return Palette
