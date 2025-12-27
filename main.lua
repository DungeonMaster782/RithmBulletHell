local console = require("console")
local maps_dir = "maps"
local maps = {}
local selected_index = 1
local mode = "main_menu" -- main_menu, osu_menu, difficulties, settings, gameplay
local selected_song = nil
local selected_difficulty = nil
local font

game = nil -- Глобальная переменная, чтобы консоль ее видела

-- Фоны
local main_menu_background_path = "res/images/menu.png"
local main_menu_background = nil

local osu_menu_background_path = "res/images/osu_menu_bg.png"
local osu_menu_background = nil

local backgrounds = {}

local main_menu_items = {
    "osu-mode",
    "Settings",
    "Exit"
}

-- Настройки
settings = { -- Глобальная переменная, чтобы консоль ее видела
    music_volume = 0.5,
    resolution_index = 1,
    resolutions = {
        {1920, 1080},
        {1600, 900},
        {1280, 720}
    },
    fullscreen_mode_index = 1,
    fullscreen_modes = {"fullscreen", "windowed", "borderless"},
    lives = 3,
    controls_index = 2, -- По умолчанию WASD (так как в config.properties было WASD)
    controls_modes = {"Arrows", "WASD"},
    bullet_multiplier = 0.5,
    bullet_speed = 1.0,
    bullet_size = 1.0,
    player_speed = 1.0,
    show_fps = false,
    vsync = true,
    max_fps = 0, -- 0 = Unlimited
    max_fps_options = {30, 60, 120, 144, 240, 0},
    max_fps_index = 6
}
local temp_settings = {}
local settings_options = {"Music Volume", "Resolution", "Window Mode", "Lives", "Controls", "Bullet Multiplier", "Bullet Speed", "Bullet Size", "Player Speed", "Show FPS", "VSync", "Max FPS", "Apply", "Back"}
local settings_selected_index = 1

local menu_music = nil
local menu_music_path = "res/sounds/menu_music.mp3" -- путь к mp3

-- Функция для применения настроек видео
local function apply_video_settings()
    local r = settings.resolutions[settings.resolution_index]
    local fs_mode = settings.fullscreen_modes[settings.fullscreen_mode_index]
    
    local flags = {
        resizable = true,
        vsync = settings.vsync
    }

    if fs_mode == "fullscreen" then
        flags.fullscreen = true
        flags.fullscreentype = "exclusive"
    elseif fs_mode == "borderless" then
        flags.fullscreen = true
        flags.fullscreentype = "desktop"
    else
        flags.fullscreen = false
        flags.borderless = false
    end

    print("[VIDEO] Applying settings: " .. r[1] .. "x" .. r[2] .. " (" .. fs_mode .. ")")
    love.window.setMode(r[1], r[2], flags)
end

-- Загрузка конфига игры (для bullet settings)
local function load_game_config()
    if not love.filesystem.getInfo("config.txt") then return end
    local contents = love.filesystem.read("config.txt")
    print("[CONFIG] Loading config.txt...")
    for line in contents:gmatch("[^\r\n]+") do
        local key, value = line:match("^([%w_]+)%s*=%s*([%w_%.]+)")
        if key and value then
            local n = tonumber(value)
            if key == "bullet_multiplier" then settings.bullet_multiplier = n end
            if key == "bullet_speed" then settings.bullet_speed = n end
            if key == "bullet_size" then settings.bullet_size = n end
            if key == "player_speed" then settings.player_speed = n end
            if key == "music_volume" then settings.music_volume = n end
            if key == "resolution_index" then settings.resolution_index = n end
            if key == "fullscreen_mode_index" then settings.fullscreen_mode_index = n end
            if key == "lives" then settings.lives = n end
            if key == "controls_index" then settings.controls_index = n end
            if key == "show_fps" then settings.show_fps = (value == "true") end
            if key == "vsync" then settings.vsync = (value == "true") end
            if key == "max_fps" then 
                settings.max_fps = n 
                -- Восстанавливаем индекс для меню
                for i, v in ipairs(settings.max_fps_options) do
                    if v == n then settings.max_fps_index = i break end
                end
            end
        end
    end
end

