local bullets = {
    list = {},
    texture = nil
}

function bullets.load()
bullets.texture = love.graphics.newImage("res/bullet.png")
end

function bullets.spawn(x, y, speed, angle)
table.insert(bullets.list, {
    x = x,
    y = y,
    vx = math.cos(angle) * speed,
             vy = math.sin(angle) * speed,
             radius = 5
})
end

function bullets.explode_circle(obj, config, warningObjects)
local base_count = math.floor(360 / math.max(10, obj.preempt / 50))
local count = math.floor(base_count * config.bullet_multiplier)
local speed = math.max(100, 400 - obj.preempt) * config.bullet_speed

for i = 1, count do
    local angle = (i / count) * math.pi * 2
    bullets.spawn(obj.x, obj.y, speed, angle)
    end

    -- убираем предупреждающий круг
    for i = #warningObjects, 1, -1 do
        local w = warningObjects[i]
        if math.abs(w.x - obj.x) < 1 and math.abs(w.y - obj.y) < 1 then
            table.remove(warningObjects, i)
            break
            end
            end
            end

            function bullets.update(dt)
            for _, b in ipairs(bullets.list) do
                b.x = b.x + b.vx * dt
                b.y = b.y + b.vy * dt
                end
                end

                function bullets.draw()
                love.graphics.setColor(1, 1, 1)
                for _, b in ipairs(bullets.list) do
                    if bullets.texture then
                        love.graphics.draw(bullets.texture, b.x - b.radius, b.y - b.radius)
                        else
                            love.graphics.circle("fill", b.x, b.y, b.radius)
                            end
                            end
                            end

                            return bullets
