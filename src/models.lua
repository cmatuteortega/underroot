-- Everything that is painted on its own rather than into the board: the sprout,
-- the fruiting bodies, the enemies and what is left of them.
--
-- Survive School's lesson, straight across: a pose is *numbers*, not a held
-- picture. Each model here is a function from a few numbers (a heading, a leg
-- phase, how far a puffball is squashed) to a list of ellipsoids, and its
-- picture is asked for those numbers rounded to a few steps and kept under that
-- key. Two hundred ants walking the trail cost what one costs: they are all
-- looking the same handful of pictures up.
--
-- What does not need a picture of its own does not get one. A starved mushroom
-- is its own picture laid down one step darker, a dormant one two, and a thing
-- that has just been hit is laid down in cream -- remaps at stamp time (see
-- T.DARKER, T.FLASH), not paintings.
--
-- And what was learned on the whistle holds: don't model a face. An ant's eyes,
-- a puffball's warts, a pillbug's plates are printed on the ball at the hit
-- point, not built.
--
-- Fruiting bodies are one function per species from a *look* -- branch, tier,
-- and three small animation numbers: `idle` (0..3, a slow breath or sway),
-- `fire` (0..2, the kick of a shot) and `grow` (0..3, coming up out of the
-- ground when it is grown or upgraded). Each tier adds parts you can see:
-- a toxic puffball goes green and grows satellites, an enoki clump gets taller
-- and sharper, a shelf grows thorns.
--
-- The bosses are the big bugs, built the same way at three times the size, so
-- the method's creases and ink pick out their plates and joints. Their legs are
-- jointed: `seg` lays an ellipsoid between two points, so a leg is a hip, a
-- knee and a foot, and a walk cycle is where the feet are.
--
-- The models are in src/models/: the kit they are built with, the sprout,
-- the fruiting bodies and the enemies. This is all of them as one table.

local M = {}
for _, part in ipairs({ "kit", "sprout", "towers", "enemies" }) do
    for k, v in pairs(require("src.models." .. part)) do M[k] = v end
end

return M
