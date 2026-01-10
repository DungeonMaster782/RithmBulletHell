local player = {
    x = 400,
    y = 300,
    radius = 16,
    hitboxRadius = 5,
    grazeRadius = 15, -- Радиус грейза (2x хитбокса)
    score = 0,
    showHitbox = false,
    speed = 200,
    texture = nil,
    visualX = 400,
    visualY = 300,
    focusTexture = nil,
    focusTexture2 = nil,
    focusRotation = 0,
    focusRotation2 = 0,
    focusAnimTime = 0,
    focusActive = false,
    hitboxTexture = nil,
    lives = 3,
    invuln = false,
    invuln_timer = 0,
    invulnDuration = 3,
    dead = false,
    shots = {},        -- список пуль
    shotCooldown = 0,   -- задержка между выстрелами
    controls = {
        up = "up",
        down = "down",
        left = "left",
        right = "right"
    },
    -- Переменные для деша
    dashCharges = 3,
    maxDashCharges = 3,
    dashRechargeTimer = 0,
    dashRechargeTime = 3.0,
    isDashing = false,
    dashTimer = 0,
    dashDuration = 0.5
}

function player.load(screenWidth, screenHeight)
    player.texture = love.graphics.newImage("res/images/player.png")
    if love.filesystem.getInfo("res/images/focus.png") then
        player.focusTexture = love.graphics.newImage("res/images/focus.png")
    end
    if love.filesystem.getInfo("res/images/focus2.png") then
        player.focusTexture2 = love.graphics.newImage("res/images/focus2.png")
    elseif player.focusTexture then
        player.focusTexture2 = player.focusTexture
    end
    if love.filesystem.getInfo("res/images/player_hitbox.png") then
        player.hitboxTexture = love.graphics.newImage("res/images/player_hitbox.png")
        player.hitboxTexture:setFilter("nearest", "nearest") -- Сохраняем четкость пикселей
    end
    if screenWidth and screenHeight then
        player.x = screenWidth / 2
        player.y = screenHeight / 2
        player.visualX = player.x
        player.visualY = player.y
        player.screenWidth = screenWidth
        player.screenHeight = screenHeight
    end
    -- Сброс состояния деша при загрузке
    player.dashCharges = player.maxDashCharges
    player.dashRechargeTimer = 0
    player.isDashing = false
    player.score = 0
    player.grazeRadius = player.hitboxRadius * 2

    player.dead = false
    player.invuln = false
    player.invuln_timer = 0
    player.shots = {}
end

function player.update(dt)
    -- Регенерация зарядов деша
    if player.dashCharges < player.maxDashCharges then
        player.dashRechargeTimer = player.dashRechargeTimer + dt
        if player.dashRechargeTimer >= player.dashRechargeTime then
            player.dashCharges = player.dashCharges + 1
            player.dashRechargeTimer = 0
        end
    end

    local shiftDown = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")

    -- Логика анимации фокуса
    if shiftDown then
        if not player.focusActive then
            player.focusActive = true
            player.focusAnimTime = 0
            player.focusRotation = 0
            player.focusRotation2 = 0
        end
        player.focusAnimTime = player.focusAnimTime + dt
        
        -- Начинаем крутить только после завершения анимации появления (0.2 сек)
        if player.focusAnimTime > 0.2 then
            player.focusRotation = player.focusRotation - dt * 4
            player.focusRotation2 = player.focusRotation2 + dt * 4
        end
    else
        player.focusActive = false
        player.focusAnimTime = 0
    end

    if player.isDashing then
        -- Логика движения во время деша (фиксированное направление)
        player.dashTimer = player.dashTimer - dt
        player.x = player.x + player.dashVx * dt
        player.y = player.y + player.dashVy * dt
        if player.dashTimer <= 0 then
            player.isDashing = false
        end
    else
        -- Обычное движение
        local currentSpeed = player.speed
        if shiftDown then
            currentSpeed = currentSpeed * 0.5
        end

        if love.keyboard.isDown(player.controls.up) then player.y = player.y - currentSpeed * dt end
        if love.keyboard.isDown(player.controls.down) then player.y = player.y + currentSpeed * dt end
        if love.keyboard.isDown(player.controls.left) then player.x = player.x - currentSpeed * dt end
        if love.keyboard.isDown(player.controls.right) then player.x = player.x + currentSpeed * dt end
    end
    
    -- Стрельба (зажатие)
    if love.keyboard.isDown("return") or love.keyboard.isDown("z") then
        player.shoot()
    end

    -- Ограничение выхода за границы экрана
    if player.screenWidth and player.screenHeight then
        player.x = math.max(player.radius, math.min(player.screenWidth - player.radius, player.x))
        player.y = math.max(player.radius, math.min(player.screenHeight - player.radius, player.y))
    end

    -- Плавное движение текстуры (Lerp) для визуального эффекта инерции
    player.visualX = player.visualX + (player.x - player.visualX) * 30 * dt
    player.visualY = player.visualY + (player.y - player.visualY) * 30 * dt

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
        local w = player.texture:getWidth()
        local h = player.texture:getHeight()
        love.graphics.draw(player.texture, player.visualX, player.visualY, 0, 1, 1, w / 2, h / 2)
    else
        love.graphics.setColor(1, 1, 1)
        love.graphics.circle("fill", player.visualX, player.visualY, player.radius)
    end

    -- Рисуем текстуру фокуса (если зажат Shift)
    if player.focusActive and player.focusTexture then
        -- Вычисляем масштаб: от 1.5 до 1.0 за 0.2 секунды
        local scale = 1
        if player.focusAnimTime < 0.2 then
            scale = 1.5 - (0.5 * (player.focusAnimTime / 0.2))
        end

        local w = player.focusTexture:getWidth()
        local h = player.focusTexture:getHeight()
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.draw(player.focusTexture, player.visualX, player.visualY, player.focusRotation, scale, scale, w / 2, h / 2)
        
        if player.focusTexture2 then
            local w2 = player.focusTexture2:getWidth()
            local h2 = player.focusTexture2:getHeight()
            love.graphics.draw(player.focusTexture2, player.visualX, player.visualY, player.focusRotation2, scale, scale, w2 / 2, h2 / 2)
        end
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

