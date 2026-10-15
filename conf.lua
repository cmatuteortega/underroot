function love.conf(t)
    t.identity = "underfoot" -- from when it was called that; saves stay put
    -- The running engine, on purpose: the field only decides whether LÖVE
    -- opens its "Compatibility Warning" box on a mismatch, and this ships on
    -- two engines -- 11.x on desktop, 12.0 in the Android build.
    t.version = love._version
    t.window.title = "Groute"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    -- Opens fullscreen everywhere: on a phone that is the only way to have the
    -- whole screen, and on a computer F11 / alt+enter goes back to a window.
    -- "desktop" keeps the display's own mode, so nothing is stretched.
    t.window.fullscreen = true
    t.window.fullscreentype = "desktop"
    -- Real pixels, not points: the zoom is picked off the short edge in pixels
    -- (main.lua's fit), and a retina phone should get the zoom its pixels earn.
    t.window.highdpi = true
    t.window.usedpiscale = false
    t.window.vsync = 1
    t.modules.audio = false
    t.modules.sound = false
end
