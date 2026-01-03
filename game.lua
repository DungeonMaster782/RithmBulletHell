local player = require("player")
local bullets = require("bullets")
local lasers = require("lasers")

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
local settingsOpen = false
local tempConfig = {}
local state = "playing" -- "playing", "paused", "game_over", "victory"
local menu_selection = 1
local current_volume = 1.0
local titleFont = nil
local menuFont = nil
local backgroundImage = nil
local particleSystem = nil
local backgroundVideo = nil
local backgroundDim = 0.5
local showVideo = true
local pauseTime = 0 -- Время начала паузы
local videoUnsupported = false -- Флаг для отображения предупреждения
local videoOffset = 0 -- Смещение видео (из .osu файла)

-- ======= CONFIG LOADING =======
local function load_config()
    if not love.filesystem.getInfo("config.txt") then return end
    local contents = love.filesystem.read("config.txt")
    print("[GAME] Loading local config...")
    for line in contents:gmatch("[^\r\n]+") do
        local key, value = line:match("^([%w_]+)%s*=%s*([%d%.]+)")
        if key and value then
            config[key] = tonumber(value)
        end
    end
end

local function save_config()
    local content = ""
    for k, v in pairs(config) do
        content = content .. k .. "=" .. v .. "\n"
    end
    love.filesystem.write("config.txt", content)
end

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
                type = isSlider and "slider" or "circle"
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

-- ======= CUSTOM GAME LOAD =======
function game.load_custom(folder_name, settings)
    print("[GAME] Loading custom map: " .. folder_name)
    load_config()
    -- Apply settings
    config.bullet_multiplier = settings.bullet_multiplier
    config.bullet_speed = settings.bullet_speed
    config.bullet_size = settings.bullet_size
    config.player_speed = settings.player_speed
    
    -- Load map data
    local dir = "Mmaps/" .. folder_name
    local path = dir .. "/map.lua"
    hitObjects = {} -- Очищаем старые объекты
    
    if love.filesystem.getInfo(path) then
        local chunk = love.filesystem.load(path)
        if chunk then
            local map_data = chunk()
            if map_data.objects then
                for _, obj in ipairs(map_data.objects) do
                    table.insert(hitObjects, {
                        x = obj.x,
                        y = obj.y,
                        time = (obj.time * 1000), -- Переводим секунды в мс (как в osu)
                        type = obj.type or "circle",
                        preempt = 1200, -- Стандартное время предупреждения
                        exploded = false,
                        shown = false
                    })
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
    state = "playing"
    player.lives = settings.lives
    player.load(love.graphics.getWidth(), love.graphics.getHeight())
    bullets.load()
    mapStartTime = love.timer.getTime()
end

