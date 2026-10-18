-- When something breaks: instead of LÖVE's blue screen, the error and where
-- it happened written to crash.txt in the save directory, and a screen in the
-- game's own colours saying so, with a way to send it on (the whole report
-- copied, to paste into a mail or a message) and a way out.
--
-- It is love.errorhandler (main.lua): it runs with the game stopped, and
-- whatever it touches may be what broke, so it leans on as little as it can
-- -- the 3x5 face (src/font.lua, plotted with rectangles) and nothing else
-- of the game's, every step that could fail tried in a pcall.

local Font = require "src.font"

local crash = {}

crash.FILE = "crash.txt"

-- Palette.list's ink, umber, cream, tan, teal and rust (src/palette.lua),
-- spelled out so a broken palette still has a screen.
local INK = { 0x24 / 255, 0x15 / 255, 0x27 / 255 }
local UMBER = { 0x4d / 255, 0x2b / 255, 0x32 / 255 }
local CREAM = { 0xe8 / 255, 0xd6 / 255, 0xb0 / 255 }
local TAN = { 0xc0 / 255, 0x94 / 255, 0x73 / 255 }
local TEAL = { 0x23 / 255, 0xa6 / 255, 0x9a / 255 }
local RUST = { 0xcf / 255, 0x57 / 255, 0x3c / 255 }

-- What is worth knowing to put it right: the error, where, and on what.
function crash.report(msg, trace)
    local lines = { "Mycelio TD crash report", os.date("!%Y-%m-%d %H:%M:%S UTC") }
    local ok, major, minor, rev = pcall(love.getVersion)
    if ok then lines[#lines + 1] = ("LOVE %s.%s.%s"):format(major, minor, rev) end
    if love.system then
        local okOS, os_ = pcall(love.system.getOS)
        if okOS then lines[#lines + 1] = "OS " .. tostring(os_) end
    end
    if love.graphics and love.graphics.getRendererInfo then
        local okR, name, version, vendor, device = pcall(love.graphics.getRendererInfo)
        if okR then lines[#lines + 1] = ("Renderer %s %s (%s %s)"):format(name, version, vendor, device) end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Error: " .. msg
    lines[#lines + 1] = ""
    lines[#lines + 1] = (trace:gsub("\n[^\n]+%(tail call%): %?", ""))
    return table.concat(lines, "\n") .. "\n"
end

-- The screen's two buttons, in its own pixels: a box each, side by side.
local function buttons(vw, vh)
    local w, h, gap = 64, 13, 6
    local x = math.floor((vw - (2 * w + gap)) / 2)
    local y = vh - h - 10
    return {
        { id = "copy", name = "COPY REPORT", x = x, y = y, w = w, h = h },
        { id = "quit", name = "QUIT", x = x + w + gap, y = y, w = w, h = h },
    }
end

local function centred(s, y, vw)
    Font.print(s, math.floor((vw - Font.width(s)) / 2), y)
end

function crash.handler(msg)
    msg = tostring(msg)
    local report = crash.report(msg, (debug.traceback("", 2):gsub("^\n", "")))
    print(report)
    if love.filesystem then pcall(love.filesystem.write, crash.FILE, report) end
    if not (love.window and love.graphics and love.event) then return end
    if not love.graphics.isCreated() or not love.window.isOpen() then
        if not pcall(love.window.setMode, 800, 600) then return end
    end
    -- Everything the game had going, let go.
    if love.mouse then
        pcall(love.mouse.setVisible, true)
        pcall(love.mouse.setGrabbed, false)
        pcall(love.mouse.setRelativeMode, false)
        if love.mouse.isCursorSupported and love.mouse.isCursorSupported() then pcall(love.mouse.setCursor) end
    end
    if love.joystick then
        for _, j in ipairs(love.joystick.getJoysticks()) do pcall(j.setVibration, j) end
    end
    if love.audio then pcall(love.audio.stop) end
    love.graphics.reset()
    love.graphics.setCanvas()
    love.graphics.origin()

    local saved = love.filesystem and love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory() or ""
    local copied = 0 -- seconds left of "COPIED"
    -- The first line of the error, as much of it as fits, for the screen.
    local short = msg:match("^[^\n]*"):gsub("^[^:]*:%d+: ", ""):upper()

    local function layout()
        local w, h = love.graphics.getDimensions()
        local zoom = math.max(1, math.floor(math.min(w / 240, h / 135)))
        return zoom, math.floor(w / zoom), math.floor(h / zoom)
    end

    local function pressed(x, y)
        local zoom, vw, vh = layout()
        x, y = x / zoom, y / zoom
        for _, b in ipairs(buttons(vw, vh)) do
            if x >= b.x and y >= b.y and x < b.x + b.w and y < b.y + b.h then return b.id end
        end
    end

    local function act(id)
        if id == "copy" and love.system then
            pcall(love.system.setClipboardText, report)
            copied = 2
        elseif id == "quit" then
            return 1
        end
    end

    local function draw()
        local zoom, vw, vh = layout()
        love.graphics.clear(INK)
        love.graphics.push()
        love.graphics.scale(zoom, zoom)
        love.graphics.setColor(RUST)
        centred("SOMETHING BROKE", 14, vw)
        love.graphics.rectangle("fill", math.floor(vw / 2 - 30), 22, 60, 1)
        love.graphics.setColor(CREAM)
        centred("THE GAME HAS STOPPED. WHAT WAS SAVED IS SAFE,", 32, vw)
        centred("THE RUN IT WAS IN THE MIDDLE OF IS NOT.", 40, vw)
        love.graphics.setColor(TAN)
        local max = math.floor((vw - 12) / 4)
        local y = 54
        for k = 1, #short, max do
            if y > vh - 44 then break end
            centred(short:sub(k, k + max - 1), y, vw)
            y = y + 8
        end
        love.graphics.setColor(CREAM)
        centred("A REPORT IS SAVED AS CRASH.TXT:", vh - 38, vw)
        centred("COPY IT TO SEND IT ON", vh - 30, vw)
        for _, b in ipairs(buttons(vw, vh)) do
            love.graphics.setColor(UMBER)
            love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
            love.graphics.setColor(TEAL)
            love.graphics.rectangle("line", b.x + 0.5, b.y + 0.5, b.w - 1, b.h - 1)
            love.graphics.setColor(CREAM)
            local name = (b.id == "copy" and copied > 0) and "COPIED" or b.name
            Font.print(name, b.x + math.floor((b.w - Font.width(name)) / 2), b.y + 4)
        end
        love.graphics.pop()
        -- Where the report is, in the window's own letters (a path is not
        -- all capitals and digits).
        love.graphics.setColor(TAN)
        love.graphics.printf(saved, 4, 4, love.graphics.getWidth() - 8, "left")
        love.graphics.present()
    end

    return function()
        love.event.pump()
        -- A tap comes as a click too (LÖVE makes one of each touch).
        for e, a, b in love.event.poll() do
            if e == "quit" then return 1 end
            if e == "keypressed" then
                if a == "escape" then return 1 end
                if a == "c" or a == "return" then act("copy") end
            elseif e == "mousereleased" then
                local r = act(pressed(a, b))
                if r then return r end
            end
        end
        if copied > 0 then copied = copied - 0.1 end
        if love.graphics.isActive() then pcall(draw) end
        if love.timer then love.timer.sleep(0.1) end
    end
end

return crash
