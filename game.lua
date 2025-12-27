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
local pauseTime = 0 -- Время начала паузы

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
    local inHitObjects = false

    local file = love.filesystem.newFile(path)
    local ok, err = file:open("r")
    if not ok then
        print("WARNING: failed to open osu file:", path, err)
        return {}, ar, audio_filename
    end

    for line in file:lines() do
        if line:match("^AudioFilename:") then
            audio_filename = line:match("AudioFilename:%s*(.+)")
        elseif line:match("^ApproachRate:") then
            ar = tonumber(line:match("ApproachRate:%s*(%d+%.?%d*)"))
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
    return objects, ar, audio_filename
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

-- ======= GAME FUNCTIONS =======
function game.load(song, difficulty, initial_lives, controls_mode, bg_image, music_volume, bullet_multiplier, bullet_speed, bullet_size, player_speed)
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
    state = "playing"
    menu_selection = 1
    local audio_name
    hitObjects, approachRate, audio_name = parse_osu(map_path)
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
    player.speed = 200 * (config.player_speed or 1.0) -- Применяем множитель скорости игрока
    if controls_mode then
        player.set_controls_mode(controls_mode)
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

    if particleSystem then particleSystem:update(dt) end

    -- Проверка на смерть
    if player.dead then
        print("[GAME] Player died. Game Over.")
        state = "game_over"
        menu_selection = 1
        if music then music:stop() end
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
                        if dist < (player.radius + 10) then -- 10 - половина ширины лазера
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

            if not player.invuln and dist < (player.radius + b.radius) then
                player.hit()
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
        menu_selection = 1
        if music then music:stop() end
    end
end

function game.draw()
    -- Отрисовка фона (затемненного)
    if backgroundImage then
        love.graphics.setColor(1, 1, 1, 0.3) -- Прозрачность 0.3 для затемнения
        local sx = love.graphics.getWidth() / backgroundImage:getWidth()
        local sy = love.graphics.getHeight() / backgroundImage:getHeight()
        local s = math.max(sx, sy) -- Cover mode (заполнение экрана)
        love.graphics.draw(backgroundImage, 0, 0, 0, s, s)
    end

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
    if state == "paused" and pauseTime > 0 then
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

    bullets.draw()

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
            options = {"Resume", "Restart", "Volume: " .. math.floor(current_volume * 100) .. "%", "Exit"}
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
        if state == "paused" and options[menu_selection]:match("Volume") then
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
            menu_selection = 1
        elseif key == "space" then
            player.shoot()
        end
    elseif state == "paused" then
        if key == "escape" then
            print("[GAME] Resumed")
            state = "playing"
            mapStartTime = mapStartTime + (love.timer.getTime() - pauseTime) -- Компенсируем время простоя
            if music then music:play() end
        elseif key == "up" or key == "w" then
            menu_selection = math.max(1, menu_selection - 1)
        elseif key == "down" or key == "s" then
            menu_selection = math.min(4, menu_selection + 1)
        elseif key == "left" and menu_selection == 3 then -- Volume
            current_volume = math.max(0, current_volume - 0.1)
            if music then music:setVolume(current_volume) end
        elseif key == "right" and menu_selection == 3 then -- Volume
            current_volume = math.min(1, current_volume + 0.1)
            if music then music:setVolume(current_volume) end
        elseif key == "return" or key == "space" then
            if menu_selection == 1 then -- Resume
                state = "playing"
                mapStartTime = mapStartTime + (love.timer.getTime() - pauseTime) -- Компенсируем время простоя
                if music then music:play() end
            elseif menu_selection == 2 then -- Restart
                return "restart", current_volume
            elseif menu_selection == 4 then -- Exit
                return "exit", current_volume
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
        local options_count = (state == "paused") and 4 or 2
        
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
        
        local options_count = (state == "paused") and 4 or 2
        
        for i = 1, options_count do
            local opt_y = base_y + i * 30
            if y >= opt_y and y <= opt_y + 20 then
                -- Если кликнули по опции
                if state == "paused" then
                    if i == 1 then 
                        state = "playing"
                        mapStartTime = mapStartTime + (love.timer.getTime() - pauseTime) -- Компенсируем время
                        if music then music:play() end
                    elseif i == 2 then return "restart", current_volume
                    elseif i == 3 then -- Volume click logic
                         current_volume = (current_volume >= 1.0) and 0 or (current_volume + 0.1)
                         if music then music:setVolume(current_volume) end
                    elseif i == 4 then return "exit", current_volume end
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
end

function game.pause()
    if state == "playing" then
        print("[GAME] Paused")
        state = "paused"
        pauseTime = love.timer.getTime() -- Фиксируем время начала паузы
        if music then music:pause() end
        menu_selection = 1
    end
end

return game
