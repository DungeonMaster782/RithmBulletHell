function love.conf(t)
    t.window.title = "RhythmHell"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.highdpi = true -- Исправляет проблемы с масштабированием системы (DPI)
    t.modules.joystick = false
end