function player.drawHitbox()
    -- Мигаем, если инвулн (так же как и сам игрок)
    if player.invuln and math.floor(love.timer.getTime() * 10) % 2 == 0 then
        return
    end

    if (player.focusActive or player.showHitbox) and player.hitboxTexture then
        love.graphics.setColor(1, 1, 1, 1)
        local w = player.hitboxTexture:getWidth()
        local h = player.hitboxTexture:getHeight()
        -- Масштабируем текстуру так, чтобы она соответствовала размеру хитбокса (диаметр = 2 * radius)
        -- Множитель 8 увеличивает визуальный размер текстуры, так как она казалась слишком маленькой
        local scale = (player.hitboxRadius * 26) / w
        love.graphics.draw(player.hitboxTexture, player.x, player.y, -player.focusRotation, scale, scale, w / 2, h / 2)
    elseif player.showHitbox then
        love.graphics.setColor(1, 0, 0, 1)
        local r = player.hitboxRadius
        love.graphics.polygon("fill", player.x, player.y - r, player.x + r, player.y, player.x, player.y + r, player.x - r, player.y)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Рисуем красную обводку реального радиуса хитбокса
    if player.showHitbox then
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.setLineWidth(1)
        love.graphics.circle("line", player.x, player.y, player.hitboxRadius)
        -- Хитбокс грейза (синий)
        love.graphics.setColor(0, 1, 1, 0.8)
        love.graphics.circle("line", player.x, player.y, player.grazeRadius)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function player.shoot()
    if player.shotCooldown <= 0 then
        table.insert(player.shots, {x = player.x, y = player.y - player.radius, speed = 400})
        player.shotCooldown = 0.08 -- Быстрая стрельба
    end
end

function player.hit()
    if player.isDashing then return end -- Неуязвимость во время деша
    if not player.invuln then
        player.lives = player.lives - 1
        player.invuln = true
        player.invuln_timer = player.invulnDuration -- сек неуязвимости
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

function player.attemptDash()
    if player.dashCharges > 0 and not player.isDashing then
        local dx, dy = 0, 0
        if love.keyboard.isDown(player.controls.up) then dy = dy - 1 end
        if love.keyboard.isDown(player.controls.down) then dy = dy + 1 end
        if love.keyboard.isDown(player.controls.left) then dx = dx - 1 end
        if love.keyboard.isDown(player.controls.right) then dx = dx + 1 end

        -- Деш работает только если нажата кнопка направления
        if dx ~= 0 or dy ~= 0 then
            local len = math.sqrt(dx*dx + dy*dy)
            local dashSpeed = player.speed * 4 -- Скорость деша (в 4 раза быстрее обычного)
            
            player.dashVx = (dx / len) * dashSpeed
            player.dashVy = (dy / len) * dashSpeed
            player.isDashing = true
            player.dashTimer = player.dashDuration
            player.dashCharges = player.dashCharges - 1
        end
    end
end

function player.graze()
    player.score = player.score + 100
end

                                                                return player
