local editor = {}
local objects = {}
local map_name = ""
local notification = nil
local notification_timer = 0
local music = nil
local currentTime = 0
local duration = 10 -- Default duration
local isPlaying = false
local waitingForAudio = false
local gridSize = 32 -- Размер сетки
local playbackSpeed = 1.0 -- Скорость воспроизведения
local placementMode = "circle" -- "circle" or "enemy"

-- Helper for directory creation (local + save dir)
local function ensure_dir(path)
    if not love.filesystem.getInfo(path) then
        love.filesystem.createDirectory(path)
    end
    local cmd
    if love.system.getOS() == "Windows" then
        cmd = 'mkdir "' .. path:gsub("/", "\\") .. '" 2>nul'
    else
        cmd = 'mkdir -p "' .. path .. '"'
    end
    os.execute(cmd)
end

function editor.load(folder_name)
    objects = {}
    map_name = folder_name
    currentTime = 0
    isPlaying = false
    music = nil
    waitingForAudio = false
    playbackSpeed = 1.0
    placementMode = "circle"
    
    local dir = "Mmaps/" .. folder_name
    ensure_dir("Mmaps")
    ensure_dir(dir)
    
    -- Загрузка данных карты
    if love.filesystem.getInfo(dir .. "/map.lua") then
        local chunk = love.filesystem.load(dir .. "/map.lua")
        if chunk then
            local ok, data = pcall(chunk)
            if ok and data then
                objects = data.objects or {}
            else
                print("Error loading map data: " .. tostring(data))
            end
        end
    end
    
    -- Попытка загрузить музыку
    editor.loadMusic(dir)
    
    if not music then
        waitingForAudio = true
        editor.notify("Map created! Drop Audio File to start.")
    else
        editor.notify("Editing: " .. map_name)
    end
end

function editor.loadMusic(dir)
    local exts = {"ogg", "mp3", "wav"} -- Reordered: OGG is preferred in Love2D
    
    -- Helper function to attempt loading with fallback
    -- Replace the inner 'tryLoad' function in editor.lua with this:

    local function tryLoad(dataOrPath, name)
        -- Attempt 1: Stream
        local status, result = pcall(love.audio.newSource, dataOrPath, "stream")
        
        if status then
            music = result
            if settings then music:setVolume(settings.music_volume) end
            duration = music:getDuration()
            editor.notify("Music loaded (Stream): " .. name)
            return true
        else
            print("Stream error for " .. name .. ": " .. tostring(result))
        end
        
        -- Attempt 2: Static (Forces full decode)
        status, result = pcall(love.audio.newSource, dataOrPath, "static")
        
        if status then
            music = result
            if settings then music:setVolume(settings.music_volume) end
            duration = music:getDuration()
            editor.notify("Music loaded (Static): " .. name)
            return true
        else
            print("CRITICAL: Static error for " .. name .. ": " .. tostring(result))
        end
        
        return false
    end

    for _, ext in ipairs(exts) do
        local filename = "audio." .. ext
        local path = dir .. "/" .. filename
        
        -- Method A: Standard Love Filesystem
        if love.filesystem.getInfo(path) then
            if tryLoad(path, filename) then return end
        end
        
        -- Method B: IO Fallback (For local files not mounted in SaveDirectory)
        local f = io.open(path, "rb")
        if f then
            local data = f:read("*all")
            f:close()
            if data then
                local fileData = love.filesystem.newFileData(data, filename)
                if tryLoad(fileData, filename .. " (local)") then return end
            end
        end
    end
    
    editor.notify("No valid audio found. Drop MP3/OGG here!")
    print("Audio Error: Files found but could not be decoded.")
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
        currentTime = currentTime + dt * playbackSpeed
    end
end

