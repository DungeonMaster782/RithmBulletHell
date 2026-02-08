local player = require("player")
local bullets = require("bullets")
local lasers = require("lasers")
local enemies = require("enemies")

local game = {}
local hitObjects = {}
local music = nil
local mapStartTime = 0
local approachRate = 5
local preempt = 1200
local config = { bullet_multiplier = 0.5, bullet_speed = 1.0, bullet_size = 1.0, player_speed = 1.0 }

-- *** НОВЫЕ ПЕРЕМЕННЫЕ ДЛЯ АДАПТАЦИИ ***
local scaleX = 1
local scaleY = 1
local offsetX = 0
local offsetY = 0
local settingsOpen = false
local state = "playing" -- "playing", "paused", "game_over", "victory"
local menu_selection = 1
local current_volume = 1.0
local backgroundImage = nil
local particleSystem = nil
local backgroundVideo = nil
local backgroundDim = 0.5
local showVideo = true
local pauseTime = 0 -- Время начала паузы
local videoUnsupported = false -- Флаг для отображения предупреждения
local videoOffset = 0 -- Смещение видео (из .osu файла)
local lastObjectTime = 0 -- Время окончания последнего объекта


-- ======= .OSU PARSER =======
local function parse_osu(path)
    print("[OSU] Parsing file: " .. path)
    local objects = {}
    local ar = 5
    local audio_filename = "audio.mp3"
    local video_filename = nil
    local video_offset = 0
    local inHitObjects = false

    local file = love.filesystem.newFile(path)
    local ok, err = file:open("r")
    if not ok then
        print("WARNING: failed to open osu file:", path, err)
        return {}, ar, audio_filename, nil, 0
    end

    for line in file:lines() do
        if line:match("^AudioFilename:") then
            audio_filename = line:match("AudioFilename:%s*(.+)")
        elseif line:match("^ApproachRate:") then
            ar = tonumber(line:match("ApproachRate:%s*(%d+%.?%d*)"))
        elseif not inHitObjects and (line:match("^Video,") or line:match("^1,")) then
            local parts = {}
            for part in line:gmatch("[^,]+") do table.insert(parts, part) end
            if #parts >= 3 then
                video_offset = tonumber(parts[2]) or 0
                video_filename = parts[3]:match("^\"?(.-)\"?$") -- remove quotes
                if video_filename then video_filename = video_filename:gsub("\\", "/") end
            end
        elseif line:match("^%[HitObjects%]") then
            inHitObjects = true
        elseif inHitObjects and line ~= "" and not line:match("^%[") then
            local parts = {}
            for part in line:gmatch("[^,]+") do
                table.insert(parts, part)
            end
            
            local objType = tonumber(parts[4]) or 0
            local isSlider = (objType % 4) >= 2
            
            local obj = {
                x = tonumber(parts[1]),
                y = tonumber(parts[2]),
                time = tonumber(parts[3]),
                exploded = false,
                shown = false,
                preempt = preempt,
                type = isSlider and "slider" or "circle",
                volleys_fired = 0
            }
            
            if isSlider then
                local sliderParams = parts[6] or ""
                local lastPoint = nil
                for p in sliderParams:gmatch("[^|]+") do
                    if p:find(":") then lastPoint = p end
                end
                if lastPoint then
                    local lx, ly = lastPoint:match("^(%-?%d+):(%-?%d+)")
                    obj.endX = tonumber(lx) or obj.x
                    obj.endY = tonumber(ly) or obj.y
                else
                    obj.endX, obj.endY = obj.x, obj.y
                end
                obj.duration = 300 -- Длительность лазера в мс
            end
            
            table.insert(objects, obj)
        end
    end
    file:close()
    print("[OSU] Parsed " .. #objects .. " objects. AR: " .. ar .. ", Audio: " .. audio_filename)
    return objects, ar, audio_filename, video_filename, video_offset
end

local function calc_preempt(ar)
    -- Используем формулу из osu!
    if ar < 5 then
        return 1800 - (ar * 120)
    elseif ar > 5 then
        return 1200 - ((ar - 5) * 150)
    else
        return 1200
    end
end

-- ======= HELPER FUNCTIONS =======
local function apply_settings(settings)
    -- Config
    config.bullet_multiplier = settings.bullet_multiplier
    config.bullet_speed = settings.bullet_speed
    config.bullet_size = settings.bullet_size
    config.player_speed = settings.player_speed
    
    -- Audio/Video
    current_volume = settings.music_volume
    backgroundDim = settings.background_dim
    showVideo = settings.show_video
    
    -- Player
    player.lives = settings.lives
    player.speed = 200 * (config.player_speed or 1.0)
    
    if settings.controls_modes and settings.controls_index then
        player.set_controls_mode(settings.controls_modes[settings.controls_index])
    end
    
    if settings.show_hitboxes ~= nil then
        player.showHitbox = settings.show_hitboxes
        bullets.showHitbox = settings.show_hitboxes
    end

    player.maxDashCharges = settings.max_dash_charges
    player.dashRechargeTime = settings.dash_recharge_time
    player.dashDuration = settings.dash_duration
    player.baseHitboxRadius = settings.hitbox_radius
    player.invulnDuration = settings.invuln_time
end

local function reset_state()
    state = "playing"
    menu_selection = 1
    pauseTime = 0
    bullets.load()
    
    
    -- Particles
    local p_canvas = love.graphics.newCanvas(8, 8)
    love.graphics.setCanvas(p_canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", 4, 4, 4)
    love.graphics.setCanvas()
    
    particleSystem = love.graphics.newParticleSystem(p_canvas, 1000)
    particleSystem:setParticleLifetime(0.5, 1.0)
    particleSystem:setLinearAcceleration(-50, -50, 50, 50)
    particleSystem:setSpeed(100, 400)
    particleSystem:setLinearDamping(3)
    particleSystem:setSpread(math.pi * 2)
    particleSystem:setColors(1, 1, 0.8, 1, 1, 0.5, 0, 1, 1, 0, 0, 0)
    particleSystem:setSizes(1.5, 2.5, 0)
end

-- ======= CUSTOM GAME LOAD =======
function game.load_custom(folder_name, settings, startTime)
    print("[GAME] Loading custom map: " .. folder_name)
    
    if music then music:stop() end
    if backgroundVideo then backgroundVideo:pause() end

    apply_settings(settings)
    enemies.load()
    
    -- Сброс масштабирования для кастомных карт (они используют абсолютные координаты)
    scaleX, scaleY = 1, 1
    offsetX, offsetY = 0, 0
    
    -- Load map data
    local dir = "Mmaps/" .. folder_name
    local path = dir .. "/map.lua"
    hitObjects = {} -- Очищаем старые объекты
    
    local firstObjectTime = math.huge
    lastObjectTime = 0
    
    if love.filesystem.getInfo(path) then
        local chunk = love.filesystem.load(path)
        if chunk then
            local map_data = chunk()
            if map_data.objects then
                for _, obj in ipairs(map_data.objects) do
                    local newObj = {
                        x = obj.x,
                        y = obj.y,
                        time = (obj.time * 1000), -- Переводим секунды в мс (как в osu)
                        type = obj.type or "circle", -- circle, slider, enemy
                        preempt = 1200, -- Стандартное время предупреждения
                        exploded = false,
                        shown = false,
                        volleys_fired = 0
                    }
                    
                    if newObj.type == "slider" then
                        newObj.endX = obj.endX or obj.x
                        newObj.endY = obj.endY or obj.y
                        newObj.duration = obj.duration or 300
                    elseif newObj.type == "enemy" then
                        newObj.duration = obj.duration
                        newObj.hp = obj.hp
                        newObj.shootInterval = obj.shootInterval
                        newObj.bulletCount = obj.bulletCount
                        newObj.bulletSpeed = obj.bulletSpeed
                    elseif newObj.type == "circle" then
                        newObj.custom_count = obj.custom_count
                        newObj.custom_speed = obj.custom_speed
                        newObj.angle_offset = obj.angle_offset
                        newObj.spread_angle = obj.spread_angle
                        newObj.volleys = obj.volleys
                        newObj.volley_interval = obj.volley_interval
                        newObj.spin = obj.spin
                    end
                    
                    table.insert(hitObjects, newObj)
                    
                    if obj.time * 1000 < firstObjectTime then firstObjectTime = obj.time * 1000 end
                    local endTime = obj.time * 1000
                    if endTime > lastObjectTime then lastObjectTime = endTime end
                end
            end
            print("[GAME] Loaded " .. #hitObjects .. " objects")
        end
    end
    
    -- Load Audio
    local exts = {"mp3", "ogg", "wav"}
    music = nil
    for _, ext in ipairs(exts) do
        local audio_path = dir .. "/audio." .. ext
        if love.filesystem.getInfo(audio_path) then
            music = love.audio.newSource(audio_path, "stream")
            music:setVolume(settings.music_volume)
            music:play()
            print("[GAME] Loaded custom audio: " .. audio_path)
            break
        end
    end
    
    -- Reset game state
    reset_state()
    player.load(love.graphics.getWidth(), love.graphics.getHeight())
    mapStartTime = love.timer.getTime()
    
    if startTime then
        -- Запуск с указанной секунды (из редактора)
        if music then music:seek(startTime) end
        mapStartTime = mapStartTime - startTime
        
        -- Помечаем прошедшие объекты как взорванные, чтобы они не сработали все сразу
        local startMs = startTime * 1000
        for _, obj in ipairs(hitObjects) do
            local endTime = obj.time
            if obj.type == "slider" then endTime = obj.time + (obj.duration or 0) end
            
            if endTime < startMs then
                obj.shown = true
                obj.exploded = true
                obj.active = false
                if obj.type == "circle" then obj.volleys_fired = obj.volleys or 999 end
            end
        end
    elseif firstObjectTime ~= math.huge then
        -- Пропуск интро (5 секунд до первого объекта)
        local skipTime = math.max(0, firstObjectTime - 5000)
        if skipTime > 0 then
            if music then music:seek(skipTime / 1000) end
            mapStartTime = mapStartTime - (skipTime / 1000)
        end
    end
end

-- Функция обновления масштаба для всех сущностей
local function update_game_scale(scale)
    scaleX = scale
    scaleY = scale
    
    -- Обновляем масштаб игрока и врагов
    player.setScale(scale)
    enemies.setScale(scale)
    
    -- Корректируем скорость игрока с учетом масштаба
    player.speed = 200 * (config.player_speed or 1.0) * scale
end

-- ======= GAME FUNCTIONS =======
function game.load(song, difficulty, bg_image, settings)
    print("[GAME] Loading level: " .. song .. " [" .. difficulty .. "]")
    apply_settings(settings)
    if music then music:stop() end
    if backgroundVideo then backgroundVideo:pause() end

    enemies.load()
    print("[GAME] Config: Multiplier=" .. config.bullet_multiplier .. ", Speed=" .. config.bullet_speed .. ", Size=" .. config.bullet_size .. ", PlayerSpeed=" .. (config.player_speed or 1.0))

    local map_path = "maps/" .. song .. "/" .. difficulty
    backgroundImage = bg_image
    -- backgroundDim and showVideo are set in apply_settings
    
    backgroundVideo = nil
    videoUnsupported = false
    videoOffset = 0
    local audio_name, video_name
    hitObjects, approachRate, audio_name, video_name, videoOffset = parse_osu(map_path)
    preempt = calc_preempt(approachRate)

    -- Расчет времени начала и конца, обновление preempt
    local firstObjectTime = math.huge
    lastObjectTime = 0
    
    if hitObjects then
        for _, obj in ipairs(hitObjects) do
            obj.preempt = preempt
            if obj.time < firstObjectTime then firstObjectTime = obj.time end
            local endTime = obj.time
            if obj.type == "slider" then endTime = obj.time + (obj.duration or 0) end
            if endTime > lastObjectTime then lastObjectTime = endTime end
        end
    end

    -- *** ИСПРАВЛЕНИЕ 2: РАСЧЕТ КОЭФФИЦИЕНТОВ МАСШТАБИРОВАНИЯ ***
    -- Стандартный "играбельный" размер поля osu! 512x384 (сдвинут на 50, 50)
    local standard_width = 512
    local standard_height = 384
    local love_width = love.graphics.getWidth()
    local love_height = love.graphics.getHeight()

    -- Используем виртуальное разрешение 960x720 (чтобы элементы не были слишком огромными)
    local target_w, target_h = 960, 720
    local scale = math.min(love_width / target_w, love_height / target_h)
    
    update_game_scale(scale)
    
    -- Центрируем игровое поле (512x384) на экране
    offsetX = (love_width - 512 * scale) / 2
    offsetY = (love_height - 384 * scale) / 2

    reset_state()

    -- Инициализируем player
    -- *** НОВОЕ: Передаем текущие размеры для правильного центрирования ***
    player.load(love_width, love_height)
    -- Применяем масштаб к игроку после загрузки
    player.setScale(scale)

    -- Загрузка видео
    if video_name then
        local video_path = "maps/" .. song .. "/" .. video_name
        
        -- Проверяем наличие .ogv версии, так как LÖVE не читает mp4
        local ext = video_name:match("%.([^%.]+)$")
        if ext and (ext:lower() == "mp4" or ext:lower() == "avi" or ext:lower() == "mkv") then
            local ogv_name = video_name:gsub("%.[^%.]+$", ".ogv")
            local ogv_path = "maps/" .. song .. "/" .. ogv_name
            if love.filesystem.getInfo(ogv_path) then
                print("[VIDEO] Found converted OGV file: " .. ogv_path)
                video_path = ogv_path
            end
        end

        if love.filesystem.getInfo(video_path) then
            local success, v = pcall(love.graphics.newVideo, video_path)
            if success then
                backgroundVideo = v
                if backgroundVideo:getSource() then backgroundVideo:getSource():setVolume(0) end -- Mute video audio
                
                -- Если оффсет отрицательный (видео началось раньше песни), перематываем
                if videoOffset <= 0 then
                    backgroundVideo:play()
                    backgroundVideo:seek(-videoOffset / 1000)
                end
                print("[VIDEO] Loaded video: " .. video_path .. " Offset: " .. videoOffset)
            else
                print("[VIDEO] Failed to load video: " .. video_path)
                if video_path:match("%.mp4$") or video_path:match("%.avi$") then
                    print("[VIDEO] NOTE: LÖVE engine typically supports only Ogg Theora (.ogv) videos!")
                    videoUnsupported = true
                end
            end
        end
    end

    local audio_path = "maps/" .. song .. "/" .. audio_name
    if love.filesystem.getInfo(audio_path) then
        music = love.audio.newSource(audio_path, "stream")
        music:setLooping(false) -- Музыка карты не должна повторяться
        music:setVolume(current_volume)
        music:play()
        print("[AUDIO] Music loaded and playing: " .. audio_path)
    else
        print("WARNING: music file missing:", audio_path)
    end

    mapStartTime = love.timer.getTime()
    
    -- Пропуск интро (5 секунд до первого объекта)
    if firstObjectTime ~= math.huge then
        local skipTime = math.max(0, firstObjectTime - 5000)
        if skipTime > 0 then
            if music then music:seek(skipTime / 1000) end
            mapStartTime = mapStartTime - (skipTime / 1000)
            
            if backgroundVideo then
                local vidPos = (skipTime - videoOffset) / 1000
                if vidPos > 0 then backgroundVideo:seek(vidPos) end
            end
            print("[GAME] Skipped intro: " .. skipTime .. "ms")
        end
    end
end

function game.update(dt)
    if settingsOpen or state ~= "playing" then return end -- Пауза

    local currentTime = (love.timer.getTime() - mapStartTime) * 1000

    -- Запуск видео с задержкой (если videoOffset > 0)
    if backgroundVideo and not backgroundVideo:isPlaying() and showVideo and state == "playing" then
        if currentTime >= videoOffset then
             backgroundVideo:play()
        end
    end

    if particleSystem then particleSystem:update(dt) end
    enemies.update(dt, player.shots)

    -- Проверка на смерть
    if player.dead then
        print("[GAME] Player died. Game Over.")
        state = "game_over"
        pauseTime = love.timer.getTime()
        menu_selection = 1
        if music then music:stop() end
        if backgroundVideo then backgroundVideo:pause() end
        return
    end

    -- Инвулн таймер
    if player.invuln then
        player.invuln_timer = player.invuln_timer - dt
        if player.invuln_timer <= 0 then
            player.invuln = false
            player.invuln_timer = 0
        end
    end

    -- Объекты карты (создание пуль)
    if hitObjects then
        local write_idx = 1
        for read_idx = 1, #hitObjects do
            local obj = hitObjects[read_idx]
            -- Переводим координаты в текущее разрешение
            local translated_x = (obj.x * scaleX) + offsetX
            local translated_y = (obj.y * scaleY) + offsetY
            
            if obj.type == "enemy" then
                if not obj.shown and currentTime >= obj.time then
                    obj.shown = true
                    obj.exploded = true
                    enemies.spawn(translated_x, translated_y, {
                        duration=obj.duration, 
                        hp=obj.hp,
                        shootInterval=obj.shootInterval,
                        bulletCount=obj.bulletCount,
                        bulletSpeed=obj.bulletSpeed
                    })
                end
            elseif obj.type == "slider" then
                local translated_endX = (obj.endX * scaleX) + offsetX
                local translated_endY = (obj.endY * scaleY) + offsetY
                
                if not obj.shown and currentTime >= obj.time - obj.preempt then
                    obj.shown = true
                end
                
                if currentTime >= obj.time and currentTime <= obj.time + obj.duration then
                    obj.active = true
                    -- Коллизия с лазером
                    if not player.invuln then
                        if lasers.checkCollision(player.x, player.y, player.hitboxRadius + 10, translated_x, translated_y, translated_endX, translated_endY) then
                            player.hit()
                        end
                    end
                elseif currentTime > obj.time + obj.duration then
                    obj.active = false
                    obj.exploded = true
                end
            else
                -- Логика для кругов (пуль)
                if not obj.shown and currentTime >= obj.time - obj.preempt then
                    obj.shown = true
                end
                
                if currentTime >= obj.time and not obj.exploded then
                    local volleys = obj.volleys or 1
                    local interval = (obj.volley_interval or 0.1) * 1000 -- переводим в мс
                    
                    -- Вычисляем, сколько залпов должно было уже произойти
                    local time_since_start = currentTime - obj.time
                    local expected_volleys = math.floor(time_since_start / interval) + 1
                    
                    if expected_volleys > volleys then expected_volleys = volleys end
                    
                    while obj.volleys_fired < expected_volleys do
                        obj.volleys_fired = obj.volleys_fired + 1
                        
                        -- Вычисляем угол с учетом закрутки (Spin)
                        local current_spin = (obj.spin or 0) * (obj.volleys_fired - 1)
                        local current_angle = (obj.angle_offset or 0) + current_spin
                        
                        if bullets and bullets.explode_circle then
                            -- Создаем временный объект параметров для передачи в bullets
                            local spawn_params = {
                                x = translated_x, y = translated_y, preempt = obj.preempt,
                                custom_count = obj.custom_count, 
                                custom_speed = obj.custom_speed, -- Это базовая скорость, она будет умножена на scale внутри explode_circle
                                angle_offset = current_angle, spread_angle = obj.spread_angle
                            }
                            -- Передаем текущий масштаб в конфиг для пуль
                            config.scale = scaleX
                            bullets.explode_circle(spawn_params, config)
                            
                            if particleSystem then
                                particleSystem:setPosition(translated_x, translated_y)
                                particleSystem:emit(30)
                            end
                        end
                    end
                    
                    if obj.volleys_fired >= volleys then
                        obj.exploded = true
                    end
                end
            end
            
            -- Очистка отработанных объектов (перенесено из draw)
            if not (obj.exploded and currentTime > obj.time + 100) then
                if read_idx ~= write_idx then
                    hitObjects[write_idx] = obj
                end
                write_idx = write_idx + 1
            end
        end
        for i = write_idx, #hitObjects do
            hitObjects[i] = nil
        end
    end

    -- Проверка столкновений пуль с игроком
    if bullets and bullets.list then
        for _, b in ipairs(bullets.list) do
            local dx = b.x - player.x
            local dy = b.y - player.y
            local distSq = dx * dx + dy * dy

            if not player.invuln and distSq < (player.hitboxRadius + b.radius)^2 then
                player.hit()
            elseif not b.grazed and distSq < (player.grazeRadius + b.radius)^2 then
                b.grazed = true
                player.graze()
            end
        end
    end

    player.update(dt)
    if bullets and bullets.update then
        bullets.update(dt)
    end

    -- Проверка на победу (все объекты показаны, пуль нет, музыка закончилась)
    if #hitObjects == 0 and currentTime >= lastObjectTime + 3000 and not player.dead then
        -- Небольшая задержка перед победой, чтобы убедиться
        print("[GAME] Victory condition met!")
        state = "victory"
        pauseTime = love.timer.getTime()
        menu_selection = 1
        if music then music:stop() end
        if backgroundVideo then backgroundVideo:pause() end
    end
end

function game.draw()
    -- Отрисовка фона / видео
    love.graphics.setColor(1, 1, 1, 1)
    
    if backgroundImage then
        local sx = love.graphics.getWidth() / backgroundImage:getWidth()
        local sy = love.graphics.getHeight() / backgroundImage:getHeight()
        local s = math.max(sx, sy) -- Cover mode (заполнение экрана)
        love.graphics.draw(backgroundImage, 0, 0, 0, s, s)
    end

    if backgroundVideo and showVideo then
        local vw, vh = backgroundVideo:getDimensions()
        local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
        local scale = math.max(sw/vw, sh/vh)
        love.graphics.draw(backgroundVideo, 0, 0, 0, scale, scale)
    elseif showVideo and videoUnsupported then
        -- Если видео включено, но формат не поддерживается
        love.graphics.setColor(1, 0, 0, 0.7)
        love.graphics.print("Video format not supported (MP4). Run convert_videos.bat!", 10, 40)
    end

    -- Затемнение фона (Background Dim)
    if backgroundDim > 0 then
        love.graphics.setColor(0, 0, 0, backgroundDim)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    end
    
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.print("Move with arrows, ESC to quit", 10, love.graphics.getHeight() - 30)

    -- Мигаем игроком при инвулне
    if player.invuln then
        local alpha = math.floor(love.timer.getTime() * 10) % 2 == 0 and 0.3 or 1
        love.graphics.setColor(1, 1, 1, alpha)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end

    player.draw()
    enemies.draw(player.showHitbox)
    love.graphics.setColor(1, 1, 1, 1)

    -- Отрисовка частиц (с режимом сложения для свечения)
    if particleSystem then
        love.graphics.setBlendMode("add")
        love.graphics.draw(particleSystem, 0, 0)
        love.graphics.setBlendMode("alpha")
    end

    -- Отрисовка лазеров
    -- Если пауза, используем зафиксированное время паузы, иначе текущее
    local t = love.timer.getTime()
    if (state == "paused" or state == "game_over" or state == "victory") and pauseTime > 0 then
        t = pauseTime
    end
    local currentTime = (t - mapStartTime) * 1000
    
    if hitObjects then
        for _, obj in ipairs(hitObjects) do
            if obj.type == "slider" and obj.shown and not obj.exploded then
                local tx = (obj.x * scaleX) + offsetX
                local ty = (obj.y * scaleY) + offsetY
                local tex = (obj.endX * scaleX) + offsetX
                local tey = (obj.endY * scaleY) + offsetY
                lasers.draw(obj, tx, ty, tex, tey, currentTime, scaleX)
                
                -- Отрисовка хитбокса лазера (если включено отображение)
                if player.showHitbox then
                    love.graphics.setColor(1, 0, 0, 0.4)
                    local oldW = love.graphics.getLineWidth()
                    love.graphics.setLineWidth(20) -- Ширина лазера (радиус 10 * 2)
                    love.graphics.line(tx, ty, tex, tey)
                    love.graphics.setLineWidth(oldW)
                    love.graphics.setColor(1, 1, 1, 1)
                end
            elseif obj.type == "circle" and obj.shown and not obj.exploded then
                -- Отрисовка предупреждающего кольца (Approach Circle)
                local tx = (obj.x * scaleX) + offsetX
                local ty = (obj.y * scaleY) + offsetY
                
                -- Прогресс от 0 (появление) до 1 (взрыв)
                local progress = 1 - ((obj.time - currentTime) / obj.preempt)
                if progress < 0 then progress = 0 end
                
                -- Кольцо сужается к центру (эффект osu!)
                -- Начальный радиус в 3 раза больше конечного
                local base_radius = 30 * math.min(scaleX, scaleY)
                local current_radius = base_radius * (1 + (1 - progress) * 2)
                
                love.graphics.setColor(0, 1, 0, 0.6 * progress) -- Становится ярче
                love.graphics.circle("line", tx, ty, current_radius)
                love.graphics.setColor(1, 1, 1, 0.2) -- Слабая точка в центре
                love.graphics.circle("fill", tx, ty, 5)
                
                -- Отрисовка хитбокса круга (спаунера)
                if player.showHitbox then
                    love.graphics.setColor(1, 0, 0, 0.5)
                    love.graphics.circle("line", tx, ty, 30 * math.min(scaleX, scaleY))
                end
            end
        end
    end
    
    -- Жизни
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Lives: " .. player.lives, 10, 10)
    
    -- Счетчик дешей
    local dashText = "Dash: " .. player.dashCharges .. "/" .. player.maxDashCharges
    if player.dashCharges < player.maxDashCharges then dashText = dashText .. " (" .. string.format("%.1f", player.dashRechargeTime - player.dashRechargeTimer) .. ")" end
    love.graphics.print(dashText, 10, 30)
    love.graphics.print("Score: " .. player.score, 10, 50)

    bullets.draw()
    player.drawHitbox()

    -- ОТРИСОВКА МЕНЮ (ПАУЗА / GAME OVER / VICTORY)
    if state ~= "playing" and not settingsOpen then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        local ui_scale = h / 720 -- Масштаб интерфейса относительно высоты 720p

        -- Затемнение
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, w, h)

        local title = ""
        local options = {}

        if state == "paused" then
            title = "PAUSED"
            local vid_status = showVideo and "On" or "Off"
            options = {
                "Resume", 
                "Restart", 
                "Volume: " .. math.floor(current_volume * 100) .. "%", 
                "Dim: " .. math.floor(backgroundDim * 100) .. "%",
                "Video: " .. vid_status,
                "Exit"
            }
        elseif state == "game_over" then
            title = "GAME OVER"
            love.graphics.setColor(1, 0, 0, 1)
            options = {"Restart", "Exit"}
        elseif state == "victory" then
            title = "VICTORY!"
            love.graphics.setColor(0, 1, 0, 1)
            options = {"Restart", "Exit"}
        end

        love.graphics.push()
        love.graphics.translate(w/2, h/2) -- Сдвигаем начало координат в центр экрана
        love.graphics.scale(ui_scale)     -- Применяем масштаб

        -- Заголовок
        if fonts.title then love.graphics.setFont(fonts.title) end
        -- Рисуем относительно центра (0,0)
        love.graphics.printf(title, -400, -150, 800, "center")
        love.graphics.setColor(1, 1, 1, 1)
        if fonts.menu then love.graphics.setFont(fonts.menu) end

        -- Опции
        local start_y = -40
        local line_h = 40

        for i, opt in ipairs(options) do
            local str = opt
            if i == menu_selection then
                love.graphics.setColor(1, 1, 0, 1)
                str = "> " .. str .. " <"
            else
                love.graphics.setColor(1, 1, 1, 1)
            end
            love.graphics.printf(str, -400, start_y + (i-1)*line_h, 800, "center")
        end
        
        -- Подсказка для громкости
        if state == "paused" and (options[menu_selection]:match("Volume") or options[menu_selection]:match("Dim") or options[menu_selection]:match("Video")) then
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            love.graphics.printf("< Left / Right >", -400, start_y + (#options)*line_h + 10, 800, "center")
        end
        
        love.graphics.pop()
    end
end

function game.keypressed(key)
    if state == "playing" then
        if key == "escape" then
            print("[GAME] Paused")
            state = "paused"
            pauseTime = love.timer.getTime() -- Фиксируем время начала паузы
            if music then music:pause() end
            if backgroundVideo then backgroundVideo:pause() end
            menu_selection = 1
        elseif key == "lctrl" or key == "rctrl" then
            player.attemptDash()
        elseif (key == player.controls.up or key == player.controls.down or 
                key == player.controls.left or key == player.controls.right) and 
               (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
            player.attemptDash()
        end
    elseif state == "paused" then
        if key == "escape" then
            print("[GAME] Resumed")
            state = "playing"
            mapStartTime = mapStartTime + (love.timer.getTime() - pauseTime) -- Компенсируем время простоя
            if music then music:play() end
            
            -- Запускаем видео только если пришло его время
            local t = (love.timer.getTime() - mapStartTime) * 1000
            if backgroundVideo and (t >= videoOffset or videoOffset <= 0) then backgroundVideo:play() end
            
        elseif key == "up" or key == "w" then
            menu_selection = menu_selection - 1
            if menu_selection < 1 then menu_selection = 6 end
        elseif key == "down" or key == "s" then
            menu_selection = menu_selection + 1
            if menu_selection > 6 then menu_selection = 1 end
        elseif key == "left" and menu_selection == 3 then -- Volume
            current_volume = math.max(0, current_volume - 0.1)
            if music then music:setVolume(current_volume) end
        elseif key == "right" and menu_selection == 3 then -- Volume
            current_volume = math.min(1, current_volume + 0.1)
            if music then music:setVolume(current_volume) end
        elseif key == "left" and menu_selection == 4 then -- Dim
            backgroundDim = math.max(0, backgroundDim - 0.1)
        elseif key == "right" and menu_selection == 4 then -- Dim
            backgroundDim = math.min(1, backgroundDim + 0.1)
        elseif (key == "left" or key == "right") and menu_selection == 5 then -- Video
            showVideo = not showVideo
        elseif key == "return" or key == "space" then
            if menu_selection == 1 then -- Resume
                state = "playing"
                mapStartTime = mapStartTime + (love.timer.getTime() - pauseTime) -- Компенсируем время простоя
                if music then music:play() end
                
                local t = (love.timer.getTime() - mapStartTime) * 1000
                if backgroundVideo and (t >= videoOffset or videoOffset <= 0) then backgroundVideo:play() end
                
            elseif menu_selection == 2 then -- Restart
                return "restart", current_volume, backgroundDim, showVideo
            elseif menu_selection == 6 then -- Exit
                return "exit", current_volume, backgroundDim, showVideo
            end
        end
    elseif state == "game_over" or state == "victory" then
        if key == "up" or key == "down" or key == "w" or key == "s" then
            menu_selection = (menu_selection == 1) and 2 or 1
        elseif key == "return" or key == "space" then
            if menu_selection == 1 then -- Restart
                return "restart", current_volume
            elseif menu_selection == 2 then -- Exit
                return "exit", current_volume
            end
        end
    end
end

function game.mousemoved(x, y)
    if state ~= "playing" and not settingsOpen then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        local ui_scale = h / 720
        -- Переводим Y мыши в локальные координаты меню
        local local_y = (y - h/2) / ui_scale
        
        local start_y = -40
        local line_h = 40
        local options_count = (state == "paused") and 6 or 2
        
        for i = 1, options_count do
            local opt_y = start_y + (i-1) * line_h
            if local_y >= opt_y and local_y <= opt_y + 30 then
                menu_selection = i
            end
        end
    end
end

function game.mousepressed(x, y, button)
    -- Обработка кликов в меню паузы/смерти
    if state ~= "playing" and button == 1 then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        local ui_scale = h / 720
        local local_y = (y - h/2) / ui_scale
        
        local start_y = -40
        local line_h = 40
        local options_count = (state == "paused") and 6 or 2
        
        for i = 1, options_count do
            local opt_y = start_y + (i-1) * line_h
            if local_y >= opt_y and local_y <= opt_y + 30 then
                -- Если кликнули по опции
                if state == "paused" then
                    if i == 1 then 
                        state = "playing"
                        mapStartTime = mapStartTime + (love.timer.getTime() - pauseTime) -- Компенсируем время
                        if music then music:play() end
                        
                        local t = (love.timer.getTime() - mapStartTime) * 1000
                        if backgroundVideo and (t >= videoOffset or videoOffset <= 0) then backgroundVideo:play() end
                        
                    elseif i == 2 then return "restart", current_volume, backgroundDim, showVideo
                    elseif i == 3 then -- Volume click logic
                         current_volume = (current_volume >= 1.0) and 0 or (current_volume + 0.1)
                         if music then music:setVolume(current_volume) end
                    elseif i == 4 then -- Dim click
                        backgroundDim = (backgroundDim >= 1.0) and 0 or (backgroundDim + 0.1)
                    elseif i == 5 then -- Video click
                        showVideo = not showVideo
                    elseif i == 6 then return "exit", current_volume, backgroundDim, showVideo end
                else -- game_over or victory
                    if i == 1 then return "restart", current_volume
                    elseif i == 2 then return "exit", current_volume end
                end
            end
        end
    end
end

function game.stopMusic()
    if music then
        music:stop()
        music = nil
    end
    if backgroundVideo then
        backgroundVideo:pause()
        backgroundVideo = nil
    end
end

function game.pause()
    if state == "playing" then
        print("[GAME] Paused")
        state = "paused"
        pauseTime = love.timer.getTime() -- Фиксируем время начала паузы
        if music then music:pause() end
        if backgroundVideo then backgroundVideo:pause() end
        menu_selection = 1
    end
end

function game.resize(w, h)
    -- Пересчитываем масштаб игрового поля при изменении размера окна
    local target_w, target_h = 960, 720
    local scale = math.min(w / target_w, h / target_h)
    
    update_game_scale(scale)
    
    -- Центрируем игровое поле (512x384) на экране
    offsetX = (w - 512 * scale) / 2
    offsetY = (h - 384 * scale) / 2
    
    if player then
        player.screenWidth = w
        player.screenHeight = h
    end
end

return game
