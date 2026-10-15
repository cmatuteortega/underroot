function love.conf(t)
    t.identity = "underfoot"
    t.version = "11.4"
    t.window.title = "Underfoot"
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
    -- Sound is made at load (src/sfx.lua): no files, just these two modules.
    t.modules.audio = true
    t.modules.sound = true
end
