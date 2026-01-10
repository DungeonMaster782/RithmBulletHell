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
local isPlacingLaser = false
local laserStartX = 0
local laserStartY = 0
local preempt = 1.2 -- Время появления объектов (AR)

-- Menu State
local menu = {
    active = false,
    advanced = false,
    obj = nil,
    x = 0, y = 0, w = 220, h = 180
}

-- Helper: Distance from point to segment (для удаления лазеров)
local function distToSegment(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0 then
        return math.sqrt((px - x1)^2 + (py - y1)^2)
    end
    local t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    t = math.max(0, math.min(1, t))
    local cx, cy = x1 + t * dx, y1 + t * dy
    return math.sqrt((px - cx)^2 + (py - cy)^2)
end

local function getObjectAt(x, y)
    local closestIndex = nil
    local minDist = 40 -- Радиус поиска (чуть больше радиуса круга)
    
    for i, obj in ipairs(objects) do
        -- Проверяем видимость объекта (как в draw)
        local dt = obj.time - currentTime
        local isVisible = (dt > -0.2 and dt <= preempt)
        
        if isVisible then
            local dist = math.huge
            if obj.type == "slider" then
                dist = distToSegment(x, y, obj.x, obj.y, obj.endX or obj.x, obj.endY or obj.y)
            else
                dist = math.sqrt((obj.x - x)^2 + (obj.y - y)^2)
            end
            
            if dist < minDist then
                minDist = dist
                closestIndex = i
            end
        end
    end
    
    return closestIndex, objects[closestIndex]
end

local function removeObjectAt(x, y)
    local idx, _ = getObjectAt(x, y)
    if idx then
        table.remove(objects, idx)
        editor.notify("Deleted object")
        if menu.active then menu.active = false end -- Close menu if deleted
    end
end

-- Helper for directory creation (local + save dir)
local function ensure_dir(path)
    if not love.filesystem.getInfo(path) then
        love.filesystem.createDirectory(path)
    end
    local cmd
    if love.system.getOS() == "Windows" then
        cmd = 'if not exist "' .. path:gsub("/", "\\") .. '" mkdir "' .. path:gsub("/", "\\") .. '"'
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
    isPlacingLaser = false
    menu.active = false
    menu.advanced = false
    
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
    print("Save Directory (Hidden Maps): " .. love.filesystem.getSaveDirectory())
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
                love.graphics.circle("line", obj.x, obj.y, 40)
                love.graphics.print("ENEMY", obj.x - 20, obj.y - 50)
                love.graphics.circle("fill", obj.x, obj.y, 5)
            elseif obj.type == "slider" then
                -- Отрисовка лазера
                love.graphics.setColor(0.5, 0.8, 1, alpha)
                love.graphics.setLineWidth(4)
                love.graphics.line(obj.x, obj.y, obj.endX or obj.x, obj.endY or obj.y)
                love.graphics.setLineWidth(2)
                love.graphics.circle("line", obj.x, obj.y, 10)
                love.graphics.circle("line", obj.endX or obj.x, obj.endY or obj.y, 10)
                love.graphics.print("LASER", (obj.x + (obj.endX or obj.x))/2 - 20, (obj.y + (obj.endY or obj.y))/2 - 10)
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
    
    -- Отрисовка процесса создания лазера (превью линии)
    if isPlacingLaser then
        local mx, my = love.mouse.getPosition()
        local snapX = math.floor(mx / gridSize + 0.5) * gridSize
        local snapY = math.floor(my / gridSize + 0.5) * gridSize
        love.graphics.setColor(0, 1, 1, 0.8)
        love.graphics.setLineWidth(2)
        love.graphics.line(laserStartX, laserStartY, snapX, snapY)
    end
    
    -- === ОТРИСОВКА МЕНЮ НАСТРОЕК ===
    if menu.active and menu.obj then
        local mx, my = menu.x, menu.y
        
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle("fill", mx, my, menu.w, menu.h, 5, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("line", mx, my, menu.w, menu.h, 5, 5)
        
        love.graphics.print("SETTINGS: " .. string.upper(menu.obj.type), mx + 10, my + 10)
        
        local yOff = 40
        local function drawProp(label, val, min, max, step, key)
            love.graphics.print(label, mx + 10, my + yOff)
            love.graphics.print("<", mx + 100, my + yOff)
            love.graphics.print(string.format("%.1f", val):gsub("%.0", ""), mx + 120, my + yOff)
            love.graphics.print(">", mx + 180, my + yOff)
            
            -- Hitboxes for buttons (simple logic in mousepressed, just visual here)
            yOff = yOff + 30
        end
        
        if menu.obj.type == "enemy" then
            menu.obj.hp = menu.obj.hp or 5
            menu.obj.duration = menu.obj.duration or 5.0
            drawProp("HP", menu.obj.hp, 1, 100, 1, "hp")
            drawProp("Duration", menu.obj.duration, 1, 20, 0.5, "duration")
            
            -- Кнопка ADVANCED
            love.graphics.setColor(1, 1, 0)
            love.graphics.print(menu.advanced and "[-] BASIC" or "[+] ADVANCED", mx + 50, my + yOff)
            love.graphics.setColor(1, 1, 1)
            yOff = yOff + 30
            
            if menu.advanced then
                menu.obj.shootInterval = menu.obj.shootInterval or 0.8
                menu.obj.bulletCount = menu.obj.bulletCount or 8
                menu.obj.bulletSpeed = menu.obj.bulletSpeed or 150
                drawProp("Rate (s)", menu.obj.shootInterval, 0.1, 5.0, 0.1, "shootInterval")
                drawProp("Bullets", menu.obj.bulletCount, 1, 50, 1, "bulletCount")
                drawProp("B.Speed", menu.obj.bulletSpeed, 50, 500, 10, "bulletSpeed")
            end
        elseif menu.obj.type == "slider" then
            menu.obj.duration = menu.obj.duration or 300
            drawProp("Duration", menu.obj.duration, 50, 2000, 50, "duration")
        elseif menu.obj.type == "circle" then
            menu.obj.custom_count = menu.obj.custom_count or 0
            menu.obj.custom_speed = menu.obj.custom_speed or 0
            
            -- Кнопка ADVANCED для Circle
            love.graphics.setColor(1, 1, 0)
            love.graphics.print(menu.advanced and "[-] BASIC" or "[+] ADVANCED", mx + 50, my + yOff)
            love.graphics.setColor(1, 1, 1)
            yOff = yOff + 30
            
            if menu.advanced then
                local cTxt = (menu.obj.custom_count == 0) and "Auto" or menu.obj.custom_count
                love.graphics.print("Count", mx + 10, my + yOff)
                love.graphics.print("<", mx + 100, my + yOff)
                love.graphics.print(tostring(cTxt), mx + 120, my + yOff)
                love.graphics.print(">", mx + 180, my + yOff)
                yOff = yOff + 30
                
                local sTxt = (menu.obj.custom_speed == 0) and "Auto" or menu.obj.custom_speed
                love.graphics.print("Speed", mx + 10, my + yOff)
                love.graphics.print("<", mx + 100, my + yOff)
                love.graphics.print(tostring(sTxt), mx + 120, my + yOff)
                love.graphics.print(">", mx + 180, my + yOff)
                yOff = yOff + 30
            end
        end
        
        -- Update menu height for next frame/click check
        menu.h = yOff + 50

        -- Delete Button
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.print("[ DELETE OBJECT ]", mx + 35, my + yOff + 10)
        
        -- Close Button (X)
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.print("X", mx + menu.w - 20, my + 5)
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- ==============================

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
    
    -- === ОБРАБОТКА КЛИКОВ В МЕНЮ ===
    if menu.active and menu.obj then
        local mx, my = menu.x, menu.y
        -- Если клик внутри меню
        if x >= mx and x <= mx + menu.w and y >= my and y <= my + menu.h then
            -- Close (X)
            if x >= mx + menu.w - 25 and y <= my + 25 then
                menu.active = false
                return
            end
            
            -- Properties Logic
            local yOff = 40
            local function checkBtn(val, min, max, step)
                if y >= my + yOff and y <= my + yOff + 20 then
                    if x >= mx + 100 and x <= mx + 115 then -- Left (<)
                        return math.max(min, val - step)
                    elseif x >= mx + 180 and x <= mx + 195 then -- Right (>)
                        return math.min(max, val + step)
                    end
                end
                return val
            end
            
            if menu.obj.type == "enemy" then
                menu.obj.hp = checkBtn(menu.obj.hp, 1, 100, 1)
                yOff = yOff + 30
                menu.obj.duration = checkBtn(menu.obj.duration, 1, 20, 0.5)
                yOff = yOff + 30
                
                -- Advanced Toggle Click
                if y >= my + yOff and y <= my + yOff + 20 then
                    menu.advanced = not menu.advanced
                    return
                end
                yOff = yOff + 30
                
                if menu.advanced then
                    menu.obj.shootInterval = checkBtn(menu.obj.shootInterval, 0.1, 5.0, 0.1)
                    yOff = yOff + 30
                    menu.obj.bulletCount = checkBtn(menu.obj.bulletCount, 1, 50, 1)
                    yOff = yOff + 30
                    menu.obj.bulletSpeed = checkBtn(menu.obj.bulletSpeed, 50, 500, 10)
                end
            elseif menu.obj.type == "slider" then
                menu.obj.duration = checkBtn(menu.obj.duration, 50, 5000, 50)
            elseif menu.obj.type == "circle" then
                -- Advanced Toggle Click
                if y >= my + yOff and y <= my + yOff + 20 then
                    menu.advanced = not menu.advanced
                    return
                end
                yOff = yOff + 30

                if menu.advanced then
                    -- Count
                    local c = menu.obj.custom_count
                    if y >= my + yOff and y <= my + yOff + 20 then
                        if x >= mx + 100 and x <= mx + 115 then c = math.max(0, c - 1) end
                        if x >= mx + 180 and x <= mx + 195 then c = c + 1 end
                    end
                    menu.obj.custom_count = c
                    yOff = yOff + 30
                    -- Speed
                    local s = menu.obj.custom_speed
                    if y >= my + yOff and y <= my + yOff + 20 then
                        if x >= mx + 100 and x <= mx + 115 then s = math.max(0, s - 50) end
                        if x >= mx + 180 and x <= mx + 195 then s = s + 50 end
                    end
                    menu.obj.custom_speed = s
                    yOff = yOff + 30
                end
            end
            
            -- Delete Button (Dynamic Position)
            if y >= my + yOff + 10 and y <= my + yOff + 30 then
                removeObjectAt(menu.obj.x, menu.obj.y)
                menu.active = false
                return
            end
            return -- Consume click
        else
            menu.active = false -- Click outside closes menu
            if button == 1 then return end -- Если левый клик мимо меню - просто закрываем его
        end
    end
    
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
        if placementMode == "slider" then
            if not isPlacingLaser then
                -- Первый клик: начало лазера
                isPlacingLaser = true
                laserStartX = snapX
                laserStartY = snapY
                editor.notify("Laser Start Set. Click for End.")
            else
                -- Второй клик: конец лазера
                table.insert(objects, {
                    x = laserStartX,
                    y = laserStartY,
                    endX = snapX,
                    endY = snapY,
                    time = currentTime,
                    type = "slider",
                    duration = 300 -- Длительность по умолчанию
                })
                isPlacingLaser = false
                editor.notify("Laser Placed at " .. string.format("%.2f", currentTime) .. "s")
            end
        else
            table.insert(objects, {
                x = snapX, y = snapY, time = currentTime, type = placementMode
            })
            editor.notify("Placed " .. placementMode .. " at " .. string.format("%.2f", currentTime) .. "s")
        end
    elseif button == 2 then
        if isPlacingLaser then
            isPlacingLaser = false
            editor.notify("Laser placement cancelled")
            return
        end
        
        -- Правый клик: Открыть меню настроек
        local idx, obj = getObjectAt(x, y)
        if obj then
            menu.active = true
            menu.advanced = false -- Reset advanced state on open
            menu.obj = obj
            menu.x, menu.y = x, y
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
        if placementMode == "circle" then
            placementMode = "slider"
        elseif placementMode == "slider" then
            placementMode = "enemy"
        else
            placementMode = "circle"
        end
        editor.notify("Mode: " .. string.upper(placementMode))
    elseif key == "delete" then
        local mx, my = love.mouse.getPosition()
        removeObjectAt(mx, my)
    end
end

function editor.save()
    local str = "return {\n  objects = {\n"
    for _, obj in ipairs(objects) do
        if obj.type == "slider" then
            str = str .. string.format("    {x=%d, y=%d, endX=%d, endY=%d, time=%.3f, type=%q, duration=%d},\n", obj.x, obj.y, obj.endX or obj.x, obj.endY or obj.y, obj.time, obj.type, obj.duration or 300)
        elseif obj.type == "enemy" then
            str = str .. string.format("    {x=%d, y=%d, time=%.3f, type=%q, duration=%.1f, hp=%d, shootInterval=%.2f, bulletCount=%d, bulletSpeed=%d},\n", 
                obj.x, obj.y, obj.time, obj.type, obj.duration or 5, obj.hp or 5, obj.shootInterval or 0.8, obj.bulletCount or 8, obj.bulletSpeed or 150)
        else
            str = str .. string.format("    {x=%d, y=%d, time=%.3f, type=%q, custom_count=%d, custom_speed=%d},\n", obj.x, obj.y, obj.time, obj.type, obj.custom_count or 0, obj.custom_speed or 0)
        end
    end
    str = str .. "  }\n}"
    
    local path = "Mmaps/" .. map_name .. "/map.lua"
    love.filesystem.write(path, str)
    
    -- Дублируем сохранение в локальную папку игры (через io), чтобы файлы были доступны пользователю
    -- Сначала убедимся, что папка существует локально
    local os_dir = "Mmaps/" .. map_name
    local cmd
    if love.system.getOS() == "Windows" then
        cmd = 'if not exist "' .. os_dir:gsub("/", "\\") .. '" mkdir "' .. os_dir:gsub("/", "\\") .. '"'
    else
        cmd = 'mkdir -p "' .. os_dir .. '"'
    end
    os.execute(cmd)

    local f = io.open(path, "w")
    if f then
        f:write(str)
        f:close()
    end
    
    editor.notify("Saved to " .. path)
    print("Saved map to " .. path)
    print("Full path: " .. love.filesystem.getSaveDirectory() .. "/" .. path)
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