-- Сохранение конфига игры
local function save_game_config()
    print("[CONFIG] Saving config.txt...")
    local content = ""
    content = content .. "music_volume=" .. string.format("%.2f", settings.music_volume) .. "\n"
    content = content .. "resolution_index=" .. settings.resolution_index .. "\n"
    content = content .. "fullscreen_mode_index=" .. settings.fullscreen_mode_index .. "\n"
    content = content .. "lives=" .. settings.lives .. "\n"
    content = content .. "controls_index=" .. settings.controls_index .. "\n"
    content = content .. "bullet_multiplier=" .. string.format("%.1f", settings.bullet_multiplier) .. "\n"
    content = content .. "bullet_speed=" .. string.format("%.1f", settings.bullet_speed) .. "\n"
    content = content .. "bullet_size=" .. string.format("%.1f", settings.bullet_size) .. "\n"
    content = content .. "player_speed=" .. string.format("%.1f", settings.player_speed) .. "\n"
    content = content .. "show_fps=" .. tostring(settings.show_fps) .. "\n"
    content = content .. "vsync=" .. tostring(settings.vsync) .. "\n"
    content = content .. "max_fps=" .. settings.max_fps .. "\n"
    love.filesystem.write("config.txt", content)
end

-- Функции
function love.load()
console.load()
print("[MAIN] Game starting...")
font = love.graphics.newFont(18)
love.graphics.setFont(font)

-- Сначала загружаем конфиг, чтобы применить настройки (громкость, разрешение)
load_game_config()

