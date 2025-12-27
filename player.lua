local player = {
    x = 400,
    y = 300,
    radius = 16,
    speed = 200,
    texture = nil,
    lives = 3,
    invuln = false,
    invuln_timer = 0,
    dead = false,
    shots = {},        -- список пуль
    shotCooldown = 0,   -- задержка между выстрелами
    controls = {
        up = "up",
        down = "down",
        left = "left",
        right = "right"
    }
}

local function load_controls_from_properties()
    if not love.filesystem.getInfo("config.properties") then return end
    print("[PLAYER] Loading controls from config.properties...")
    local contents = love.filesystem.read("config.properties")
    if not contents then return end

    local function normalize_key(value)
        if type(value) ~= "string" then return nil end
        value = value:match("^%s*(.-)%s*$")
        if value == "" then return nil end
        return value:lower()
    end

    local function try_set_control(field, value)
        local k = normalize_key(value)
        if not k then return end

        local ok = pcall(love.keyboard.isDown, k)
        if ok then
            player.controls[field] = k
            print("[PLAYER] Control set: " .. field .. " -> " .. k)
        else
            print("WARNING: Invalid key constant in config.properties:", k)
        end
    end

    for line in contents:gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("=") then
            local key, value = line:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
            if key and value then
                if key == "keyUp" then try_set_control("up", value) end
                if key == "keyDown" then try_set_control("down", value) end
                if key == "keyLeft" then try_set_control("left", value) end
                if key == "keyRight" then try_set_control("right", value) end
            end
        end
    end
end

function player.load(screenWidth, screenHeight)
    load_controls_from_properties()
    player.texture = love.graphics.newImage("res/player.png")
    if screenWidth and screenHeight then
        player.x = screenWidth / 2
        player.y = screenHeight / 2
        player.screenWidth = screenWidth
        player.screenHeight = screenHeight
    end
end

function player.update(dt)
    -- Движение
    if love.keyboard.isDown(player.controls.up) then player.y = player.y - player.speed * dt end
    if love.keyboard.isDown(player.controls.down) then player.y = player.y + player.speed * dt end
    if love.keyboard.isDown(player.controls.left) then player.x = player.x - player.speed * dt end
    if love.keyboard.isDown(player.controls.right) then player.x = player.x + player.speed * dt end

    -- Ограничение выхода за границы экрана
    if player.screenWidth and player.screenHeight then
        player.x = math.max(player.radius, math.min(player.screenWidth - player.radius, player.x))
        player.y = math.max(player.radius, math.min(player.screenHeight - player.radius, player.y))
    end

    -- Обновляем таймер неуязвимости
    if player.invuln then
        player.invuln_timer = player.invuln_timer - dt
        if player.invuln_timer <= 0 then
            player.invuln = false
        end
    end

    -- Кулдаун выстрела
    if player.shotCooldown > 0 then
        player.shotCooldown = player.shotCooldown - dt
    end

    -- Двигаем пули игрока
    for i = #player.shots, 1, -1 do
        local s = player.shots[i]
        s.y = s.y - s.speed * dt
        if s.y < -10 then
            table.remove(player.shots, i)
        end
    end
end

function player.draw()
    -- Мигаем, если инвулн
    if player.invuln and math.floor(love.timer.getTime() * 10) % 2 == 0 then
        return
    end

    if player.texture then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(player.texture, player.x - player.radius, player.y - player.radius)
    else
        love.graphics.setColor(1, 1, 1)
        love.graphics.circle("fill", player.x, player.y, player.radius)
    end

    -- Рисуем пули
    love.graphics.setColor(1, 1, 0)
    love.graphics.setBlendMode("add")
    for _, s in ipairs(player.shots) do
        love.graphics.circle("fill", s.x, s.y, 4)
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1)
end

function player.shoot()
    if player.shotCooldown <= 0 then
        table.insert(player.shots, {x = player.x, y = player.y - player.radius, speed = 400})
        player.shotCooldown = 0.2 -- 0.2 сек между выстрелами
    end
end

function player.hit()
    if not player.invuln then
        player.lives = player.lives - 1
        player.invuln = true
        player.invuln_timer = 3 -- 3 сек неуязвимости
        print("[PLAYER] Hit! Lives left: " .. player.lives)
        if player.lives <= 0 then
            print("[PLAYER] No lives left.")
            player.dead = true
        end
    end
end

function player.set_controls_mode(mode)
    if mode == "WASD" then
        player.controls.up = "w"
        player.controls.down = "s"
        player.controls.left = "a"
        player.controls.right = "d"
    elseif mode == "Arrows" then
        player.controls.up = "up"
        player.controls.down = "down"
        player.controls.left = "left"
        player.controls.right = "right"
    end
end

                                                                return player
