-- A run of a level: starting it (painting its board first, the first time),
-- and each frame of it -- the rules stepped at the game's speed, the sound
-- of what they cued, and what the profile keeps of it: records, spores, wins.
-- A run is played on the network the Spore Bank has grown (Profile.grown).
-- The run going on is kept as it goes (src/resume.lua): at each build phase,
-- and when the game goes to the background; and picked up again from there.

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
local Resume = require "src.resume"
local Guide = require "src.ui.guide"
local O = require "src.options"

local max = math.max
-- Seconds of build phase before the next wave starts by itself.
local AUTO_WAIT = 12
local layTools = Toolbar.layTools

-- The run going on kept, if it is one to keep: not the shots', not one
-- over. With what it is, to start it again from (the level, the challenge, the
-- species brought), off the run itself: the screens may be on to the next.
local lastPhase
local function keep()
    local g = S.game
    if S.script or not g or g.phase == "won" or g.phase == "lost" then return end
    local brought = false
    if g.loadout then
        local list = {}
        for _, t in ipairs(D.TOWERS) do if g.loadout[t.id] then list[#list + 1] = t.id end end
        brought = table.concat(list, " ")
    end
    Resume.save(g, { level = g.level.id, challenge = g.challenge or false, loadout = brought })
end

-- A new run of the level on its board, everything put down and the camera home;
-- or the run kept, picked up again (`resume`, the text of it).
local resuming
local function start()
    local back = resuming and Resume.decode(resuming, S.world)
    resuming = nil
    -- The shots play the whole network; a player, what theirs has grown.
    -- The tutorial plants the bean, whatever was planted here before.
    S.game = back or Game.new(S.world, S.level, { challenge = S.challenge, loadout = S.chosen, seed = not S.script and not S.tutorial and Profile.sown[S.level.id] or nil,
        best = Profile.records[S.level.id], dice = S.script and 1, net = not S.script and Profile.grown() or nil,
        firstWin = not S.script and not Profile.won[S.level.id] })
    lastPhase = S.game.phase
    S.endingAt = nil
    keep()
    layTools(S.game)
    S.mode, S.drag, S.panx, S.pany, S.selected = "grow", nil, 0, 0, nil
    S.focus, S.focused = nil, nil
    -- Picked up in the middle of a wave: paused, to see where things are first.
    S.paused, S.speed = back and back.phase == "wave" or false, 1
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

-- Is there a run to go on with: one left to go back to, or one kept?
local function canContinue()
    if S.game and not S.script and S.game.phase ~= "won" and S.game.phase ~= "lost" then return true end
    return Resume.kept()
end

-- Back to the run left, or the one kept picked up again on its board.
local function continue()
    if S.game and S.game.phase ~= "won" and S.game.phase ~= "lost" then
        S.menu = nil
        return true
    end
    local text, head = Resume.load()
    if not text then return false end
    local n
    for k, l in ipairs(D.LEVELS) do if l.id == head.level then n = k end end
    if not n then Resume.clear() return false end
    S.challenge = head.challenge or false
    S.chosen = nil
    if head.loadout then
        S.chosen = {}
        for id in head.loadout:gmatch("%S+") do S.chosen[#S.chosen + 1] = id end
    end
    resuming = text
    play(n)
    return true
end

-- A frame of the run, dt on.
local function update(dt)
    -- The guide first: a card up holds the run.
    Guide.update(S.game)
    if not S.paused and not Guide.holding() then
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
    -- Kept as each build phase starts; let go once the run is over. A wave
    -- starts at the speed the settings say.
    local phase = S.game.phase
    if phase ~= lastPhase then
        S.autoWait = 0
        if phase == "wave" and not S.script then S.speed = O.get("speed") end
        if phase == "build" then keep()
        elseif (phase == "won" or phase == "lost") and not S.script then Resume.clear() end
        lastPhase = phase
    end
    -- The next wave by itself, if the settings say so: after the first, once
    -- the build phase has had its time, unless the run is held.
    if O.get("auto") and not S.script and not S.tutorial and phase == "build" and S.game.wave > 0
        and S.game:nextWave() and not S.paused and not Guide.holding() then
        S.autoWait = (S.autoWait or 0) + dt
        if S.autoWait >= AUTO_WAIT then S.game:startWave() end
    end
    if S.endingAt and flair.now() >= S.endingAt then
        S.endingAt = nil
        require("src.ui.ending").open()
        return
    end
    if S.game.phase == "won" and not S.game.recorded then
        S.game.recorded = true
        if not S.script then
            -- The first win opens what on the network waited on it, named on the way out.
            if not Profile.won[S.level.id] then
                S.game.opened = Profile.opens(S.level.id)
                -- The last level, won the first time: the ending, once the
                -- win has had a moment (src/ui/ending.lua).
                if S.level == D.LEVELS[#D.LEVELS] and not S.game.challenge then S.endingAt = flair.now() + 2.5 end
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
    keep = keep,
    canContinue = canContinue,
    AUTO_WAIT = AUTO_WAIT,
    continue = continue,
}