-- ======= GAME FUNCTIONS =======
function game.load(song, difficulty, initial_lives, controls_mode, bg_image, music_volume, bullet_multiplier, bullet_speed, bullet_size, player_speed, show_hitboxes, bg_dim, enable_video)
    print("[GAME] Loading level: " .. song .. " [" .. difficulty .. "]")
    load_config()
    -- Применяем настройки, переданные из меню (они приоритетнее файла)
    if bullet_multiplier then config.bullet_multiplier = bullet_multiplier end
    if bullet_speed then config.bullet_speed = bullet_speed end
    if bullet_size then config.bullet_size = bullet_size end
    if player_speed then config.player_speed = player_speed end
    print("[GAME] Config: Multiplier=" .. config.bullet_multiplier .. ", Speed=" .. config.bullet_speed .. ", Size=" .. config.bullet_size .. ", PlayerSpeed=" .. (config.player_speed or 1.0))

    local map_path = "maps/" .. song .. "/" .. difficulty
    backgroundImage = bg_image
    backgroundDim = bg_dim or 0.5
    showVideo = (enable_video == nil) and true or enable_video
    backgroundVideo = nil
    videoUnsupported = false
    videoOffset = 0
    pauseTime = 0
    state = "playing"
    menu_selection = 1
    local audio_name, video_name
    hitObjects, approachRate, audio_name, video_name, videoOffset = parse_osu(map_path)
    preempt = calc_preempt(approachRate)

    -- Ensure hit objects use the AR-based preempt, not the default value captured during parsing
    if hitObjects then
        for _, obj in ipairs(hitObjects) do
            obj.preempt = preempt
        end
    end

    -- *** ИСПРАВЛЕНИЕ 2: РАСЧЕТ КОЭФФИЦИЕНТОВ МАСШТАБИРОВАНИЯ ***
    -- Стандартный "играбельный" размер поля osu! 512x384 (сдвинут на 50, 50)
    local standard_width = 512
    local standard_height = 384
    local love_width = love.graphics.getWidth()
    local love_height = love.graphics.getHeight()

    scaleX = love_width / 640 -- 640 - ширина игрового поля (512 + 50*2 + запас)
    scaleY = love_height / 480 -- 480 - высота игрового поля (384 + 50*2 + запас)

    -- Выбираем меньший масштаб, чтобы не выходить за границы
    local uniform_scale = math.min(scaleX, scaleY)

    scaleX = uniform_scale * (love_width / 800) -- Коррекция для центровки
    scaleY = uniform_scale * (love_height / 600) -- Коррекция для центровки

    -- Инициализируем player
    if type(initial_lives) ~= "number" then initial_lives = 3 end
    if initial_lives < 1 then initial_lives = 1 end
    if initial_lives > 99 then initial_lives = 99 end
    player.lives = math.floor(initial_lives)
    player.invuln = false
    player.invuln_timer = 0
    player.dead = false
    player.shots = {}
    player.shotCooldown = 0
    -- *** НОВОЕ: Передаем текущие размеры для правильного центрирования ***
    player.load(love_width, love_height)
    if show_hitboxes ~= nil then 
        player.showHitbox = show_hitboxes 
        bullets.showHitbox = show_hitboxes
    end
    player.speed = 200 * (config.player_speed or 1.0) -- Применяем множитель скорости игрока
    if controls_mode then
        player.set_controls_mode(controls_mode)
    end

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

    bullets.load()

    local audio_path = "maps/" .. song .. "/" .. audio_name
    if love.filesystem.getInfo(audio_path) then
        music = love.audio.newSource(audio_path, "stream")
        music:setLooping(false) -- Музыка карты не должна повторяться
        music:setVolume(music_volume or 0.7)
        music:play()
        current_volume = music_volume or 0.7
        print("[AUDIO] Music loaded and playing: " .. audio_path)
    else
        print("WARNING: music file missing:", audio_path)
        current_volume = music_volume or 1.0
    end

    mapStartTime = love.timer.getTime()
    
    titleFont = love.graphics.newFont(30)
    menuFont = love.graphics.newFont(18)

    -- Инициализация системы частиц (простой кружок)
    local p_canvas = love.graphics.newCanvas(8, 8)
    love.graphics.setCanvas(p_canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", 4, 4, 4)
    love.graphics.setCanvas()
    
    particleSystem = love.graphics.newParticleSystem(p_canvas, 1000)
    particleSystem:setParticleLifetime(0.5, 1.0)
    particleSystem:setLinearAcceleration(-50, -50, 50, 50)
    particleSystem:setSpeed(100, 400) -- Добавляем скорость разлета (взрыв)
    particleSystem:setLinearDamping(3) -- Частицы замедляются
    particleSystem:setSpread(math.pi * 2) -- Разлет во все стороны (360 градусов)
    particleSystem:setColors(1, 1, 0.8, 1, 1, 0.5, 0, 1, 1, 0, 0, 0) -- Белый -> Оранжевый -> Красный -> Прозрачный
    particleSystem:setSizes(1.5, 2.5, 0) -- Увеличиваем размер частиц
end

function game.update(dt)
    if settingsOpen or state ~= "playing" then return end -- Пауза

    local currentTime = (love.timer.getTime() - mapStartTime) * 1000

    -- Запуск видео с задержкой (если videoOffset > 0)
    if backgroundVideo and not backgroundVideo:isPlaying() and showVideo and state == "playing" then
        if videoOffset > 0 and currentTime >= videoOffset then
             backgroundVideo:play()
        end
    end

    if particleSystem then particleSystem:update(dt) end

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
        for _, obj in ipairs(hitObjects) do
            -- Переводим координаты в текущее разрешение
            local translated_x = (obj.x * scaleX) + 50
            local translated_y = (obj.y * scaleY) + 50
            
            if obj.type == "slider" then
                local translated_endX = (obj.endX * scaleX) + 50
                local translated_endY = (obj.endY * scaleY) + 50
                
                if not obj.shown and currentTime >= obj.time - obj.preempt then
                    obj.shown = true
                end
                
                if currentTime >= obj.time and currentTime <= obj.time + obj.duration then
                    obj.active = true
                    -- Коллизия с лазером
                    if not player.invuln then
                        local dist = lasers.getDistance(player.x, player.y, translated_x, translated_y, translated_endX, translated_endY)
                        if dist < (player.hitboxRadius + 10) then -- 10 - половина ширины лазера
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
                if not obj.exploded and currentTime >= obj.time then
                    obj.exploded = true
                    if bullets and bullets.explode_circle then
                        -- Используем переведенные координаты для спауна пуль
                        bullets.explode_circle({x = translated_x, y = translated_y, preempt = obj.preempt}, config)
                        -- Эффект частиц при взрыве
                        if particleSystem then
                            particleSystem:setPosition(translated_x, translated_y)
                            particleSystem:emit(30)
                        end
                    end
                end
            end
        end
    end

    -- Проверка столкновений пуль с игроком
    if bullets and bullets.list then
        for _, b in ipairs(bullets.list) do
            local dx = b.x - player.x
            local dy = b.y - player.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if not player.invuln and dist < (player.hitboxRadius + b.radius) then
                player.hit()
            elseif not b.grazed and dist < (player.grazeRadius + b.radius) then
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
    if #hitObjects == 0 and (not music or not music:isPlaying()) and not player.dead then
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
                local tx = (obj.x * scaleX) + 50
                local ty = (obj.y * scaleY) + 50
                local tex = (obj.endX * scaleX) + 50
                local tey = (obj.endY * scaleY) + 50
                lasers.draw(obj, tx, ty, tex, tey, currentTime)
                
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
                local tx = (obj.x * scaleX) + 50
                local ty = (obj.y * scaleY) + 50
                
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
            end
        end
    end
    
    -- Удаляем отработанные объекты
    for i = #hitObjects, 1, -1 do
        local obj = hitObjects[i]
        if obj.exploded and currentTime > obj.time + 100 then
            -- Удаляем отработанный объект карты, чтобы не обрабатывать его дальше
            table.remove(hitObjects, i)
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
        local cx, cy = w / 2, h / 2

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

        -- Заголовок
        if titleFont then love.graphics.setFont(titleFont) end
        love.graphics.printf(title, 0, cy - 100, w, "center")
        love.graphics.setColor(1, 1, 1, 1)
        if menuFont then love.graphics.setFont(menuFont) end

        -- Опции
        for i, opt in ipairs(options) do
            if i == menu_selection then
                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print("> " .. opt, cx - 60, cy - 40 + i * 30)
            else
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.print("  " .. opt, cx - 60, cy - 40 + i * 30)
            end
        end
        
        -- Подсказка для громкости
        if state == "paused" and (options[menu_selection]:match("Volume") or options[menu_selection]:match("Dim") or options[menu_selection]:match("Video")) then
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            love.graphics.print("< Left / Right >", cx + 80, cy - 40 + 3 * 30)
        end
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
        elseif key == "space" then
            player.shoot()
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
        local cx, cy = w / 2, h / 2
        local base_y = cy - 40
        local options_count = (state == "paused") and 6 or 2
        
        for i = 1, options_count do
            local opt_y = base_y + i * 30
            if y >= opt_y and y <= opt_y + 20 then
                menu_selection = i
            end
        end
    end
end

function game.mousepressed(x, y, button)
    -- Обработка кликов в меню паузы/смерти
    if state ~= "playing" and button == 1 then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        local cx, cy = w / 2, h / 2
        local base_y = cy - 40
        
        local options_count = (state == "paused") and 6 or 2
        
        for i = 1, options_count do
            local opt_y = base_y + i * 30
            if y >= opt_y and y <= opt_y + 20 then
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

return game
