local bullets = {
    list = {},
    styles = {},
    glowTexture = nil,
    showHitbox = false,
    glowBatch = nil
}

function bullets.load()
    bullets.list = {}
    bullets.styles = {}

    local function registerStyle(name, path, offset)
        if love.filesystem.getInfo(path) then
            local tex = love.graphics.newImage(path)
            bullets.styles[name] = {
                texture = tex,
                batch = love.graphics.newSpriteBatch(tex, 3000, "stream"),
                offset = offset or 0,
                w = tex:getWidth(),
                h = tex:getHeight()
            }
        end
    end

    registerStyle("circle", "res/images/bullet.png", 0)
    registerStyle("arrow_black", "res/images/arrow-black.png", -math.pi/2)
    registerStyle("arrow_red", "res/images/arrow-red.png", -math.pi/2)
    registerStyle("arrow_white", "res/images/arrow-white.png", -math.pi/2)

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
    
    bullets.glowBatch = love.graphics.newSpriteBatch(bullets.glowTexture, 3000, "stream")
end

function bullets.clear()
    bullets.list = {}
end

function bullets.spawn(x, y, speed, angle, radius, style)
    if not style or not bullets.styles[style] then
        style = "circle"
        if not bullets.styles["circle"] then
            for k in pairs(bullets.styles) do style = k break end
        end
    end

    table.insert(bullets.list, {
        x = x,
        y = y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        radius = radius or 5,
        angle = angle,
        style = style
    })
end

-- Универсальная функция для спауна кольца пуль (для врагов и osu-карт)
function bullets.spawn_ring(x, y, count, speed, radius, angle_offset, arc, style)
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
        bullets.spawn(x, y, speed, angle, radius, style)
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

    local style = config.style
    if not style then style = "arrow_red" end

    bullets.spawn_ring(obj.x, obj.y, count, speed, radius, angle_offset, arc, style)
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
    for _, s in pairs(bullets.styles) do
        if s.batch then s.batch:clear() end
    end
    if bullets.glowBatch then bullets.glowBatch:clear() end

    -- Объединяем итерации для производительности
    if #bullets.list > 0 then
        local glow_ox = bullets.glowTexture:getWidth() / 2
        local glow_oy = bullets.glowTexture:getHeight() / 2

        for _, b in ipairs(bullets.list) do
            if bullets.glowBatch and glow_ox then
                local scale = (b.radius * 3) / glow_ox
                bullets.glowBatch:add(b.x, b.y, 0, scale, scale, glow_ox, glow_oy)
            end
            local s = bullets.styles[b.style]
            if s and s.batch then
                local dim = math.max(s.w, s.h)
                local scale = (b.radius * 2.5) / dim
                local r = b.angle + s.offset
                s.batch:add(b.x, b.y, r, scale, scale, s.w / 2, s.h / 2)
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
    for _, s in pairs(bullets.styles) do
        if s.batch then love.graphics.draw(s.batch) end
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
