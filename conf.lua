function love.conf(t)
    t.window.title = "RithmBulletHell"
    t.window.width = 1280
    t.window.height = 720
    t.window.highdpi = true -- Исправляет проблемы с масштабированием > 100%
    t.identity = "RithmBulletHell" -- Папка сохранения в AppData
    t.console = false
    t.window.vsync = false -- Let the game settings control VSync
end