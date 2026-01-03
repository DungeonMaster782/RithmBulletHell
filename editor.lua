local editor = {}
local objects = {}
local map_name = ""
local notification = nil
local notification_timer = 0
local music = nil
local currentTime = 0
local duration = 10 -- Default duration
local isPlaying = false

function editor.load(folder_name)
    objects = {}
    map_name = folder_name
    currentTime = 0
    isPlaying = false
    music = nil
    
    local dir = "Mmaps/" .. folder_name
    if not love.filesystem.getInfo(dir) then
        love.filesystem.createDirectory(dir)
    end
    
    -- Загрузка данных карты
    if love.filesystem.getInfo(dir .. "/map.lua") then
        local chunk = love.filesystem.load(dir .. "/map.lua")
        if chunk then
            local data = chunk()
            objects = data.objects or {}
        end
    end
    
    -- Попытка загрузить музыку
    editor.loadMusic(dir)
    
    editor.notify("Editing: " .. map_name)
end

function editor.loadMusic(dir)
    local exts = {"mp3", "ogg", "wav"}
    for _, ext in ipairs(exts) do
        local path = dir .. "/audio." .. ext
        if love.filesystem.getInfo(path) then
            music = love.audio.newSource(path, "stream")
            duration = music:getDuration()
            editor.notify("Music loaded: audio." .. ext)
            return
        end
    end
    editor.notify("No audio found. Drop MP3/OGG here!")
end

function editor.notify(msg)
    notification = msg
    notification_timer = 3
end

function editor.update(dt)
    if notification_timer > 0 then
        notification_timer = notification_timer - dt
    end
    
    if isPlaying and music then
        currentTime = music:tell()
        if currentTime >= duration then
            isPlaying = false
            currentTime = 0
            music:stop()
        end
    elseif isPlaying then
        currentTime = currentTime + dt
    end
end

function editor.draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("EDITOR: " .. map_name, 10, 10)
    love.graphics.print("Time: " .. string.format("%.2f", currentTime) .. " / " .. string.format("%.2f", duration), 10, 30)
    love.graphics.print("[Space] Play/Pause | [Arrows] Seek | [LMB] Place | [S] Save | [ESC] Exit", 10, 50)
    
    -- Отрисовка объектов
    for i, obj in ipairs(objects) do
        -- Подсвечиваем объекты, которые рядом по времени (в пределах 1 сек)
        local alpha = math.max(0.2, 1 - math.abs(obj.time - currentTime))
        love.graphics.setColor(1, 0, 0, alpha)
        love.graphics.circle("line", obj.x, obj.y, 15)
        love.graphics.print(string.format("%.1f", obj.time), obj.x - 10, obj.y - 20)
    end

    -- Уведомление
    if notification_timer > 0 then
        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.print(notification, 10, love.graphics.getHeight() - 30)
    end
    
    -- Таймлайн бар
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.rectangle("fill", 0, h - 10, w, 10)
    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.rectangle("fill", 0, h - 10, (currentTime / duration) * w, 10)
end

function editor.mousepressed(x, y, button)
    if button == 1 then
        -- Добавляем объект с текущим временем
        table.insert(objects, {
            x = x, 
            y = y, 
            time = currentTime, 
            type = "circle"
        })
        editor.notify("Placed object at " .. string.format("%.2f", currentTime) .. "s")
    elseif button == 2 then
        if #objects > 0 then
            table.remove(objects)
        end
    end
end

function editor.keypressed(key)
    if key == "escape" then
        if music then music:stop() end
        return "exit"
    elseif key == "s" then
        editor.save()
    elseif key == "space" then
        isPlaying = not isPlaying
        if music then
            if isPlaying then music:play() else music:pause() end
        end
    elseif key == "left" then
        currentTime = math.max(0, currentTime - 1)
        if music then music:seek(currentTime) end
    elseif key == "right" then
        currentTime = math.min(duration, currentTime + 1)
        if music then music:seek(currentTime) end
    end
end

function editor.save()
    local str = "return {\n  objects = {\n"
    for _, obj in ipairs(objects) do
        str = str .. string.format("    {x=%d, y=%d, time=%.3f, type=%q},\n", obj.x, obj.y, obj.time, obj.type)
    end
    str = str .. "  }\n}"
    
    local path = "Mmaps/" .. map_name .. "/map.lua"
    love.filesystem.write(path, str)
    editor.notify("Saved to " .. path)
    print("Saved map to " .. path)
end

function editor.filedropped(file)
    local filename = file:getFilename()
    local ext = filename:match("%.([^%.]+)$")
    if ext then ext = ext:lower() end
    
    if ext == "mp3" or ext == "ogg" or ext == "wav" then
        local data = file:read()
        if not data then
            editor.notify("Failed to read file")
            return
        end
        
        local target = "Mmaps/" .. map_name .. "/audio." .. ext
        love.filesystem.write(target, data)
        
        -- Перезагружаем музыку
        if music then music:stop() end
        editor.loadMusic("Mmaps/" .. map_name)
        editor.notify("Imported audio: " .. filename)
    else
        editor.notify("Only MP3/OGG/WAV supported!")
    end
end

return editor