function editor.draw()
    if waitingForAudio then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("EDITOR: " .. map_name, 10, 10)
        love.graphics.printf("STEP 2: DRAG & DROP AUDIO FILE (MP3/OGG) HERE", 0, love.graphics.getHeight() * 0.4, love.graphics.getWidth(), "center")
        love.graphics.printf("Folder created at: Mmaps/" .. map_name, 0, love.graphics.getHeight() * 0.5, love.graphics.getWidth(), "center")
        if notification_timer > 0 then
            love.graphics.setColor(0, 1, 0, 1)
            love.graphics.print(notification, 10, love.graphics.getHeight() - 30)
        end
        return
    end
    
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    -- 1. Рисуем сетку (Grid)
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.setLineWidth(1)
    for x = 0, w, gridSize do
        love.graphics.line(x, 0, x, h)
    end
    for y = 0, h, gridSize do
        love.graphics.line(0, y, w, y)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("EDITOR: " .. map_name, 10, 10)
    love.graphics.print("Time: " .. string.format("%.2f", currentTime) .. " / " .. string.format("%.2f", duration), 10, 30)
    love.graphics.print("[Space] Play | [+/-] Speed (" .. playbackSpeed .. "x) | [G] Grid | [E] Mode: " .. string.upper(placementMode) .. " | [S] Save", 10, 50)
    
    -- Кнопка сохранения
    local btnX = w - 120
    local btnY = 10
    love.graphics.setColor(0, 0.6, 0, 1)
    love.graphics.rectangle("fill", btnX, btnY, 100, 30, 5, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("SAVE", btnX + 30, btnY + 5)
    
    -- Отрисовка объектов
    local preempt = 1.2 -- Время появления (как AR в osu)
    
    for i, obj in ipairs(objects) do
        local dt = obj.time - currentTime
        
        -- Показываем объекты, которые скоро появятся или только что исчезли
        if dt > -0.2 and dt <= preempt then
            -- Прозрачность зависит от времени
            local alpha = 1
            if dt < 0 then alpha = 1 - (math.abs(dt) / 0.2) end -- Исчезает после удара
            
            love.graphics.setColor(1, 1, 1, alpha)
            
            if obj.type == "enemy" then
                -- Отрисовка врага в редакторе
                love.graphics.setColor(1, 0.2, 0.2, alpha)
                love.graphics.rectangle("line", obj.x - 20, obj.y - 20, 40, 40)
                love.graphics.print("ENEMY", obj.x - 20, obj.y - 35)
            else
                -- Круг объекта (Hit Circle)
                love.graphics.setLineWidth(2)
                love.graphics.circle("line", obj.x, obj.y, 30)
                love.graphics.print(i, obj.x - 5, obj.y - 10)
            end
            
            -- Круг приближения (Approach Circle)
            if dt > 0 then
                local approachScale = 1 + (dt / preempt) * 2 -- От 3x до 1x
                love.graphics.setColor(0.5, 1, 0.5, alpha * 0.8)
                love.graphics.circle("line", obj.x, obj.y, 30 * approachScale)
            else
                -- Эффект "удара" (вспышка)
                love.graphics.setColor(1, 1, 0.5, alpha)
                love.graphics.circle("fill", obj.x, obj.y, 32)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    -- Уведомление
    if notification_timer > 0 then
        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.print(notification, 10, love.graphics.getHeight() - 30)
    end
    
    -- Таймлайн бар
    local barHeight = 30
    
    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.rectangle("fill", 0, h - barHeight, w, barHeight)
    
    if duration > 0 then
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.rectangle("fill", 0, h - barHeight, (currentTime / duration) * w, barHeight)
        -- Индикатор курсора
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", (currentTime / duration) * w - 2, h - barHeight, 4, barHeight)
        
        -- Рисуем засечки объектов на таймлайне
        love.graphics.setColor(1, 1, 0, 0.7)
        for _, obj in ipairs(objects) do
            love.graphics.rectangle("fill", (obj.time / duration) * w, h - barHeight, 2, barHeight)
        end
    end
end

function editor.mousepressed(x, y, button)
    if waitingForAudio then return end
    
    local h = love.graphics.getHeight()
    local barHeight = 30
    local w = love.graphics.getWidth()
    
    -- Клик по кнопке Save
    if x >= w - 120 and x <= w - 20 and y >= 10 and y <= 40 then
        editor.save()
        return
    end
    
    -- Клик по таймлайну
    if y >= h - barHeight then
        if button == 1 and duration > 0 then
            local progress = x / love.graphics.getWidth()
            currentTime = math.max(0, math.min(duration, progress * duration))
            if music then music:seek(currentTime) end
        end
        return
    end

    -- Прилипание к сетке (Snapping)
    local snapX = math.floor(x / gridSize + 0.5) * gridSize
    local snapY = math.floor(y / gridSize + 0.5) * gridSize

    if button == 1 then
        -- Добавляем объект с текущим временем
        table.insert(objects, {
            x = snapX, 
            y = snapY, 
            time = currentTime,
            type = placementMode
        })
        editor.notify("Placed object at " .. string.format("%.2f", currentTime) .. "s")
    elseif button == 2 then
        -- Умное удаление: ищем объект под курсором
        local closestIndex = nil
        local minDist = 40 -- Радиус поиска (чуть больше радиуса круга)
        
        for i, obj in ipairs(objects) do
            local dx = obj.x - x
            local dy = obj.y - y
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist < minDist then
                minDist = dist
                closestIndex = i
            end
        end
        
        if closestIndex then
            table.remove(objects, closestIndex)
            editor.notify("Deleted object")
        end
    end
end

function editor.wheelmoved(x, y)
    if waitingForAudio then return end
    
    local seekAmount = 0.5 -- По умолчанию 0.5 сек
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        seekAmount = 0.05 -- Точная настройка с Shift
    end
    
    currentTime = math.max(0, math.min(duration, currentTime + (y * seekAmount)))
    if music then music:seek(currentTime) end
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
    elseif key == "-" or key == "kp-" then
        playbackSpeed = math.max(0.25, playbackSpeed - 0.25)
        if music then music:setPitch(playbackSpeed) end
        editor.notify("Speed: " .. playbackSpeed .. "x")
    elseif key == "=" or key == "kp+" then
        playbackSpeed = math.min(2.0, playbackSpeed + 0.25)
        if music then music:setPitch(playbackSpeed) end
        editor.notify("Speed: " .. playbackSpeed .. "x")
    elseif key == "g" then
        if gridSize == 32 then gridSize = 16
        elseif gridSize == 16 then gridSize = 8
        else gridSize = 32 end
        editor.notify("Grid size: " .. gridSize)
    elseif key == "e" then
        placementMode = (placementMode == "circle") and "enemy" or "circle"
        editor.notify("Mode: " .. string.upper(placementMode))
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
    
    -- Дублируем сохранение в локальную папку игры (через io), чтобы файлы были доступны пользователю
    local f = io.open(path, "w")
    if f then
        f:write(str)
        f:close()
    end
    
    editor.notify("Saved to " .. path)
    print("Saved map to " .. path)
end

function editor.filedropped(file)
    local filename = file:getFilename()
    local ext = filename:match("%.([^%.]+)$")
    if ext then ext = ext:lower() end
    
    if ext == "mp3" or ext == "ogg" or ext == "wav" then
        local ok, err = file:open("r")
        if not ok then
            editor.notify("Open failed: " .. tostring(err))
            return
        end
        local data = file:read()
        file:close()
        if not data then
            editor.notify("Failed to read file")
            return
        end
        
        local target = "Mmaps/" .. map_name .. "/audio." .. ext
        love.filesystem.write(target, data)
        
        -- Дублируем аудио в локальную папку
        local f = io.open(target, "wb")
        if f then
            f:write(data)
            f:close()
        end
        
        -- Перезагружаем музыку
        if music then music:stop() end
        editor.loadMusic("Mmaps/" .. map_name)
        
        -- Принудительно выходим из режима ожидания, если файл записан
        if music or love.filesystem.getInfo(target) then 
            waitingForAudio = false 
        end
        editor.notify("Imported audio: " .. filename)
    else
        editor.notify("Only MP3/OGG/WAV supported!")
    end
end

return editor