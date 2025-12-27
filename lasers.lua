local lasers = {}

-- Функция проверки расстояния от точки до отрезка (для коллизии)
function lasers.getDistance(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0 then
        return math.sqrt((px - x1)^2 + (py - y1)^2)
    end
    local t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    t = math.max(0, math.min(1, t))
    local cx, cy = x1 + t * dx, y1 + t * dy
    return math.sqrt((px - cx)^2 + (py - cy)^2)
end

function lasers.draw(obj, x1, y1, x2, y2, currentTime)
    if not obj.shown or obj.exploded then return end

    if obj.active then
        -- === АКТИВНЫЙ ЛАЗЕР (ВЫСТРЕЛ) ===
        love.graphics.setBlendMode("add")
        
        -- Внешнее свечение (Красное/Оранжевое)
        love.graphics.setColor(1, 0.1, 0.1, 0.6)
        -- Пульсация ширины
        local pulse = math.sin(currentTime / 20) * 4
        love.graphics.setLineWidth(28 + pulse)
        love.graphics.line(x1, y1, x2, y2)
        
        -- Яркое белое ядро
        love.graphics.setColor(1, 0.9, 0.8, 1)
        love.graphics.setLineWidth(8)
        love.graphics.line(x1, y1, x2, y2)
        
        -- Свечение на концах
        love.graphics.setColor(1, 0.4, 0.2, 0.8)
        love.graphics.circle("fill", x1, y1, 12 + pulse/2)
        love.graphics.circle("fill", x2, y2, 12 + pulse/2)
        
    else
        -- === ПРЕДУПРЕЖДЕНИЕ (ПОДГОТОВКА) ===
        local progress = 1 - ((obj.time - currentTime) / obj.preempt)
        if progress < 0 then progress = 0 end
        
        love.graphics.setBlendMode("add")
        -- Тонкая линия, которая становится ярче и шире
        love.graphics.setColor(1, 0, 0, 0.2 + 0.6 * progress)
        local w = 2 + 15 * progress
        love.graphics.setLineWidth(w) 
        love.graphics.line(x1, y1, x2, y2)
        love.graphics.circle("fill", x1, y1, w / 2)
        love.graphics.circle("fill", x2, y2, w / 2)
    end
    
    love.graphics.setBlendMode("alpha")
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return lasers