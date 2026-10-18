-- The game's version, as the title and the crash report say it: the number,
-- bumped by hand for a release, and the commit it was built from, which the
-- build workflows stamp into build.txt (`git describe --tags --always`). Run
-- from the folder, there is no build.txt and only the number shows.

local V = { number = "0.2.0" }

local fs = love.filesystem
local build = fs and fs.getInfo and fs.getInfo("build.txt") and fs.read("build.txt")
V.build = build and build:match("%S+") or nil

-- As it is written on the screen, in the font's capitals.
V.text = "V" .. V.number .. (V.build and (" " .. V.build:upper()) or "")

return V
