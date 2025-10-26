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
    shotCooldown = 0   -- задержка между выстрелами
}

function player.load()
player.texture = love.graphics.newImage("res/player.png")
end

function player.update(dt)
-- Движение
if love.keyboard.isDown("up") then player.y = player.y - player.speed * dt end
    if love.keyboard.isDown("down") then player.y = player.y + player.speed * dt end
        if love.keyboard.isDown("left") then player.x = player.x - player.speed * dt end
            if love.keyboard.isDown("right") then player.x = player.x + player.speed * dt end

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
                                                for _, s in ipairs(player.shots) do
                                                    love.graphics.circle("fill", s.x, s.y, 4)
                                                    end
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
                                                            print("Player hit! Lives left:", player.lives)
                                                            if player.lives <= 0 then
                                                                print("GAME OVER")
                                                                player.dead = true
                                                                end
                                                                end
                                                                end

                                                                return player