if love.filesystem.getInfo(main_menu_background_path) then
    main_menu_background = love.graphics.newImage(main_menu_background_path)
    else
        print("Warning: main menu background not found at " .. main_menu_background_path)
        end

        if love.filesystem.getInfo(osu_menu_background_path) then
            osu_menu_background = love.graphics.newImage(osu_menu_background_path)
            else
                print("Warning: osu menu background not found at " .. osu_menu_background_path)
                end

                scan_maps()

                if love.filesystem.getInfo(menu_music_path) then
                    menu_music = love.audio.newSource(menu_music_path, "stream")
                    menu_music:setLooping(true)
                    menu_music:setVolume(settings.music_volume)
                    love.audio.play(menu_music)
                    end
                    -- Применяем начальные настройки видео
                    apply_video_settings()
                    end

                    function scan_maps()
                    maps = {}
                    backgrounds = {}
                    print("[MAPS] Scanning maps directory...")

                    if love.filesystem.getInfo(maps_dir) then
                        local folders = love.filesystem.getDirectoryItems(maps_dir)
                        for _, folder in ipairs(folders) do
                            print("[MAPS] Found folder: " .. folder)
                            local folder_path = maps_dir .. "/" .. folder
                            local info = love.filesystem.getInfo(folder_path)
                            if info and info.type == "directory" then
                                local files = love.filesystem.getDirectoryItems(folder_path)
                                maps[folder] = {}
                                for _, file in ipairs(files) do
                                    if file:match("%.osu$") then
                                        table.insert(maps[folder], file)
                                        print("[MAPS]   Found difficulty: " .. file)
                                        end
                                        end
                                        for _, file in ipairs(files) do
                                            if file:match("%.png$") or file:match("%.jpg$") or file:match("%.jpeg$") then
                                                local bg_path = folder_path .. "/" .. file
                                                local success, err = pcall(function()
                                                backgrounds[folder] = love.graphics.newImage(bg_path)
                                                end)
                                                if not success then
                                                    print("Failed to load background " .. bg_path .. ": " .. err)
                                                    end
                                                    break
                                                    end
                                                    end
                                                    end
                                                    end
                                                    else
                                                        print("Warning: maps directory not found: " .. maps_dir)
                                                        end
                                                        end

                                                        local function draw_text_with_outline(text, x, y, color)
                                                        local outline_color = {0, 0, 0, 1}
                                                        local text_color = color or {1, 1, 1, 1}

                                                        love.graphics.setColor(outline_color)
                                                        for ox = -1, 1 do
                                                            for oy = -1, 1 do
                                                                if not (ox == 0 and oy == 0) then
                                                                    love.graphics.print(text, x + ox, y + oy)
                                                                    end
                                                                    end
                                                                    end

                                                                    love.graphics.setColor(text_color)
                                                                    love.graphics.print(text, x, y)
                                                                    love.graphics.setColor(1, 1, 1, 1)
                                                                    end

                                                                    function get_song_list()
                                                                    local keys = {}
                                                                    for k, _ in pairs(maps) do
                                                                        table.insert(keys, k)
                                                                        end
                                                                        table.sort(keys)
                                                                        return keys
                                                                        end

                                                                        function draw_settings_menu()
                                                                        draw_text_with_outline("Settings", 50, 50)
                                                                        for i, option in ipairs(settings_options) do
                                                                            local prefix = (i == settings_selected_index) and "> " or "  "
                                                                            local item_color = (i == settings_selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                                                                            local value = ""
                                                                            
                                                                            if option == "Music Volume" then
                                                                                draw_text_with_outline(prefix .. option, 70, 80 + i * 30, item_color)
                                                                                -- Рисуем полоску громкости
                                                                                local bar_x = 250
                                                                                local bar_w = 200
                                                                                local bar_h = 20
                                                                                love.graphics.setColor(item_color)
                                                                                love.graphics.rectangle("line", bar_x, 80 + i * 30 + 2, bar_w, bar_h)
                                                                                love.graphics.rectangle("fill", bar_x, 80 + i * 30 + 2, bar_w * temp_settings.music_volume, bar_h)
                                                                                draw_text_with_outline(math.floor(temp_settings.music_volume * 100) .. "%", bar_x + bar_w + 10, 80 + i * 30, item_color)
                                                                                value = "" -- Уже отрисовали
                                                                                elseif option == "Resolution" then
                local r = settings.resolutions[temp_settings.resolution_index]
                                                                                    value = r[1].."x"..r[2]
                                                                                    elseif option == "Window Mode" then
                value = settings.fullscreen_modes[temp_settings.fullscreen_mode_index]
                                                                                        elseif option == "Lives" then
                value = temp_settings.lives
            elseif option == "Controls" then
                value = settings.controls_modes[temp_settings.controls_index]
            elseif option == "Bullet Multiplier" then
                value = string.format("%.1f", temp_settings.bullet_multiplier)
            elseif option == "Bullet Speed" then
                value = string.format("%.1f", temp_settings.bullet_speed)
            elseif option == "Bullet Size" then
                value = string.format("%.1f", temp_settings.bullet_size)
            elseif option == "Player Speed" then
                value = string.format("%.1f", temp_settings.player_speed)
            elseif option == "Show FPS" then
                value = temp_settings.show_fps and "On" or "Off"
            elseif option == "VSync" then
                value = temp_settings.vsync and "On" or "Off"
            elseif option == "Max FPS" then
                value = (temp_settings.max_fps == 0) and "Unlimited" or temp_settings.max_fps
                                                                                            end
            if value ~= "" then
                draw_text_with_outline(prefix .. option .. ": " .. value, 70, 80 + i * 30, item_color)
            elseif option ~= "Music Volume" then -- Music Volume уже отрисован выше
                draw_text_with_outline(prefix .. option, 70, 80 + i * 30, item_color)
            end
                                                                                            end
                                                                                            end

                                                                                            -- Функция для обработки клавиш в меню настроек
                                                                                            function handle_settings_key(key)
                                                                                            if key == "up" then
        settings_selected_index = math.max(1, settings_selected_index - 1)
                                                                                                elseif key == "down" then
        settings_selected_index = math.min(#settings_options, settings_selected_index + 1)
                                                                                                    elseif key == "left" then
                                                                                                        if settings_options[settings_selected_index] == "Music Volume" then
            temp_settings.music_volume = math.max(0, temp_settings.music_volume - 0.05)
            settings.music_volume = temp_settings.music_volume
            if menu_music then menu_music:setVolume(settings.music_volume) end
                                                                                                            elseif settings_options[settings_selected_index] == "Resolution" then
            temp_settings.resolution_index = math.max(1, temp_settings.resolution_index - 1)
                                                                                                                elseif settings_options[settings_selected_index] == "Window Mode" then
            temp_settings.fullscreen_mode_index = math.max(1, temp_settings.fullscreen_mode_index - 1)
                                                                                                                    elseif settings_options[settings_selected_index] == "Lives" then
            temp_settings.lives = math.max(1, temp_settings.lives - 1)
        elseif settings_options[settings_selected_index] == "Controls" then
            temp_settings.controls_index = math.max(1, temp_settings.controls_index - 1)
        elseif settings_options[settings_selected_index] == "Bullet Multiplier" then
            temp_settings.bullet_multiplier = math.max(0.1, temp_settings.bullet_multiplier - 0.1)
        elseif settings_options[settings_selected_index] == "Bullet Speed" then
            temp_settings.bullet_speed = math.max(0.1, temp_settings.bullet_speed - 0.1)
        elseif settings_options[settings_selected_index] == "Bullet Size" then
            temp_settings.bullet_size = math.max(0.1, temp_settings.bullet_size - 0.1)
        elseif settings_options[settings_selected_index] == "Player Speed" then
            temp_settings.player_speed = math.max(0.1, temp_settings.player_speed - 0.1)
        elseif settings_options[settings_selected_index] == "Show FPS" then
            temp_settings.show_fps = not temp_settings.show_fps
        elseif settings_options[settings_selected_index] == "VSync" then
            temp_settings.vsync = not temp_settings.vsync
        elseif settings_options[settings_selected_index] == "Max FPS" then
            temp_settings.max_fps_index = math.max(1, temp_settings.max_fps_index - 1)
            temp_settings.max_fps = settings.max_fps_options[temp_settings.max_fps_index]
                                                                                                                        end
                                                                                                                        elseif key == "right" then
                                                                                                                            if settings_options[settings_selected_index] == "Music Volume" then
            temp_settings.music_volume = math.min(1, temp_settings.music_volume + 0.05)
            settings.music_volume = temp_settings.music_volume
            if menu_music then menu_music:setVolume(settings.music_volume) end
                                                                                                                                elseif settings_options[settings_selected_index] == "Resolution" then
            temp_settings.resolution_index = math.min(#settings.resolutions, temp_settings.resolution_index + 1)
                                                                                                                                    elseif settings_options[settings_selected_index] == "Window Mode" then
            temp_settings.fullscreen_mode_index = math.min(#settings.fullscreen_modes, temp_settings.fullscreen_mode_index + 1)
                                                                                                                                        elseif settings_options[settings_selected_index] == "Lives" then
            temp_settings.lives = math.min(10, temp_settings.lives + 1)
        elseif settings_options[settings_selected_index] == "Controls" then
            temp_settings.controls_index = math.min(#settings.controls_modes, temp_settings.controls_index + 1)
        elseif settings_options[settings_selected_index] == "Bullet Multiplier" then
            temp_settings.bullet_multiplier = temp_settings.bullet_multiplier + 0.1
        elseif settings_options[settings_selected_index] == "Bullet Speed" then
            temp_settings.bullet_speed = temp_settings.bullet_speed + 0.1
        elseif settings_options[settings_selected_index] == "Bullet Size" then
            temp_settings.bullet_size = temp_settings.bullet_size + 0.1
        elseif settings_options[settings_selected_index] == "Player Speed" then
            temp_settings.player_speed = temp_settings.player_speed + 0.1
        elseif settings_options[settings_selected_index] == "Show FPS" then
            temp_settings.show_fps = not temp_settings.show_fps
        elseif settings_options[settings_selected_index] == "VSync" then
            temp_settings.vsync = not temp_settings.vsync
        elseif settings_options[settings_selected_index] == "Max FPS" then
            temp_settings.max_fps_index = math.min(#settings.max_fps_options, temp_settings.max_fps_index + 1)
            temp_settings.max_fps = settings.max_fps_options[temp_settings.max_fps_index]
                                                                                                                                            end
                                                                                                                                            elseif key == "return" then
        if settings_options[settings_selected_index] == "Apply" then
            settings.music_volume = temp_settings.music_volume
            settings.resolution_index = temp_settings.resolution_index
            settings.fullscreen_mode_index = temp_settings.fullscreen_mode_index
            settings.lives = temp_settings.lives
            settings.controls_index = temp_settings.controls_index
            settings.bullet_multiplier = temp_settings.bullet_multiplier
            settings.bullet_speed = temp_settings.bullet_speed
            settings.bullet_size = temp_settings.bullet_size
            settings.player_speed = temp_settings.player_speed
            settings.show_fps = temp_settings.show_fps
            settings.vsync = temp_settings.vsync
            settings.max_fps = temp_settings.max_fps
            settings.max_fps_index = temp_settings.max_fps_index
                                                                                                                                                    apply_video_settings() -- ПРИМЕНЯЕМ НАСТРОЙКИ
            save_game_config() -- СОХРАНЯЕМ В ФАЙЛ
            if menu_music then menu_music:setVolume(settings.music_volume) end
        elseif settings_options[settings_selected_index] == "Back" then
            save_game_config() -- Сохраняем настройки (например, громкость, которая применяется сразу)
            mode = "main_menu"
        end
                                                                                                                                                    elseif key == "escape" then
                                                                                                                                                        mode = "main_menu"
                                                                                                                                                        end
                                                                                                                                                            end

                                                                                                                                                            function love.draw()
                                                                                                                                                            if mode == "main_menu" then
                                                                                                                                                                if main_menu_background then
                                                                                                                                                                    love.graphics.draw(main_menu_background, 0, 0, 0,
                                                                                                                                                                                       love.graphics.getWidth() / main_menu_background:getWidth(),
                                                                                                                                                                                       love.graphics.getHeight() / main_menu_background:getHeight())
                                                                                                                                                                    end

                                                                                                                                                                    love.graphics.setColor(0, 0, 0, 0.5)
                                                                                                                                                                    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                                                                                                                                                                    love.graphics.setColor(1, 1, 1, 1)

                                                                                                                                                                    draw_text_with_outline("Main Menu", 50, 50)
                                                                                                                                                                    for i, item in ipairs(main_menu_items) do
                                                                                                                                                                        local prefix = (i == selected_index) and "> " or "  "
                                                                                                                                                                        local color = (i == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                                                                                                                                                                        draw_text_with_outline(prefix .. item, 70, 80 + i * 30, color)
                                                                                                                                                                        end

                                                                                                                                                                        elseif mode == "settings" then
                                                                                                                                                                            if main_menu_background then
                                                                                                                                                                                love.graphics.draw(main_menu_background, 0, 0, 0,
                                                                                                                                                                                                   love.graphics.getWidth() / main_menu_background:getWidth(),
                                                                                                                                                                                                   love.graphics.getHeight() / main_menu_background:getHeight())
                                                                                                                                                                                love.graphics.setColor(0, 0, 0, 0.5)
                                                                                                                                                                                love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                                                                                                                                                                                love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                end
                                                                                                                                                                                draw_settings_menu()

                                                                                                                                                                                elseif mode == "osu_menu" then
                                                                                                                                                                                    local keys = get_song_list()
                                                                                                                                                                                    if #keys == 0 then
                                                                                                                                                                                        draw_text_with_outline("No maps found!", 50, 50)
                                                                                                                                                                                        return
                                                                                                                                                                                        end

                                                                                                                                                                                        if selected_index > #keys then selected_index = #keys end
                                                                                                                                                                                            if selected_index < 1 then selected_index = 1 end

                                                                                                                                                                                                local current_folder = keys[selected_index]
                                                                                                                                                                                                local bg = backgrounds[current_folder] or osu_menu_background

                                                                                                                                                                                                if bg then
                                                                                                                                                                                                    love.graphics.draw(bg, 0, 0, 0,
                                                                                                                                                                                                                       love.graphics.getWidth() / bg:getWidth(),
                                                                                                                                                                                                                       love.graphics.getHeight() / bg:getHeight())
                                                                                                                                                                                                    love.graphics.setColor(0, 0, 0, 0.5)
                                                                                                                                                                                                    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                                                                                                                                                                                                    love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                                    end

                                                                                                                                                                                                    draw_text_with_outline("Select a song:", 50, 50)
                                                                                                                                                                                                    for i, folder in ipairs(keys) do
                                                                                                                                                                                                        local prefix = (i == selected_index) and "> " or "  "
                                                                                                                                                                                                        local color = (i == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                                                                                                                                                                                                        draw_text_with_outline(prefix .. folder, 70, 80 + i * 30, color)
                                                                                                                                                                                                        end

                                                                                                                                                                                                        elseif mode == "difficulties" and selected_song then
                                                                                                                                                                                                            local bg = backgrounds[selected_song]
                                                                                                                                                                                                            if bg then
                                                                                                                                                                                                                love.graphics.draw(bg, 0, 0, 0,
                                                                                                                                                                                                                                   love.graphics.getWidth() / bg:getWidth(),
                                                                                                                                                                                                                                   love.graphics.getHeight() / bg:getHeight())
                                                                                                                                                                                                                love.graphics.setColor(0, 0, 0, 0.5)
                                                                                                                                                                                                                love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                                                                                                                                                                                                                love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                                                end

                                                                                                                                                                                                                draw_text_with_outline("Select difficulty for: " .. selected_song, 50, 50)
                                                                                                                                                                                                                local difficulties = maps[selected_song] or {}
                                                                                                                                                                                                                for i, diff in ipairs(difficulties) do
                                                                                                                                                                                                                    local prefix = (i == selected_index) and "> " or "  "
                                                                                                                                                                                                                    local color = (i == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                                                                                                                                                                                                                    draw_text_with_outline(prefix .. diff, 70, 80 + i * 30, color)
                                                                                                                                                                                                                    end

                                                                                                                                                                                                                    elseif mode == "gameplay" then
                                                                                                                                                                                                                        if game and game.draw then
                                                                                                                                                                                                                            game.draw()
                                                                                                                                                                                                                            else
                                                                                                                                                                                                                                draw_text_with_outline("Game started: " .. (selected_song or "") .. " - " .. (selected_difficulty or ""), 50, 50)
                                                                                                                                                                                                                                draw_text_with_outline("Press ESC to return to menu", 50, 80)
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                -- Отрисовка FPS (теперь внутри love.draw)
                                                                                                                                                                                                                                if settings.show_fps then
                                                                                                                                                                                                                                    love.graphics.setColor(0, 1, 0, 1)
                                                                                                                                                                                                                                    love.graphics.print("FPS: " .. love.timer.getFPS(), love.graphics.getWidth() - 80, 10)
                                                                                                                                                                                                                                    love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                console.draw()
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                function love.update(dt)
                                                                                                                                                                                                                                if console.isOpen then return end
                                                                                                                                                                                                                                -- Ограничитель FPS (если VSync выключен)
                                                                                                                                                                                                                                if not settings.vsync and settings.max_fps > 0 then
                                                                                                                                                                                                                                    local target = 1 / settings.max_fps
                                                                                                                                                                                                                                    if dt < target then
                                                                                                                                                                                                                                        love.timer.sleep(target - dt)
                                                                                                                                                                                                                                    end
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                if mode == "gameplay" and game and game.update then
                                                                                                                                                                                                                                    local status = game.update(dt) -- Получаем статус из game.lua
                                                                                                                                                                                                                                    if status == "exit" then
                                                                                                                                                                                                                                        mode = "main_menu" -- Переходим в главное меню
                                                                                                                                                                                                                                        selected_index = 1
                                                                                                                                                                                                                                        game = nil -- Сбрасываем модуль игры
                                                                                                                                                                                                                                        if menu_music and not menu_music:isPlaying() then
                                                                                                                                                                                                                                            menu_music:play()
                                                                                                                                                                                                                                            end
                                                                                                                                                                                                                                    elseif status == "restart" then
                                                                                                                                                                                                                                        -- Перезапуск с теми же параметрами
                                                                                                                                                                                                                                        game.load(selected_song, selected_difficulty, settings.lives, settings.controls_modes[settings.controls_index], backgrounds[selected_song], settings.music_volume, settings.bullet_multiplier, settings.bullet_speed)
                                                                                                                                                                                                                                            end
                                                                                                                                                                                                                                            end
                                                                                                                                                                                                                                            end

                                                                                                                                                                                                                                            function love.keypressed(key)
                                                                                                                                                                                                                                            if console.keypressed(key) then return end
                                                                                                                                                                                                                                            if mode == "main_menu" then
        if key == "up" or key == "w" then
                                                                                                                                                                                                                                                    selected_index = math.max(1, selected_index - 1)
        elseif key == "down" or key == "s" then
                                                                                                                                                                                                                                                        selected_index = math.min(#main_menu_items, selected_index + 1)
                                                                                                                                                                                                                                                        elseif key == "return" then
                                                                                                                                                                                                                                                            local choice = main_menu_items[selected_index]
                                                                                                                                                                                                                                                            if choice == "osu-mode" then
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                mode = "osu_menu"
                                                                                                                                                                                                                                                                elseif choice == "Settings" then
                                                                                                                                                                                                                                                                settings_selected_index = 1
                                                                                                                                                                                                                                                                mode = "settings"
            temp_settings.music_volume = settings.music_volume
            temp_settings.resolution_index = settings.resolution_index
            temp_settings.fullscreen_mode_index = settings.fullscreen_mode_index
            temp_settings.lives = settings.lives
            temp_settings.controls_index = settings.controls_index
            temp_settings.bullet_multiplier = settings.bullet_multiplier
            temp_settings.bullet_speed = settings.bullet_speed
            temp_settings.bullet_size = settings.bullet_size
            temp_settings.player_speed = settings.player_speed
            temp_settings.show_fps = settings.show_fps
            temp_settings.vsync = settings.vsync
            temp_settings.max_fps = settings.max_fps
            temp_settings.max_fps_index = settings.max_fps_index
                                                                                                                                                                                                                                                                elseif choice == "Exit" then
                                                                                                                                                                                                                                                                love.event.quit()
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif mode == "settings" then
        handle_settings_key(key == "w" and "up" or key == "s" and "down" or key == "a" and "left" or key == "d" and "right" or key)

                                                                                                                                                                                                                                                                elseif mode == "osu_menu" then
                                                                                                                                                                                                                                                                local keys = get_song_list()
                                                                                                                                                                                                                                                                if #keys > 0 then
            if key == "up" or key == "w" then
                                                                                                                                                                                                                                                                selected_index = math.max(1, selected_index - 1)
            elseif key == "down" or key == "s" then
                                                                                                                                                                                                                                                                selected_index = math.min(#keys, selected_index + 1)
                                                                                                                                                                                                                                                                elseif key == "return" then
                                                                                                                                                                                                                                                                selected_song = keys[selected_index]
                                                                                                                                                                                                                                                                if maps[selected_song] and #maps[selected_song] > 0 then
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                mode = "difficulties"
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                if key == "escape" then
                                                                                                                                                                                                                                                                mode = "main_menu"
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif mode == "difficulties" and selected_song then
                                                                                                                                                                                                                                                                local difficulties = maps[selected_song] or {}
                                                                                                                                                                                                                                                                if #difficulties > 0 then
            if key == "up" or key == "w" then
                                                                                                                                                                                                                                                                selected_index = math.max(1, selected_index - 1)
            elseif key == "down" or key == "s" then
                                                                                                                                                                                                                                                                selected_index = math.min(#difficulties, selected_index + 1)
                                                                                                                                                                                                                                                                elseif key == "return" then
                                                                                                                                                                                                                                                                selected_difficulty = difficulties[selected_index]

                                                                                                                                                                                                                                                                -- *** ИСПРАВЛЕНИЕ: ОСТАНОВКА МУЗЫКИ МЕНЮ ***
                                                                                                                                                                                                                                                                if menu_music and menu_music:isPlaying() then
                                                                                                                                                                                                                                                                menu_music:stop()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                -- Загрузка и инициализация игры
                                                                                                                                                                                                                                                                game = require("game")
                                                                                                                                                                                                                                game.load(selected_song, selected_difficulty, settings.lives, settings.controls_modes[settings.controls_index], backgrounds[selected_song], settings.music_volume, settings.bullet_multiplier, settings.bullet_speed, settings.bullet_size, settings.player_speed)

                                                                                                                                                                                                                                                                mode = "gameplay"
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                if key == "escape" then
                                                                                                                                                                                                                                                                mode = "osu_menu"
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif mode == "gameplay" then
                                                                                                                                                                                                                                if game and game.keypressed then
                                                                                                                                                                                                                                local action, new_vol = game.keypressed(key)
                                                                                                                                                                                                                                if action == "exit" then
                                                                                                                                                                                                                                    if new_vol then 
                                                                                                                                                                                                                                        settings.music_volume = new_vol
                                                                                                                                                                                                                                        print("[AUDIO] Volume updated from game: " .. new_vol)
                                                                                                                                                                                                                                        save_game_config()
                                                                                                                                                                                                                                    end
                                                                                                                                                                                                                                    mode = "main_menu"
                                                                                                                                                                                                                                    game = nil
                                                                                                                                                                                                                                    if menu_music then 
                                                                                                                                                                                                                                        menu_music:setVolume(settings.music_volume)
                                                                                                                                                                                                                                        menu_music:play() 
                                                                                                                                                                                                                                    end
                                                                                                                                                                                                                                elseif action == "restart" then
                                                                                                                                                                                                                                    if new_vol then 
                                                                                                                                                                                                                                        settings.music_volume = new_vol
                                                                                                                                                                                                                                        save_game_config()
                                                                                                                                                                                                                                    end
                                                                                                                                        game.load(selected_song, selected_difficulty, settings.lives, settings.controls_modes[settings.controls_index], backgrounds[selected_song], settings.music_volume, settings.bullet_multiplier, settings.bullet_speed, settings.bullet_size, settings.player_speed)
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

function love.textinput(t)
    console.textinput(t)
end

function love.mousepressed(x, y, button)
    if console.isOpen then return end
    -- Если мы в игре, передаем управление туда
    if mode == "gameplay" and game and game.mousepressed then
        local action, new_vol = game.mousepressed(x, y, button)
        if action == "exit" then
            if new_vol then 
                settings.music_volume = new_vol
                save_game_config()
            end
            mode = "main_menu"
            game = nil
            if menu_music then 
                menu_music:setVolume(settings.music_volume)
                menu_music:play() 
            end
        elseif action == "restart" then
            if new_vol then 
                settings.music_volume = new_vol
                save_game_config()
            end
            game.load(selected_song, selected_difficulty, settings.lives, settings.controls_modes[settings.controls_index], backgrounds[selected_song], settings.music_volume, settings.bullet_multiplier, settings.bullet_speed, settings.bullet_size, settings.player_speed)
        end
        return
    end

    -- Обработка кликов в меню
    if button == 1 then
        local start_y = 80
        local line_h = 30
        local count = 0
        
        if mode == "main_menu" then count = #main_menu_items
        elseif mode == "settings" then count = #settings_options
        elseif mode == "osu_menu" then count = #get_song_list()
        elseif mode == "difficulties" and selected_song then count = #(maps[selected_song] or {})
        end
        
        for i = 1, count do
            local iy = start_y + i * line_h
            if y >= iy and y < iy + line_h and x > 20 then
                -- Логика для слайдера громкости (клик мышкой)
                if mode == "settings" and settings_options[i] == "Music Volume" then
                    local bar_x = 250
                    local bar_w = 200
                    if x >= bar_x and x <= bar_x + bar_w then
                        temp_settings.music_volume = (x - bar_x) / bar_w
                        settings.music_volume = temp_settings.music_volume
                        if menu_music then menu_music:setVolume(settings.music_volume) end
                        return -- Прерываем, чтобы не сработало переключение
                    end
                end
                -- Если кликнули по пункту
                if mode == "settings" then
                    settings_selected_index = i
                    if settings_options[i] == "Apply" or settings_options[i] == "Back" then
                        love.keypressed("return") -- Нажимаем кнопку
                    else
                        love.keypressed("right") -- Меняем значение (как стрелка вправо)
                    end
                else
                    selected_index = i
                    love.keypressed("return") -- Активируем пункт
                end
                return
            end
        end
    end
end

function love.mousemoved(x, y)
    if console.isOpen then return end
    if mode == "gameplay" and game and game.mousemoved then
        game.mousemoved(x, y)
        return
    end

    local start_y = 80
    local line_h = 30
    local count = 0
    
    if mode == "main_menu" then count = #main_menu_items
    elseif mode == "settings" then count = #settings_options
    elseif mode == "osu_menu" then count = #get_song_list()
    elseif mode == "difficulties" and selected_song then count = #(maps[selected_song] or {})
    end

    for i = 1, count do
        local iy = start_y + i * line_h
        if y >= iy and y < iy + line_h and x > 20 then
            if mode == "settings" then
                settings_selected_index = i
            else
                selected_index = i
            end
        end
    end
end
