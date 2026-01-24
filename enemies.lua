local enemies = {}
local bullets = require("bullets")
local list = {}
local img = nil
local scale = 1

function enemies.setScale(s)
    scale = s
end

function enemies.load()
    list = {}
    if love.filesystem.getInfo("res/images/enemy.png") then
        img = love.graphics.newImage("res/images/enemy.png")
    end
end

function enemies.clear()
    list = {}
end

function enemies.spawn(x, y, props)
    local duration = 5.0
    local hp = 5
    local shootInterval = 0.8
    local bulletCount = 8
    local bulletSpeed = 150
    
    if type(props) == "table" then
        duration = props.duration or 5.0
        hp = props.hp or 5
        shootInterval = props.shootInterval or 0.8
        bulletCount = props.bulletCount or 8
        bulletSpeed = props.bulletSpeed or 150
    elseif type(props) == "number" then
        duration = props
    end

    table.insert(list, {
        x = x,
        y = y,
        visualX = x,
        visualY = -100, -- Появляется за пределами экрана сверху
        state = "entering", -- entering, attacking, leaving
        timer = 0,
        duration = duration,
        hp = hp,
        maxHp = hp,
        shootTimer = 0,
        shootInterval = shootInterval,
        bulletCount = bulletCount,
        bulletSpeed = bulletSpeed
    })
end

function enemies.update(dt, player_shots)
    for i = #list, 1, -1 do
        local e = list[i]
        
        if e.state == "entering" then
            -- Плавное появление (Lerp)
            e.visualY = e.visualY + (e.y - e.visualY) * 2 * dt
            if math.abs(e.visualY - e.y) < 2 then
                e.state = "attacking"
            end
        elseif e.state == "attacking" then
            e.timer = e.timer + dt
            e.shootTimer = e.shootTimer + dt
            
            -- Стрельба
            if e.shootTimer > e.shootInterval then
                e.shootTimer = 0
                bullets.spawn_ring(e.visualX, e.visualY, e.bulletCount, e.bulletSpeed, 5)
            end
            
            if e.timer >= e.duration then
                e.state = "leaving"
            end
        elseif e.state == "leaving" then
            -- Улетает вверх
            e.visualY = e.visualY - 200 * dt
            if e.visualY < -100 then
                table.remove(list, i)
                goto continue
            end
        end
        
        -- Коллизия с пулями игрока
        if player_shots then
            for j = #player_shots, 1, -1 do
                local s = player_shots[j]
                local dx = s.x - e.visualX
                local dy = s.y - e.visualY
                if dx*dx + dy*dy < (1600 * scale * scale) then -- Радиус ~40, масштабируем квадрат радиуса
                    e.hp = e.hp - 1
                    table.remove(player_shots, j)
                    if e.hp <= 0 then
                        table.remove(list, i)
                        goto continue
                    end
                    break
                end
            end
        end
        
        ::continue::
    end
end

function enemies.draw(showHitbox)
    love.graphics.setColor(1, 1, 1, 1)
    for _, e in ipairs(list) do
        if img then
            love.graphics.draw(img, e.visualX, e.visualY, 0, scale, scale, img:getWidth()/2, img:getHeight()/2)
        else
            -- Заглушка, если нет текстуры
            love.graphics.setColor(1, 0.2, 0.2)
            love.graphics.circle("fill", e.visualX, e.visualY, 30)
            love.graphics.setColor(1, 1, 1)
        end
        
        -- Полоска здоровья
        local hpPct = e.hp / e.maxHp
        love.graphics.setColor(1, 0, 0)
        love.graphics.rectangle("fill", e.visualX - 30, e.visualY - 50, 60, 6)
        love.graphics.setColor(0, 1, 0)
        love.graphics.rectangle("fill", e.visualX - 30, e.visualY - 50, 60 * hpPct, 6)
        love.graphics.setColor(1, 1, 1)
        
        -- Хитбокс
        if showHitbox then
            love.graphics.setColor(1, 0, 0, 0.4)
            love.graphics.circle("fill", e.visualX, e.visualY, 40)
            love.graphics.setColor(1, 0, 0, 1)
            love.graphics.circle("line", e.visualX, e.visualY, 40) -- Радиус коллизии
        end
    end
end

return enemies