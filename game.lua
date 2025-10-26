local player = require("player")
local bullets = require("bullets")

local game = {}
local hitObjects = {}
local warningObjects = {}
local music = nil
local mapStartTime = 0
local approachRate = 5
local preempt = 1200
local config = { bullet_multiplier = 0.5, bullet_speed = 1.0 }

-- *** НОВЫЕ ПЕРЕМЕННЫЕ ДЛЯ АДАПТАЦИИ ***
local scaleX = 1
local scaleY = 1

-- ======= CONFIG LOADING =======
local function load_config()
if not love.filesystem.getInfo("config.txt") then return end
    local contents = love.filesystem.read("config.txt")
    for line in contents:gmatch("[^\r\n]+") do
        local key, value = line:match("^(%w+)%s*=%s*([%d%.]+)")
        if key and value then
            config[key] = tonumber(value)
            end
            end
            end

            -- ======= .OSU PARSER =======
            local function parse_osu(path)
            local objects = {}
            local ar = 5
            local audio_filename = "audio.mp3"
            local inHitObjects = false

            local file = love.filesystem.newFile(path)
            file:open("r")
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
                                    table.insert(objects, {
                                        x = tonumber(parts[1]),
                                                 y = tonumber(parts[2]),
                                                 time = tonumber(parts[3]),
                                                 exploded = false,
                                                 shown = false,
                                                 preempt = preempt
                                    })
                                    end
                                    end
                                    file:close()
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
                                                function game.load(song, difficulty)
                                                load_config()
                                                local map_path = "maps/" .. song .. "/" .. difficulty
                                                hitObjects, approachRate, audio_name = parse_osu(map_path)
                                                preempt = calc_preempt(approachRate)

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
                                                player.lives = 3
                                                player.invuln = false
                                                player.invuln_timer = 0
                                                player.dead = false
                                                -- *** НОВОЕ: Передаем текущие размеры для правильного центрирования ***
                                                player.load(love_width, love_height)

                                                warningObjects = {}
                                                bullets.load()

                                                local audio_path = "maps/" .. song .. "/" .. audio_name
                                                if love.filesystem.getInfo(audio_path) then
                                                    music = love.audio.newSource(audio_path, "stream")
                                                    music:setLooping(false) -- Музыка карты не должна повторяться
                                                    music:setVolume(0.7)
                                                    music:play()
                                                    else
                                                        print("WARNING: music file missing:", audio_path)
                                                        end

                                                        mapStartTime = love.timer.getTime()
                                                        end

                                                        function game.update(dt)
                                                        local currentTime = (love.timer.getTime() - mapStartTime) * 1000

                                                        -- Проверка на смерть
                                                        if player.dead then
                                                            game.stopMusic()
                                                            return "game_over"
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

                                                                            if not obj.shown and currentTime >= obj.time - obj.preempt then
                                                                                obj.shown = true
                                                                                -- Используем переведенные координаты для предупреждения
                                                                                table.insert(warningObjects, {x = translated_x, y = translated_y, radius = 30 * math.min(scaleX, scaleY)})
                                                                                end
                                                                                if not obj.exploded and currentTime >= obj.time then
                                                                                    obj.exploded = true
                                                                                    if bullets and bullets.explode_circle then
                                                                                        -- Используем переведенные координаты для спауна пуль
                                                                                        bullets.explode_circle({x = translated_x, y = translated_y, preempt = obj.preempt}, config, warningObjects)
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
                                                                                                        end

                                                                                                        function game.draw()
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

                                                                                                                -- Предупреждения
                                                                                                                love.graphics.setColor(0, 1, 0, 0.4)
                                                                                                                for i = #warningObjects, 1, -1 do -- Проходим в обратном порядке для удаления
                                                                                                                    local w = warningObjects[i]
                                                                                                                    love.graphics.circle("line", w.x, w.y, w.radius)
                                                                                                                    end
                                                                                                                    -- Удаляем те, которые уже отработали (если они не удалились в explode_circle)
                                                                                                                    -- На самом деле, они должны удаляться в explode_circle, но добавим проверку:
                                                                                                                    local currentTime = (love.timer.getTime() - mapStartTime) * 1000
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
                                                                                                                            end

                                                                                                                            function game.keypressed(key)
                                                                                                                            if key == "escape" and music then
                                                                                                                                music:stop()
                                                                                                                                elseif key == "space" then
                                                                                                                                    player.shoot()
                                                                                                                                    end
                                                                                                                                    end

                                                                                                                                    function game.stopMusic()
                                                                                                                                    if music then
                                                                                                                                        music:stop()
                                                                                                                                        music = nil
                                                                                                                                        end
                                                                                                                                        end

                                                                                                                                        return game
