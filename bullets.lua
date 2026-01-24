local bullets = {
    list = {},
    texture = nil,
    glowTexture = nil,
    showHitbox = false,
    batch = nil,
    glowBatch = nil
}

function bullets.load()
    bullets.list = {}
    if love.filesystem.getInfo("res/images/bullet.png") then
        bullets.texture = love.graphics.newImage("res/images/bullet.png")
    else
        bullets.texture = nil
    end

    -- Генерация текстуры свечения (мягкий градиент)
    local size = 64
    local data = love.image.newImageData(size, size)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local dx = (x - size / 2) / (size / 2)
            local dy = (y - size / 2) / (size / 2)
            local d = math.sqrt(dx * dx + dy * dy)
            local a = math.max(0, 1 - d)
            a = a * a -- Квадратичное затухание для мягкости
            data:setPixel(x, y, 1, 1, 1, a)
        end
    end
    bullets.glowTexture = love.graphics.newImage(data)
    
    -- Инициализация SpriteBatch для оптимизации отрисовки
    if bullets.texture then
        bullets.batch = love.graphics.newSpriteBatch(bullets.texture, 3000, "stream")
    end
    if bullets.glowTexture then
        bullets.glowBatch = love.graphics.newSpriteBatch(bullets.glowTexture, 3000, "stream")
    end
end

function bullets.spawn(x, y, speed, angle, radius)
    table.insert(bullets.list, {
        x = x,
        y = y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        radius = radius or 5
    })
end

-- Универсальная функция для спауна кольца пуль (для врагов и osu-карт)
function bullets.spawn_ring(x, y, count, speed, radius, angle_offset, arc)
    if count <= 0 then return end
    angle_offset = angle_offset or 0
    arc = arc or (math.pi * 2)

    for i = 1, count do
        local angle
        if math.abs(arc - math.pi * 2) < 0.001 then
            angle = angle_offset + ((i - 1) / count) * arc
        else
            -- Если это дуга (spread), распределяем равномерно
            if count > 1 then
                angle = angle_offset + ((i - 1) / (count - 1)) * arc
            else
                angle = angle_offset + arc / 2
            end
        end
        bullets.spawn(x, y, speed, angle, radius)
    end
end

function bullets.explode_circle(obj, config)
    local base_count = math.floor(360 / math.max(10, obj.preempt / 50))
    if obj.custom_count and obj.custom_count > 0 then base_count = obj.custom_count end
    
    local count = math.floor(base_count * config.bullet_multiplier)
    
    local base_speed = math.max(100, 400 - obj.preempt)
    if obj.custom_speed and obj.custom_speed > 0 then base_speed = obj.custom_speed end
    
    -- Применяем масштаб (config.scale) к скорости и размеру
    local scale = config.scale or 1.0
    local speed = base_speed * config.bullet_speed * scale
    local radius = 5 * (config.bullet_size or 1.0) * scale

    -- Параметры угла и дуги (переводим из градусов в радианы)
    local angle_offset = math.rad(obj.angle_offset or 0)
    local arc = math.rad(obj.spread_angle or 360)

    print("[BULLETS] Boom! Spawning " .. count .. " bullets at (" .. math.floor(obj.x) .. ", " .. math.floor(obj.y) .. ")")

    bullets.spawn_ring(obj.x, obj.y, count, speed, radius, angle_offset, arc)
end

function bullets.update(dt)
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()
    local margin = 50

    local write_idx = 1
    for read_idx = 1, #bullets.list do
        local b = bullets.list[read_idx]
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        
        if not (b.x < -margin or b.x > (w + margin) or b.y < -margin or b.y > (h + margin)) then
            if read_idx ~= write_idx then
                bullets.list[write_idx] = b
            end
            write_idx = write_idx + 1
        end
    end
    -- Удаляем "хвост"
    for i = write_idx, #bullets.list do
        bullets.list[i] = nil
    end
end

function bullets.draw()
    -- Очищаем батчи
    if bullets.batch then bullets.batch:clear() end
    if bullets.glowBatch then bullets.glowBatch:clear() end

    -- Объединяем итерации для производительности
    if #bullets.list > 0 then
        local glow_ox, glow_oy, bullet_w, bullet_ox, bullet_oy
        if bullets.glowTexture then
            glow_ox = bullets.glowTexture:getWidth() / 2
            glow_oy = bullets.glowTexture:getHeight() / 2
        end
        if bullets.texture then
            bullet_w = bullets.texture:getWidth()
            bullet_ox = bullet_w / 2
            bullet_oy = bullets.texture:getHeight() / 2
        end

        for _, b in ipairs(bullets.list) do
            if bullets.glowBatch and glow_ox then
                local scale = (b.radius * 3) / glow_ox
                bullets.glowBatch:add(b.x, b.y, 0, scale, scale, glow_ox, glow_oy)
            end
            if bullets.batch and bullet_w then
                local scale = (b.radius * 2) / bullet_w
                bullets.batch:add(b.x, b.y, 0, scale, scale, bullet_ox, bullet_oy)
            end
        end
    end

    -- 1. Слой свечения (Glow)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(0.2, 0.6, 1, 0.8) -- Голубоватое свечение
    if bullets.glowBatch then
        love.graphics.draw(bullets.glowBatch)
    end
    
    -- 2. Основное тело пули
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
    if bullets.batch then
        love.graphics.draw(bullets.batch)
    else
        -- Fallback (если текстуры нет)
        for _, b in ipairs(bullets.list) do
            love.graphics.circle("fill", b.x, b.y, b.radius)
        end
    end

    -- 3. Хитбокс (если включен)
    if bullets.showHitbox then
        love.graphics.setColor(1, 0, 0, 0.8)
        love.graphics.setLineWidth(1)
        for _, b in ipairs(bullets.list) do
            love.graphics.circle("line", b.x, b.y, b.radius)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
end

return bullets
