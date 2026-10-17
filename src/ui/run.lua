-- A run of a level: starting it (painting its board first, the first time),
-- and each frame of it -- the rules stepped at the game's speed, the sound
-- of what they cued, and what the profile keeps of it: records, spores, wins.

local World = require "src.world"
local Game = require "src.game"
local D = require "src.defs"
local Sfx = require "src.sfx"
local Profile = require "src.profile"
local S = require "src.ui.state"
local Toolbar = require "src.ui.toolbar"
local flair = require "src.ui.flair"
local audio = require "src.ui.audio"
local codex = require "src.ui.codex"

local max = math.max
local layTools = Toolbar.layTools

-- A new run of the level on its board, everything put down and the camera home.
local function start()
    S.game = Game.new(S.world, S.level, { challenge = S.challenge, loadout = S.chosen, seed = not S.script and Profile.sown[S.level.id] or nil,
        best = Profile.records[S.level.id], dice = S.script and 1 })
    layTools(S.game)
    S.mode, S.drag, S.panx, S.pany, S.selected = "grow", nil, 0, 0, nil
    S.focus, S.focused = nil, nil
    S.paused, S.speed = false, 1
    S.menu = nil
    flair.sky.change(S.game.weather or false)
    flair.sky.t = flair.sky.time
end

-- Plays level `n` with the species in `chosen`: its board if it is painted
-- already, else paint it first.
local function play(n)
    S.level = D.LEVELS[n]
    S.menu = nil
    if S.worlds[S.level.id] then
        S.world = S.worlds[S.level.id]
        start()
        return
    end
    S.world = World.new(S.level.map)
    S.worlds[S.level.id] = S.world
    S.progress = 0
    S.painter = coroutine.create(function() S.world:paint() end)
end

-- A frame of the run, dt on.
local function update(dt)
    if not S.paused then
        for _ = 1, S.speed do
            S.game:update(dt)
            if S.game.events.heart then S.heartFlash, flair.hurt = 0.15, 0.45 end
            if S.game.events.shake then S.shake = max(S.shake, S.game.events.shake) end
        end
        if not S.script then codex.watch(S.game) end
    end
    audio.hear()
    -- A lot coming in at once (a body drunk, a wave's bonus): the count glows.
    if S.game.nutrients - flair.lastNut >= 3 and (flair.nut.t <= 0 or flair.nut.k ~= "r") then flair.nut = { t = 0.35, k = "w" } end
    flair.lastNut = S.game.nutrients
    -- The sprout low: a heartbeat, heard and seen at the screen's edge.
    local low = S.game.phase == "wave" and S.game.heartHp > 0 and S.game.heartHp < S.game.heartMax * 0.3
    local b = low and not S.paused and (S.game.clock % 1.2) < 0.15
    if b and not flair.beat then Sfx.play("stomp", 0, 0.6, 0.6) end
    flair.beat = b
    S.heartFlash = max(0, S.heartFlash - dt)
    S.shake = max(0, S.shake - dt)
    if S.game.best > (Profile.records[S.level.id] or 0) and not S.script then
        Profile.records[S.level.id] = S.game.best
        Profile.save()
    end
    -- Spores go into the bank as they are earned, so a run left half way keeps them.
    if S.game.spores > (S.game.banked or 0) and not S.script then
        Profile.spores = Profile.spores + S.game.spores - (S.game.banked or 0)
        S.game.banked = S.game.spores
        Profile.save()
    end
    if S.game.phase == "won" and not S.game.recorded then
        S.game.recorded = true
        if not S.script then
            -- The first win puts the level's species up for sale, shown on the way on.
            if not Profile.won[S.level.id] and S.level.prize and not Profile.owns(S.level.prize) then S.game.offer = S.level.prize end
            -- And any seed waiting on it.
            for _, sd in ipairs(D.SEEDS) do
                if not Profile.won[S.level.id] and sd.after == S.level.id and not Profile.ownsSeed(sd.id) then S.game.newSeed = sd.id end
            end
            Profile.won[S.level.id] = true
            Profile.save()
        end
    end
    -- What was selected may have been eaten, sterilised, sold or flattened.
    if S.selected then
        local gone
        if S.selected.node then gone = S.selected.node.tower ~= S.selected
        else
            gone = true
            for _, m in ipairs(S.game.mats) do if m == S.selected then gone = false end end
        end
        if gone then S.selected = nil end
    end
end

return {
    start = start,
    play = play,
    update = update,
}
