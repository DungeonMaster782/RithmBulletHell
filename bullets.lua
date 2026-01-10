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
function bullets.spawn_ring(x, y, count, speed, radius)
    if count <= 0 then return end
    for i = 1, count do
        local angle = (i / count) * math.pi * 2
        bullets.spawn(x, y, speed, angle, radius)
    end
end

function bullets.explode_circle(obj, config)
    local base_count = math.floor(360 / math.max(10, obj.preempt / 50))
    if obj.custom_count and obj.custom_count > 0 then base_count = obj.custom_count end
    
    local count = math.floor(base_count * config.bullet_multiplier)
    
    local base_speed = math.max(100, 400 - obj.preempt)
    if obj.custom_speed and obj.custom_speed > 0 then base_speed = obj.custom_speed end
    
    local speed = base_speed * config.bullet_speed
    local radius = 5 * (config.bullet_size or 1.0)

    print("[BULLETS] Boom! Spawning " .. count .. " bullets at (" .. math.floor(obj.x) .. ", " .. math.floor(obj.y) .. ")")

    bullets.spawn_ring(obj.x, obj.y, count, speed, radius)
end

function bullets.update(dt)
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()
    local margin = 50

    for i = #bullets.list, 1, -1 do
        local b = bullets.list[i]
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        if b.x < -margin or b.x > (w + margin) or b.y < -margin or b.y > (h + margin) then
            table.remove(bullets.list, i)
        end
    end
end

function bullets.draw()
    -- Очищаем батчи
    if bullets.batch then bullets.batch:clear() end
    if bullets.glowBatch then bullets.glowBatch:clear() end

    -- 1. Слой свечения (Glow)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(0.2, 0.6, 1, 0.8) -- Голубоватое свечение
    
    if bullets.glowTexture and bullets.glowBatch then
        local gw = bullets.glowTexture:getWidth()
        local gh = bullets.glowTexture:getHeight()
        local ox, oy = gw / 2, gh / 2
        
        for _, b in ipairs(bullets.list) do
            local scale = (b.radius * 3) / ox
            bullets.glowBatch:add(b.x, b.y, 0, scale, scale, ox, oy)
        end
        love.graphics.draw(bullets.glowBatch)
    end
    
    -- 2. Основное тело пули
    if bullets.texture and bullets.batch then
        local w = bullets.texture:getWidth()
        local h = bullets.texture:getHeight()
        local ox, oy = w / 2, h / 2
        
        for _, b in ipairs(bullets.list) do
            local scale = (b.radius * 2) / w
            bullets.batch:add(b.x, b.y, 0, scale, scale, ox, oy)
        end
    end

    -- Отрисовка основного слоя
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
