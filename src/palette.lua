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

-- key, colour, the key one step darker
Palette.list = {
    { "o", "1c1216", "o" }, -- ink: outlines, the darkest thing there is
    { "u", "47301f", "o" }, -- umber: deep soil, shadow
    { "n", "7b5536", "u" }, -- brown: soil
    { "t", "b98f5e", "n" }, -- tan: lit soil, the trail, mushroom flesh in shade
    { "w", "eee3c4", "t" }, -- cream: glints, mushroom caps, salt
    { "s", "9a958a", "k" }, -- stone: the patio
    { "k", "625d58", "u" }, -- ash: stone in shade
    { "d", "3b5530", "u" }, -- dark moss
    { "m", "6c8c3e", "d" }, -- moss
    { "g", "a8ec3a", "m" }, -- sprout: the most saturated thing on screen, always
    { "c", "23a69a", "d" }, -- teal: the network
    { "l", "a3f5e3", "c" }, -- glow: nutrients moving, the network lit
    { "r", "c8452c", "u" }, -- rust: enemies, damage, anything that went wrong
}

Palette.key, Palette.darker = {}, {}
for _, row in ipairs(Palette.list) do
    Palette.key[row[1]] = hex(row[2])
    Palette.darker[row[1]] = row[3]
end

return Palette
