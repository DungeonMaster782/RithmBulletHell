local console = require("console")
local editor = require("editor")
local maps_dir = "maps"
local maps = {}
local selected_index = 1
local mode = "main_menu" -- main_menu, osu_menu, difficulties, settings, gameplay
local selected_song = nil
local selected_difficulty = nil
local selected_custom_map = nil
local font
fonts = {} -- Глобальная таблица шрифтов

game = nil -- Глобальная переменная, чтобы консоль ее видела

-- Фоны
local main_menu_background_path = "res/images/menu.png"
local main_menu_background = nil
local menu_background_dim = 0.2 -- Затемнение фона в меню (0.0 - нет, 1.0 - черный)

local osu_menu_background_path = "res/images/osu_menu_bg.png"
local osu_menu_background = nil

local backgrounds = {}

local main_menu_items = {
    "Play Custom",
    "Level Editor",
    "osu-mode",
    "Settings",
    "Exit"
}

-- Настройки
settings = { -- Глобальная переменная, чтобы консоль ее видела
    music_volume = 0.5,
    resolution_index = 1,
    resolutions = {
        {2560, 1440},
        {1920, 1080},
        {1600, 900},
        {1366, 768},
        {1280, 720},
        {1024, 768}
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
    show_hitboxes = false,
    vsync = true,
    background_dim = 0.5,
    show_video = true,
    max_fps = 0, -- 0 = Unlimited
    max_fps_options = {30, 60, 120, 144, 240, 0},
    max_fps_index = 6,
    max_dash_charges = 3,
    dash_recharge_time = 3.0,
    dash_duration = 0.5,
    hitbox_radius = 6,
    invuln_time = 3.0
}
local temp_settings = {}
local settings_options = {"Music Volume", "Background Dim", "Show Video", "Resolution", "Window Mode", "Lives", "Controls", "Bullet Multiplier", "Bullet Speed", "Bullet Size", "Player Speed", "Show FPS", "Show Hitboxes", "VSync", "Max FPS", "Save", "Back"}
local settings_selected_index = 1

local next_time = 0
local custom_maps = {}
local new_map_name = ""
local notification = nil
local notification_timer = 0
local delete_confirmation = false
local map_to_delete = nil
local map_to_delete_folder = "maps"

local menu_music = nil
local menu_music_path = "res/sounds/menu_music.mp3" -- путь к mp3

-- Функция для применения настроек видео
local function apply_video_settings()
    local w, h
    if settings.resolution_index == 0 then
        w, h = love.graphics.getPixelWidth(), love.graphics.getPixelHeight()
    else
        local r = settings.resolutions[settings.resolution_index]
        w, h = r[1], r[2]
    end
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

    print("[VIDEO] Applying settings: " .. w .. "x" .. h .. " (" .. fs_mode .. ") VSync: " .. tostring(settings.vsync))
    
    -- Коррекция размера окна для HighDPI (чтобы окно не становилось огромным при масштабе > 100%)
    if not flags.fullscreen then
        local scale = love.window.getDPIScale()
        if scale > 1 then
            w = w / scale
            h = h / scale
        end
        
        -- Ограничение размера окна размерами рабочего стола (фикс для 125% масштаба)
        local dw, dh = love.window.getDesktopDimensions()
        if w > dw then
            local ratio = h / w
            w = dw
            h = w * ratio
        end
        if h > dh then
            local ratio = w / h
            h = dh
            w = h * ratio
        end
    end
    love.window.setMode(w, h, flags)
end

-- Загрузка конфига игры (для bullet settings)
local function load_game_config()
    local contents = nil
    
    -- 1. Сначала проверяем локальный файл (приоритет для переносной версии)
    local f = io.open("config.txt", "r")
    if f then
        contents = f:read("*all")
        f:close()
        print("[CONFIG] Loading config.txt from local file...")
    elseif love.filesystem.getInfo("config.txt") then
        -- 2. Если локального нет, читаем через LÖVE (Save Directory или Source)
        contents = love.filesystem.read("config.txt")
        print("[CONFIG] Loading config.txt from save directory/source...")
    end
    
    if not contents then return end

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
            if key == "show_hitboxes" then settings.show_hitboxes = (value == "true") end
            if key == "vsync" then settings.vsync = (value == "true") end
            if key == "background_dim" then settings.background_dim = n end
            if key == "show_video" then settings.show_video = (value == "true") end
            if key == "max_fps" then 
                settings.max_fps = n 
                -- Восстанавливаем индекс для меню
                for i, v in ipairs(settings.max_fps_options) do
                    if v == n then settings.max_fps_index = i break end
                end
            end
            if key == "max_dash_charges" then settings.max_dash_charges = n end
            if key == "dash_recharge_time" then settings.dash_recharge_time = n end
            if key == "dash_duration" then settings.dash_duration = n end
            if key == "hitbox_radius" then settings.hitbox_radius = n end
            if key == "invuln_time" then settings.invuln_time = n end
        end
    end
end

-- Сохранение конфига игры
local function save_game_config()
    print("[CONFIG] Saving config.txt...")
    local lines = {}
    table.insert(lines, "music_volume=" .. string.format("%.2f", settings.music_volume))
    table.insert(lines, "resolution_index=" .. settings.resolution_index)
    table.insert(lines, "fullscreen_mode_index=" .. settings.fullscreen_mode_index)
    table.insert(lines, "lives=" .. settings.lives)
    table.insert(lines, "controls_index=" .. settings.controls_index)
    table.insert(lines, "bullet_multiplier=" .. string.format("%.1f", settings.bullet_multiplier))
    table.insert(lines, "bullet_speed=" .. string.format("%.1f", settings.bullet_speed))
    table.insert(lines, "bullet_size=" .. string.format("%.1f", settings.bullet_size))
    table.insert(lines, "player_speed=" .. string.format("%.1f", settings.player_speed))
    table.insert(lines, "show_fps=" .. tostring(settings.show_fps))
    table.insert(lines, "show_hitboxes=" .. tostring(settings.show_hitboxes))
    table.insert(lines, "vsync=" .. tostring(settings.vsync))
    table.insert(lines, "background_dim=" .. string.format("%.2f", settings.background_dim))
    table.insert(lines, "show_video=" .. tostring(settings.show_video))
    table.insert(lines, "max_fps=" .. settings.max_fps)
    table.insert(lines, "max_dash_charges=" .. settings.max_dash_charges)
    table.insert(lines, "dash_recharge_time=" .. string.format("%.1f", settings.dash_recharge_time))
    table.insert(lines, "dash_duration=" .. string.format("%.2f", settings.dash_duration))
    table.insert(lines, "hitbox_radius=" .. string.format("%.1f", settings.hitbox_radius))
    table.insert(lines, "invuln_time=" .. string.format("%.1f", settings.invuln_time))
    
    local content = table.concat(lines, "\n")

    -- Пытаемся сохранить файл прямо в папку с игрой (через io), чтобы настройки были переносными
    local f = io.open("config.txt", "w")
    if f then
        f:write(content)
        f:close()
        -- Если успешно записали локально, удаляем копию из AppData, чтобы она не перекрывала наш файл
        love.filesystem.remove("config.txt")
    else
        -- Если не получилось (например, нет прав записи), сохраняем по старинке в AppData
        love.filesystem.write("config.txt", content)
    end
end

local function delete_map_directory(folder_name, base_dir)
    base_dir = base_dir or "maps"
    local path = base_dir .. "/" .. folder_name
    
    -- 1. Удаляем из save directory (рекурсивно)
    local function recursive_love_remove(p)
        local info = love.filesystem.getInfo(p)
        if not info then return end
        
        if info.type == "directory" then
            for _, item in ipairs(love.filesystem.getDirectoryItems(p)) do
                recursive_love_remove(p .. "/" .. item)
            end
            love.filesystem.remove(p)
        else
            love.filesystem.remove(p)
        end
    end
    recursive_love_remove(path)

    -- 2. Удаляем из папки проекта (через OS)
    local cmd
    if love.system.getOS() == "Windows" then
        cmd = 'rd /s /q "' .. path:gsub("/", "\\") .. '" 2>nul'
    else
        cmd = 'rm -rf "' .. path .. '"'
    end
    os.execute(cmd)
    
    print("[MAPS] Deleted map: " .. folder_name)
end

local function scan_custom_maps()
    custom_maps = {}
    local dir = "Mmaps"
    if not love.filesystem.getInfo(dir) then
        love.filesystem.createDirectory(dir)
    end
    local items = love.filesystem.getDirectoryItems(dir)
    for _, item in ipairs(items) do
        if love.filesystem.getInfo(dir .. "/" .. item).type == "directory" then
            table.insert(custom_maps, item)
        end
    end
end

-- Функция для расчета масштаба меню (адаптация под разрешение)
local function get_menu_scale()
    local w, h = love.graphics.getDimensions()
    local target_h = 720
    local scale = h / target_h
    return scale, 0, 0
end

-- Функции
function love.load()
console.load()
print("[MAIN] Game starting...")

-- Инициализация шрифтов один раз
local fontPath = "res/RussoOne-Regular.ttf"
if love.filesystem.getInfo(fontPath) then
    fonts.main = love.graphics.newFont(fontPath, 20)
    fonts.menu = love.graphics.newFont(fontPath, 24)
    fonts.title = love.graphics.newFont(fontPath, 40)
else
    fonts.main = love.graphics.newFont(20)
    fonts.menu = love.graphics.newFont(24)
    fonts.title = love.graphics.newFont(40)
end

font = fonts.main -- Для совместимости с локальной переменной в main.lua
love.graphics.setFont(fonts.main)

next_time = love.timer.getTime()
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
                scan_custom_maps()

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
                                                                                local bar_x = 400
                                                                                local bar_w = 200
                                                                                local bar_h = 20
                                                                                love.graphics.setColor(item_color)
                                                                                love.graphics.rectangle("line", bar_x, 80 + i * 30 + 2, bar_w, bar_h)
                                                                                love.graphics.rectangle("fill", bar_x, 80 + i * 30 + 2, bar_w * temp_settings.music_volume, bar_h)
                                                                                draw_text_with_outline(math.floor(temp_settings.music_volume * 100) .. "%", bar_x + bar_w + 10, 80 + i * 30, item_color)
                                                                                value = "" -- Уже отрисовали
                                                                            elseif option == "Background Dim" then
                                                                                draw_text_with_outline(prefix .. option, 70, 80 + i * 30, item_color)
                                                                                local bar_x = 400
                                                                                local bar_w = 200
                                                                                local bar_h = 20
                                                                                love.graphics.setColor(item_color)
                                                                                love.graphics.rectangle("line", bar_x, 80 + i * 30 + 2, bar_w, bar_h)
                                                                                love.graphics.rectangle("fill", bar_x, 80 + i * 30 + 2, bar_w * temp_settings.background_dim, bar_h)
                                                                                draw_text_with_outline(math.floor(temp_settings.background_dim * 100) .. "%", bar_x + bar_w + 10, 80 + i * 30, item_color)
                                                                                value = ""
                                                                            elseif option == "Show Video" then
                                                                                value = temp_settings.show_video and "On" or "Off"
                                                                                elseif option == "Resolution" then
                if temp_settings.resolution_index == 0 then
                    value = love.graphics.getPixelWidth() .. "x" .. love.graphics.getPixelHeight() .. " (Custom)"
                else
                    local r = settings.resolutions[temp_settings.resolution_index]
                    value = r[1].."x"..r[2]
                end
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
            elseif option == "Show Hitboxes" then
                value = temp_settings.show_hitboxes and "On" or "Off"
            elseif option == "VSync" then
                value = temp_settings.vsync and "On" or "Off"
            elseif option == "Max FPS" then
                value = (temp_settings.max_fps == 0) and "Unlimited" or temp_settings.max_fps
                                                                                            end
            if value ~= "" then
                draw_text_with_outline(prefix .. option .. ": " .. value, 70, 80 + i * 30, item_color)
            elseif option ~= "Music Volume" and option ~= "Background Dim" then -- Music Volume и Dim уже отрисованы выше
                draw_text_with_outline(prefix .. option, 70, 80 + i * 30, item_color)
            end
                                                                                            end
                                                                                            end

                                                                                            -- Функция для обработки клавиш в меню настроек
                                                                                            function handle_settings_key(key)
                                                                                            if key == "up" then
        settings_selected_index = settings_selected_index - 1
        if settings_selected_index < 1 then settings_selected_index = #settings_options end
                                                                                                elseif key == "down" then
        settings_selected_index = settings_selected_index + 1
        if settings_selected_index > #settings_options then settings_selected_index = 1 end
                                                                                                    elseif key == "left" then
                                                                                                        if settings_options[settings_selected_index] == "Music Volume" then
            temp_settings.music_volume = temp_settings.music_volume - 0.05
            if temp_settings.music_volume < 0 then temp_settings.music_volume = 1.0 end
            settings.music_volume = temp_settings.music_volume -- Применяем сразу
            if menu_music then menu_music:setVolume(settings.music_volume) end
                                                                                                            elseif settings_options[settings_selected_index] == "Background Dim" then
            temp_settings.background_dim = temp_settings.background_dim - 0.05
            if temp_settings.background_dim < 0 then temp_settings.background_dim = 1.0 end
            settings.background_dim = temp_settings.background_dim -- Применяем сразу
                                                                                                            elseif settings_options[settings_selected_index] == "Show Video" then
            temp_settings.show_video = not temp_settings.show_video
            settings.show_video = temp_settings.show_video -- Применяем сразу
                                                                                                            elseif settings_options[settings_selected_index] == "Resolution" then
            temp_settings.resolution_index = temp_settings.resolution_index - 1
            if temp_settings.resolution_index < 1 then 
                temp_settings.resolution_index = #settings.resolutions 
            elseif temp_settings.resolution_index == 0 then
                temp_settings.resolution_index = #settings.resolutions
            end
                                                                                                                elseif settings_options[settings_selected_index] == "Window Mode" then
            temp_settings.fullscreen_mode_index = temp_settings.fullscreen_mode_index - 1
            if temp_settings.fullscreen_mode_index < 1 then temp_settings.fullscreen_mode_index = #settings.fullscreen_modes end
                                                                                                                    elseif settings_options[settings_selected_index] == "Lives" then
            temp_settings.lives = temp_settings.lives - 1
            if temp_settings.lives < 1 then temp_settings.lives = 10 end
            settings.lives = temp_settings.lives -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Controls" then
            temp_settings.controls_index = temp_settings.controls_index - 1
            if temp_settings.controls_index < 1 then temp_settings.controls_index = #settings.controls_modes end
            settings.controls_index = temp_settings.controls_index -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Bullet Multiplier" then
            temp_settings.bullet_multiplier = math.max(0.1, temp_settings.bullet_multiplier - 0.1)
            settings.bullet_multiplier = temp_settings.bullet_multiplier -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Bullet Speed" then
            temp_settings.bullet_speed = math.max(0.1, temp_settings.bullet_speed - 0.1)
            settings.bullet_speed = temp_settings.bullet_speed -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Bullet Size" then
            temp_settings.bullet_size = math.max(0.1, temp_settings.bullet_size - 0.1)
            settings.bullet_size = temp_settings.bullet_size -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Player Speed" then
            temp_settings.player_speed = math.max(0.1, temp_settings.player_speed - 0.1)
            settings.player_speed = temp_settings.player_speed -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Show FPS" then
            temp_settings.show_fps = not temp_settings.show_fps
            settings.show_fps = temp_settings.show_fps -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Show Hitboxes" then
            temp_settings.show_hitboxes = not temp_settings.show_hitboxes
            settings.show_hitboxes = temp_settings.show_hitboxes -- Применяем сразу
        elseif settings_options[settings_selected_index] == "VSync" then
            temp_settings.vsync = not temp_settings.vsync
        elseif settings_options[settings_selected_index] == "Max FPS" then
            temp_settings.max_fps_index = temp_settings.max_fps_index - 1
            if temp_settings.max_fps_index < 1 then temp_settings.max_fps_index = #settings.max_fps_options end
            temp_settings.max_fps = settings.max_fps_options[temp_settings.max_fps_index]
            settings.max_fps = temp_settings.max_fps -- Применяем сразу
            settings.max_fps_index = temp_settings.max_fps_index
                                                                                                                        end
                                                                                                                        elseif key == "right" then
                                                                                                                            if settings_options[settings_selected_index] == "Music Volume" then
            temp_settings.music_volume = temp_settings.music_volume + 0.05
            if temp_settings.music_volume > 1.0 then temp_settings.music_volume = 0.0 end
            settings.music_volume = temp_settings.music_volume -- Применяем сразу
            if menu_music then menu_music:setVolume(settings.music_volume) end
                                                                                                                                elseif settings_options[settings_selected_index] == "Background Dim" then
            temp_settings.background_dim = temp_settings.background_dim + 0.05
            if temp_settings.background_dim > 1.0 then temp_settings.background_dim = 0.0 end
            settings.background_dim = temp_settings.background_dim -- Применяем сразу
                                                                                                                                elseif settings_options[settings_selected_index] == "Show Video" then
            temp_settings.show_video = not temp_settings.show_video
            settings.show_video = temp_settings.show_video -- Применяем сразу
                                                                                                                                elseif settings_options[settings_selected_index] == "Resolution" then
            temp_settings.resolution_index = temp_settings.resolution_index + 1
            if temp_settings.resolution_index > #settings.resolutions then 
                temp_settings.resolution_index = 1 
            elseif temp_settings.resolution_index == 0 then
                temp_settings.resolution_index = 1
            end
                                                                                                                                    elseif settings_options[settings_selected_index] == "Window Mode" then
            temp_settings.fullscreen_mode_index = temp_settings.fullscreen_mode_index + 1
            if temp_settings.fullscreen_mode_index > #settings.fullscreen_modes then temp_settings.fullscreen_mode_index = 1 end
                                                                                                                                        elseif settings_options[settings_selected_index] == "Lives" then
            temp_settings.lives = temp_settings.lives + 1
            if temp_settings.lives > 10 then temp_settings.lives = 1 end
            settings.lives = temp_settings.lives -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Controls" then
            temp_settings.controls_index = temp_settings.controls_index + 1
            if temp_settings.controls_index > #settings.controls_modes then temp_settings.controls_index = 1 end
            settings.controls_index = temp_settings.controls_index -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Bullet Multiplier" then
            temp_settings.bullet_multiplier = temp_settings.bullet_multiplier + 0.1
            settings.bullet_multiplier = temp_settings.bullet_multiplier -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Bullet Speed" then
            temp_settings.bullet_speed = temp_settings.bullet_speed + 0.1
            settings.bullet_speed = temp_settings.bullet_speed -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Bullet Size" then
            temp_settings.bullet_size = temp_settings.bullet_size + 0.1
            settings.bullet_size = temp_settings.bullet_size -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Player Speed" then
            temp_settings.player_speed = temp_settings.player_speed + 0.1
            settings.player_speed = temp_settings.player_speed -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Show FPS" then
            temp_settings.show_fps = not temp_settings.show_fps
            settings.show_fps = temp_settings.show_fps -- Применяем сразу
        elseif settings_options[settings_selected_index] == "Show Hitboxes" then
            temp_settings.show_hitboxes = not temp_settings.show_hitboxes
            settings.show_hitboxes = temp_settings.show_hitboxes -- Применяем сразу
        elseif settings_options[settings_selected_index] == "VSync" then
            temp_settings.vsync = not temp_settings.vsync
        elseif settings_options[settings_selected_index] == "Max FPS" then
            temp_settings.max_fps_index = temp_settings.max_fps_index + 1
            if temp_settings.max_fps_index > #settings.max_fps_options then temp_settings.max_fps_index = 1 end
            temp_settings.max_fps = settings.max_fps_options[temp_settings.max_fps_index]
            settings.max_fps = temp_settings.max_fps -- Применяем сразу
            settings.max_fps_index = temp_settings.max_fps_index
                                                                                                                                            end
                                                                                                                                            elseif key == "return" then
        if settings_options[settings_selected_index] == "Save" then
            -- Проверяем, изменились ли настройки видео
            local video_changed = false
            if temp_settings.resolution_index ~= settings.resolution_index or
               temp_settings.fullscreen_mode_index ~= settings.fullscreen_mode_index or
               temp_settings.vsync ~= settings.vsync then
                video_changed = true
            end

            -- Обновляем настройки видео в основном объекте
            settings.resolution_index = temp_settings.resolution_index
            settings.fullscreen_mode_index = temp_settings.fullscreen_mode_index
            settings.vsync = temp_settings.vsync
            
            -- Применяем видео настройки только если они изменились
            if video_changed then
                apply_video_settings()
            end
            
            save_game_config() -- СОХРАНЯЕМ В ФАЙЛ
        elseif settings_options[settings_selected_index] == "Back" then
            -- Просто выходим, так как настройки уже применены в памяти
            mode = "main_menu"
        end
                                                                                                                                                    elseif key == "escape" then
                                                                                                                                                        mode = "main_menu"
                                                                                                                                                        end
                                                                                                                                                            end

                                                                                                                                                            function love.draw()
                                                                                                                                                            local s, ox, oy = get_menu_scale()

                                                                                                                                                            if mode == "main_menu" then
                                                                                                                                                                if main_menu_background then
                                                                                                                                                                    love.graphics.draw(main_menu_background, 0, 0, 0,
                                                                                                                                                                                       love.graphics.getWidth() / main_menu_background:getWidth(),
                                                                                                                                                                                       love.graphics.getHeight() / main_menu_background:getHeight())
                                                                                                                                                                    end

                                                                                                                                                                    love.graphics.setColor(0, 0, 0, menu_background_dim)
                                                                                                                                                                    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                                                                                                                                                                    love.graphics.setColor(1, 1, 1, 1)

                                                                                                                                                                    love.graphics.push()
                                                                                                                                                                    love.graphics.translate(ox, oy)
                                                                                                                                                                    love.graphics.scale(s)

                                                                                                                                                                    draw_text_with_outline("Main Menu", 50, 50)
                                                                                                                                                                    
                                                                                                                                                                    -- Подсказка про импорт
                                                                                                                                                                    love.graphics.setColor(0.7, 0.7, 0.7, 1)
                                                                                                                                                                    love.graphics.print("Drag & Drop .osz files to import", 50, 720 - 40)
                                                                                                                                                                    love.graphics.setColor(1, 1, 1, 1)

                                                                                                                                                                    for i, item in ipairs(main_menu_items) do
                                                                                                                                                                        local prefix = (i == selected_index) and "> " or "  "
                                                                                                                                                                        local color = (i == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                                                                                                                                                                        draw_text_with_outline(prefix .. item, 70, 80 + i * 30, color)
                                                                                                                                                                        end
                                                                                                                                                                        love.graphics.pop()

                                                                                                                                                                        elseif mode == "settings" then
                                                                                                                                                                            if main_menu_background then
                                                                                                                                                                                love.graphics.draw(main_menu_background, 0, 0, 0,
                                                                                                                                                                                                   love.graphics.getWidth() / main_menu_background:getWidth(),
                                                                                                                                                                                                   love.graphics.getHeight() / main_menu_background:getHeight())
                                                                                                                                                                                love.graphics.setColor(0, 0, 0, menu_background_dim)
                                                                                                                                                                                love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                                                                                                                                                                                love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                end
                                                                                                                                                                                love.graphics.push()
                                                                                                                                                                                love.graphics.translate(ox, oy)
                                                                                                                                                                                love.graphics.scale(s)
                                                                                                                                                                                draw_settings_menu()
                                                                                                                                                                                love.graphics.pop()

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
                                                                                                                                                                                                    love.graphics.setColor(0, 0, 0, menu_background_dim)
                                                                                                                                                                                                    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                                                                                                                                                                                                    love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                                    end

                                                                                                                                                                                                    love.graphics.push()
                                                                                                                                                                                                    love.graphics.translate(ox, oy)
                                                                                                                                                                                                    love.graphics.scale(s)
                                                                                                                                                                                                    draw_text_with_outline("Select a song:", 50, 50)
                                                                                                                                                                                                    for i, folder in ipairs(keys) do
                                                                                                                                                                                                        local prefix = (i == selected_index) and "> " or "  "
                                                                                                                                                                                                        local color = (i == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                                                                                                                                                                                                        draw_text_with_outline(prefix .. folder, 70, 80 + i * 30, color)
                                                                                                                                                                                                        end
                                                                                                                                                                                                        love.graphics.setColor(1, 0.5, 0.5, 1)
                                                                                                                                                                                                        draw_text_with_outline("Press DELETE to remove map", 50, 720 - 40)
                                                                                                                                                                                                        love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                                        love.graphics.pop()

                                                                                                                                                                                                        elseif mode == "difficulties" and selected_song then
                                                                                                                                                                                                            local bg = backgrounds[selected_song]
                                                                                                                                                                                                            if bg then
                                                                                                                                                                                                                love.graphics.draw(bg, 0, 0, 0,
                                                                                                                                                                                                                                   love.graphics.getWidth() / bg:getWidth(),
                                                                                                                                                                                                                                   love.graphics.getHeight() / bg:getHeight())
                                                                                                                                                                                                                love.graphics.setColor(0, 0, 0, menu_background_dim)
                                                                                                                                                                                                                love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                                                                                                                                                                                                                love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                                                end

                                                                                                                                                                                                                love.graphics.push()
                                                                                                                                                                                                                love.graphics.translate(ox, oy)
                                                                                                                                                                                                                love.graphics.scale(s)
                                                                                                                                                                                                                draw_text_with_outline("Select difficulty for: " .. selected_song, 50, 50)
                                                                                                                                                                                                                local difficulties = maps[selected_song] or {}
                                                                                                                                                                                                                for i, diff in ipairs(difficulties) do
                                                                                                                                                                                                                    local prefix = (i == selected_index) and "> " or "  "
                                                                                                                                                                                                                    local color = (i == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                                                                                                                                                                                                                    draw_text_with_outline(prefix .. diff, 70, 80 + i * 30, color)
                                                                                                                                                                                                                    end
                                                                                                                                                                                                                    love.graphics.pop()

                                                                                                                                                                                                                    elseif mode == "gameplay" then
                                                                                                                                                                                                                        if game and game.draw then
                                                                                                                                                                                                                            game.draw()
                                                                                                                                                                                                                            else
                                                                                                                                                                                                                                draw_text_with_outline("Game started: " .. (selected_song or "") .. " - " .. (selected_difficulty or ""), 50, 50)
                                                                                                                                                                                                                                draw_text_with_outline("Press ESC to return to menu", 50, 80)
                                                                                                                                                                                                                                end
    elseif mode == "custom_select" then
        love.graphics.push()
        love.graphics.translate(ox, oy)
        love.graphics.scale(s)
        draw_text_with_outline("Select Custom Map:", 50, 50)
        if #custom_maps == 0 then
            draw_text_with_outline("No maps in Mmaps folder!", 70, 80, {1, 0, 0, 1})
        else
            for i, map in ipairs(custom_maps) do
                local prefix = (i == selected_index) and "> " or "  "
                local color = (i == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                draw_text_with_outline(prefix .. map, 70, 80 + i * 30, color)
            end
            love.graphics.setColor(1, 0.5, 0.5, 1)
            draw_text_with_outline("Press DELETE to remove map", 50, 720 - 40)
            love.graphics.setColor(1, 1, 1, 1)
        end
        love.graphics.pop()
    elseif mode == "editor_select" then
        love.graphics.push()
        love.graphics.translate(ox, oy)
        love.graphics.scale(s)
        draw_text_with_outline("Editor - Select Map:", 50, 50)
        local prefix = (selected_index == 1) and "> " or "  "
        local color = (selected_index == 1) and {0, 1, 0, 1} or {1, 1, 1, 1}
        draw_text_with_outline(prefix .. "[Create New Map]", 70, 80, color)
        
        for i, map in ipairs(custom_maps) do
            local idx = i + 1
            prefix = (idx == selected_index) and "> " or "  "
            color = (idx == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
            draw_text_with_outline(prefix .. map, 70, 80 + idx * 30, color)
        end
        if selected_index > 1 then
            love.graphics.setColor(1, 0.5, 0.5, 1)
            draw_text_with_outline("Press DELETE to remove map", 50, 720 - 40)
            love.graphics.setColor(1, 1, 1, 1)
        end
        love.graphics.pop()
    elseif mode == "editor" then
        editor.draw()
    elseif mode == "editor_name_input" then
        love.graphics.push()
        love.graphics.translate(ox, oy)
        love.graphics.scale(s)
        draw_text_with_outline("Enter New Map Name:", 50, 50)
        draw_text_with_outline(new_map_name .. "_", 50, 80, {1, 1, 0, 1})
        love.graphics.pop()
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                -- Отрисовка FPS (теперь внутри love.draw)
                                                                                                                                                                                                                                if settings.show_fps then
                                                                                                                                                                                                                                    love.graphics.setColor(0, 1, 0, 1)
                                                                                                                                                                                                                                    love.graphics.print("FPS: " .. love.timer.getFPS(), love.graphics.getWidth() - 80, 10)
                                                                                                                                                                                                                                    love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                console.draw()

                                                                                                                                                                -- Отрисовка уведомлений
                                                                                                                                                                if notification and notification_timer > 0 then
                                                                                                                                                                    love.graphics.setColor(0, 0, 0, 0.8)
                                                                                                                                                                    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), 40)
                                                                                                                                                                    love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                    love.graphics.printf(notification, 0, 10, love.graphics.getWidth(), "center")
                                                                                                                                                                end

                                                                                                                                                                -- Окно подтверждения удаления
                                                                                                                                                                if delete_confirmation then
                                                                                                                                                                    love.graphics.setColor(0, 0, 0, 0.9)
                                                                                                                                                                    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                                                                                                                                                                    
                                                                                                                                                                    love.graphics.setColor(1, 0, 0, 1)
                                                                                                                                                                    draw_text_with_outline("DELETE MAP?", love.graphics.getWidth()/2 - 60, love.graphics.getHeight()/2 - 60)
                                                                                                                                                                    love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                    draw_text_with_outline(map_to_delete, love.graphics.getWidth()/2 - (font:getWidth(map_to_delete)/2), love.graphics.getHeight()/2 - 20)
                                                                                                                                                                    draw_text_with_outline("Press Y to confirm, N to cancel", love.graphics.getWidth()/2 - 130, love.graphics.getHeight()/2 + 40)
                                                                                                                                                                end
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                function love.update(dt)
                                                                                                                                                                                                                                if console.isOpen then return end
                                                                                                                                                                                                                                -- Ограничитель FPS (если VSync выключен)
                                                                                                                                                                                                                                if not settings.vsync and settings.max_fps > 0 then
        next_time = next_time + 1.0 / settings.max_fps
        local cur_time = love.timer.getTime()
        if next_time > cur_time then
            local time_to_sleep = next_time - cur_time
            -- Гибридное ожидание: sleep для разгрузки CPU, busy-wait для точности
            if time_to_sleep > 0.002 then
                love.timer.sleep(time_to_sleep - 0.001)
            end
            -- Точная доводка циклом (busy-wait)
            while love.timer.getTime() < next_time do end
        else
            next_time = cur_time
                                                                                                                                                                                                                                    end
    else
        next_time = love.timer.getTime()
                                                                                                                                                                                                                                end

                                                                                                                                                                if notification_timer > 0 then
                                                                                                                                                                    notification_timer = notification_timer - dt
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
                                                                                                                                                                                                                                        if selected_custom_map then
                                                                                                                                                                                                                                            game.load_custom(selected_custom_map, settings)
                                                                                                                                                                                                                                        else
                                                                                                                                                                                                                                            game.load(selected_song, selected_difficulty, backgrounds[selected_song], settings)
                                                                                                                                                                                                                                        end
                                                                                                                                                                                                                                            end
                                                                                                                                                                                                                                            end
    
    if mode == "editor" then
        editor.update(dt)
    end
                                                                                                                                                                                                                                            end

                                                                                                                                                                                                                                            function love.keypressed(key)
                                                                                                                                                                if delete_confirmation then
                                                                                                                                                                    if key == "y" then
                                                                                                                                                                        if map_to_delete then
                                                                                                                                                                            delete_map_directory(map_to_delete, map_to_delete_folder)
                                                                                                                                                                            if map_to_delete_folder == "Mmaps" then
                                                                                                                                                                                scan_custom_maps()
                                                                                                                                                                            else
                                                                                                                                                                                scan_maps()
                                                                                                                                                                            end
                                                                                                                                                                            selected_index = 1
                                                                                                                                                                            notification = "Map deleted: " .. map_to_delete
                                                                                                                                                                            notification_timer = 3
                                                                                                                                                                        end
                                                                                                                                                                        delete_confirmation = false
                                                                                                                                                                        map_to_delete = nil
                                                                                                                                                                    elseif key == "n" or key == "escape" then
                                                                                                                                                                        delete_confirmation = false
                                                                                                                                                                        map_to_delete = nil
                                                                                                                                                                    end
                                                                                                                                                                    return
                                                                                                                                                                end

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
                                                                                                                                                                                                                                                            elseif choice == "Play Custom" then
                                                                                                                                                                                                                                                                scan_custom_maps()
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                mode = "custom_select"
                                                                                                                                                                                                                                                            elseif choice == "Level Editor" then
                                                                                                                                                                                                                                                                scan_custom_maps()
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                mode = "editor_select"
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
            temp_settings.show_hitboxes = settings.show_hitboxes
            temp_settings.vsync = settings.vsync
            temp_settings.max_fps = settings.max_fps
            temp_settings.background_dim = settings.background_dim
            temp_settings.show_video = settings.show_video
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
                                                                                                                                                                                                                                                                elseif key == "delete" then
                                                                                                                                                                                                                                                                    local keys = get_song_list()
                                                                                                                                                                                                                                                                    if #keys > 0 then
                                                                                                                                                                                                                                                                        map_to_delete = keys[selected_index]
                                                                                                                                                                                                        map_to_delete_folder = "maps"
                                                                                                                                                                                                                                                                        delete_confirmation = true
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
                                                                                                                                                                                                                                                               selected_custom_map = nil

                                                                                                                                                                                                                                                                -- *** ИСПРАВЛЕНИЕ: ОСТАНОВКА МУЗЫКИ МЕНЮ ***
                                                                                                                                                                                                                                                                if menu_music and menu_music:isPlaying() then
                                                                                                                                                                                                                                                                menu_music:stop()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                -- Загрузка и инициализация игры
                                                                                                                                                                                                                                                                game = require("game")
                                                                                                                                                                                                                                game.load(selected_song, selected_difficulty, backgrounds[selected_song], settings)

                                                                                                                                                                                                                                                                mode = "gameplay"
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                if key == "escape" then
                                                                                                                                                                                                                                                                mode = "osu_menu"
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif mode == "editor_name_input" then
                                                                                                                                                                                                                                                                    if key == "return" then
                                                                                                                                                                                                                                                                        if new_map_name ~= "" then
                                                                                                                                                                                                                                            if menu_music and menu_music:isPlaying() then menu_music:stop() end
                                                                                                                                                                                                                                                                            editor.load(new_map_name)
                                                                                                                                                                                                                                                                            mode = "editor"
                                                                                                                                                                                                                                                                        end
                                                                                                                                                                                                                                                                    elseif key == "escape" then
                                                                                                                                                                                                                                                                        mode = "editor_select"
                                                                                                                                                                                                                                                                    elseif key == "backspace" then
                                                                                                                                                                                                                                                                       local byteoffset = nil
                                                                                                                                                                                                                                                                       if love.utf8 then
                                                                                                                                                                                                                                                                           local status, offset = pcall(love.utf8.offset, new_map_name, -1)
                                                                                                                                                                                                                                                                           if status then byteoffset = offset end
                                                                                                                                                                                                                                                                       end
                                                                                                                                                                                                                                                                       
                                                                                                                                                                                                                                                                        if byteoffset then
                                                                                                                                                                                                                                                                            new_map_name = string.sub(new_map_name, 1, byteoffset - 1)
                                                                                                                                                                                                                                                                       else
                                                                                                                                                                                                                                                                           local len = #new_map_name
                                                                                                                                                                                                                                                                           if len > 0 then
                                                                                                                                                                                                                                                                               local i = len
                                                                                                                                                                                                                                                                               while i > 1 and (string.byte(new_map_name, i) >= 128 and string.byte(new_map_name, i) <= 191) do
                                                                                                                                                                                                                                                                                   i = i - 1
                                                                                                                                                                                                                                                                               end
                                                                                                                                                                                                                                                                               new_map_name = string.sub(new_map_name, 1, i - 1)
                                                                                                                                                                                                                                                                           end
                                                                                                                                                                                                                                                                        end
                                                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                                                elseif mode == "custom_select" then
                                                                                                                                                                                                                                                                    if #custom_maps > 0 then
                                                                                                                                                                                                                                                                        if key == "up" or key == "w" then
                                                                                                                                                                                                                                                                            selected_index = math.max(1, selected_index - 1)
                                                                                                                                                                                                                                                                        elseif key == "down" or key == "s" then
                                                                                                                                                                                                                                                                            selected_index = math.min(#custom_maps, selected_index + 1)
                                                                                                                                                                                                                                                                        elseif key == "return" then
                                                                                                                                                                                                                                                                            local map_file = custom_maps[selected_index]
                                                                                                                                                                                                                                                                           selected_custom_map = map_file
                                                                                                                                                                                                                                                                           selected_song = nil
                                                                                                                                                                                                                                                                           selected_difficulty = nil
                                                                                                                                                                                                                                                                            if menu_music and menu_music:isPlaying() then menu_music:stop() end
                                                                                                                                                                                                                                                                            game = require("game")
                                                                                                                                                                                                                                                                            game.load_custom(map_file, settings)
                                                                                                                                                                                                                                                                            mode = "gameplay"
                                                                                                                                                                                                                                                                        elseif key == "delete" then
                                                                                                                                                                                                                                                                            map_to_delete = custom_maps[selected_index]
                                                                                                                                                                                                                                                                            map_to_delete_folder = "Mmaps"
                                                                                                                                                                                                                                                                            delete_confirmation = true
                                                                                                                                                                                                                                                                        end
                                                                                                                                                                                                                                                                    end
                                                                                                                                                                                                                                                                    if key == "escape" then
                                                                                                                                                                                                                                                                        mode = "main_menu"
                                                                                                                                                                                                                                                                        selected_index = 1
                                                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                                                elseif mode == "editor_select" then
                                                                                                                                                                                                                                                                    local count = #custom_maps + 1
                                                                                                                                                                                                                                                                    if key == "up" or key == "w" then
                                                                                                                                                                                                                                                                        selected_index = math.max(1, selected_index - 1)
                                                                                                                                                                                                                                                                    elseif key == "down" or key == "s" then
                                                                                                                                                                                                                                                                        selected_index = math.min(count, selected_index + 1)
                                                                                                                                                                                                                                                                    elseif key == "return" then
                                                                                                                                                                                                                                                                        if selected_index == 1 then
                                                                                                                                                                                                                                                                            mode = "editor_name_input"
                                                                                                                                                                                                                                                                            new_map_name = ""
                                                                                                                                                                                                                                                                        else
                                                                                                                                                                                                                                            if menu_music and menu_music:isPlaying() then menu_music:stop() end
                                                                                                                                                                                                                                                                            editor.load(custom_maps[selected_index - 1])
                                                                                                                                                                                                                                                                           mode = "editor"
                                                                                                                                                                                                                                                                        end
                                                                                                                                                                                                                                                                    end
                                                                                                                                                                                                    if key == "delete" then
                                                                                                                                                                                                        if selected_index > 1 then
                                                                                                                                                                                                            map_to_delete = custom_maps[selected_index - 1]
                                                                                                                                                                                                            map_to_delete_folder = "Mmaps"
                                                                                                                                                                                                            delete_confirmation = true
                                                                                                                                                                                                        end
                                                                                                                                                                                                    end
                                                                                                                                                                                                                                                                    if key == "escape" then
                                                                                                                                                                                                                                                                        mode = "main_menu"
                                                                                                                                                                                                                                                                        selected_index = 1
                                                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                                                elseif mode == "editor" then
                                                                                                                                                                                                                                                                    local action = editor.keypressed(key)
                                                                                                                                                                                                                                                                    if action == "exit" then
                                                                                                                                                                                                                                                                        mode = "main_menu"
                                                                                                                                                                                                                                                                        scan_custom_maps()
                                                                                                                                                                                                                                        if menu_music and not menu_music:isPlaying() then
                                                                                                                                                                                                                                            menu_music:play()
                                                                                                                                                                                                                                        end
                                                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                                                elseif mode == "gameplay" then
                                                                                                                                                                                                                                if game and game.keypressed then
                                                                                                                                                                                                                                local action, new_vol, new_dim, new_video = game.keypressed(key)
                                                                                                                                                                                                                                if action == "exit" then
                                                                                                                                                                                                                                    if new_vol then 
                                                                                                                                                                                                                                        settings.music_volume = new_vol
                                                                                                                                                                                                                                        if new_dim then settings.background_dim = new_dim end
                                                                                                                                                                                                                                        if new_video ~= nil then settings.show_video = new_video end
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
                                                                                                                                                                                                                                        if new_dim then settings.background_dim = new_dim end
                                                                                                                                                                                                                                        if new_video ~= nil then settings.show_video = new_video end
                                                                                                                                                                                                                                        save_game_config()
                                                                                                                                                                                                                                    end
                                                                                                                                                                                                                                    if selected_custom_map then
                                                                                                                                                                                                                                        game.load_custom(selected_custom_map, settings)
                                                                                                                                                                                                                                    else
                                                                                                                                                                                                                                        game.load(selected_song, selected_difficulty, backgrounds[selected_song], settings)
                                                                                                                                                                                                                                    end
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                
                                                                                                                                                                                                                                                                if mode == "editor" then
                                                                                                                                                                                                                                                                    editor.update(dt)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                -- Draw section additions
                                                                                                                                                                                                                                                                if mode == "custom_select" then
                                                                                                                                                                                                                                                                    draw_text_with_outline("Select Custom Map:", 50, 50)
                                                                                                                                                                                                                                                                    if #custom_maps == 0 then
                                                                                                                                                                                                                                                                        draw_text_with_outline("No maps in Mmaps folder!", 70, 80, {1, 0, 0, 1})
                                                                                                                                                                                                                                                                    else
                                                                                                                                                                                                                                                                        for i, map in ipairs(custom_maps) do
                                                                                                                                                                                                                                                                            local prefix = (i == selected_index) and "> " or "  "
                                                                                                                                                                                                                                                                            local color = (i == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                                                                                                                                                                                                                                                                            draw_text_with_outline(prefix .. map, 70, 80 + i * 30, color)
                                                                                                                                                                                                                                                                        end
                                                                                                                                                                                                        love.graphics.setColor(1, 0.5, 0.5, 1)
                                                                                                                                                                                                        draw_text_with_outline("Press DELETE to remove map", 50, love.graphics.getHeight() - 40)
                                                                                                                                                                                                        love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                                                                                                    end
                                                                                                                                                                                                                                                                elseif mode == "editor_select" then
                                                                                                                                                                                                                                                                    draw_text_with_outline("Editor - Select Map:", 50, 50)
                                                                                                                                                                                                                                                                    local prefix = (selected_index == 1) and "> " or "  "
                                                                                                                                                                                                                                                                    local color = (selected_index == 1) and {0, 1, 0, 1} or {1, 1, 1, 1}
                                                                                                                                                                                                                                                                    draw_text_with_outline(prefix .. "[Create New Map]", 70, 80, color)
                                                                                                                                                                                                                                                                    
                                                                                                                                                                                                                                                                    for i, map in ipairs(custom_maps) do
                                                                                                                                                                                                                                                                        local idx = i + 1
                                                                                                                                                                                                                                                                        prefix = (idx == selected_index) and "> " or "  "
                                                                                                                                                                                                                                                                        color = (idx == selected_index) and {1, 1, 0, 1} or {1, 1, 1, 1}
                                                                                                                                                                                                                                                                        draw_text_with_outline(prefix .. map, 70, 80 + idx * 30, color)
                                                                                                                                                                                                                                                                    end
                                                                                                                                                                                                    if selected_index > 1 then
                                                                                                                                                                                                        love.graphics.setColor(1, 0.5, 0.5, 1)
                                                                                                                                                                                                        draw_text_with_outline("Press DELETE to remove map", 50, love.graphics.getHeight() - 40)
                                                                                                                                                                                                        love.graphics.setColor(1, 1, 1, 1)
                                                                                                                                                                                                    end
                                                                                                                                                                                                                                                                elseif mode == "editor" then
                                                                                                                                                                                                                                                                    editor.draw()
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                if mode == "editor_name_input" then
                                                                                                                                                                                                                                                                    draw_text_with_outline("Enter New Map Name:", 50, 50)
                                                                                                                                                                                                                                                                    draw_text_with_outline(new_map_name .. "_", 50, 80, {1, 1, 0, 1})
                                                                                                                                                                                                                                                                end

function love.textinput(t)
    console.textinput(t)
    if mode == "editor_name_input" then
        new_map_name = new_map_name .. t
    end
end

function love.mousepressed(x, y, button)
    if console.isOpen then return end
    
    if mode == "editor" then
        editor.mousepressed(x, y, button)
        return
    end

    -- Если мы в игре, передаем управление туда
    if mode == "gameplay" and game and game.mousepressed then
        local action, new_vol, new_dim, new_video = game.mousepressed(x, y, button)
        if action == "exit" then
            if new_vol then 
                settings.music_volume = new_vol
                if new_dim then settings.background_dim = new_dim end
                if new_video ~= nil then settings.show_video = new_video end
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
                if new_dim then settings.background_dim = new_dim end
                if new_video ~= nil then settings.show_video = new_video end
                save_game_config()
            end
            if selected_custom_map then
                game.load_custom(selected_custom_map, settings)
            else
                game.load(selected_song, selected_difficulty, backgrounds[selected_song], settings)
            end
        end
        return
    end

    -- Масштабируем координаты мыши для меню
    local s, ox, oy = get_menu_scale()
    x = (x - ox) / s
    y = (y - oy) / s

    -- Обработка кликов в меню
    if button == 1 then
        local start_y = 80
        local line_h = 30
        local count = 0
        
        if mode == "main_menu" then count = #main_menu_items
        elseif mode == "settings" then count = #settings_options
        elseif mode == "osu_menu" then count = #get_song_list()
        elseif mode == "difficulties" and selected_song then count = #(maps[selected_song] or {})
        elseif mode == "custom_select" then count = #custom_maps
        elseif mode == "editor_select" then count = #custom_maps + 1
        end
        
        for i = 1, count do
            local iy = start_y + i * line_h
            if y >= iy and y < iy + line_h and x > 20 then
                -- Логика для слайдера громкости (клик мышкой)
                if mode == "settings" and settings_options[i] == "Music Volume" then
                    local bar_x = 400
                    local bar_w = 200
                    if x >= bar_x and x <= bar_x + bar_w then
                        temp_settings.music_volume = (x - bar_x) / bar_w
                        settings.music_volume = temp_settings.music_volume
                        if menu_music then menu_music:setVolume(settings.music_volume) end
                        return -- Прерываем, чтобы не сработало переключение
                    end
                elseif mode == "settings" and settings_options[i] == "Background Dim" then
                    local bar_x = 400
                    local bar_w = 200
                    if x >= bar_x and x <= bar_x + bar_w then
                        temp_settings.background_dim = (x - bar_x) / bar_w
                        return
                    end
                end
                -- Если кликнули по пункту
                if mode == "settings" then
                    settings_selected_index = i
                    if settings_options[i] == "Save" or settings_options[i] == "Back" then
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

local function ensure_dir(path)
    love.filesystem.createDirectory(path) -- Создаем в save directory (гарантировано работает)
    
    -- Пытаемся создать в папке проекта (для удобства разработки)
    local cmd
    if love.system.getOS() == "Windows" then
        cmd = 'mkdir "' .. path:gsub("/", "\\") .. '" 2>nul'
    else
        cmd = 'mkdir -p "' .. path .. '"'
    end
    os.execute(cmd)
end

local function write_file(path, data)
    -- Пытаемся записать через стандартный IO (в папку проекта)
    local f = io.open(path, "wb")
    if f then f:write(data) f:close() return true end
    -- Если не вышло, пишем через LÖVE (в save directory)
    return love.filesystem.write(path, data)
end

function love.filedropped(file)
    if mode == "editor" then
        editor.filedropped(file)
        return
    end

    local filename = file:getFilename()
    local ext = filename:match("%.([^%.]+)$")
    
    if ext and (ext:lower() == "osz" or ext:lower() == "zip") then
        notification = "Importing map... Please wait."
        notification_timer = 5
        love.draw() -- Принудительно рисуем кадр с уведомлением
        love.graphics.present()
        
        local mount_point = "temp_import_" .. tostring(love.timer.getTime()):gsub("%.", "")
        if love.filesystem.mount(file, mount_point) then
            local map_name = filename:match("([^/\\]+)%.%w+$") or "imported_map"
            local target_dir = "maps/" .. map_name
            
            ensure_dir("maps")
            ensure_dir(target_dir)
            
            local function copy_dir(src, dst)
                for _, item in ipairs(love.filesystem.getDirectoryItems(src)) do
                    local src_path = src .. "/" .. item
                    local dst_path = dst .. "/" .. item
                    local info = love.filesystem.getInfo(src_path)
                    if info.type == "directory" then
                        ensure_dir(dst_path)
                        copy_dir(src_path, dst_path)
                    elseif info.type == "file" then
                        local data = love.filesystem.read(src_path)
                        if data then write_file(dst_path, data) end
                    end
                end
            end
            
            copy_dir(mount_point, target_dir)
            love.filesystem.unmount(mount_point)
            
            scan_maps() -- Обновляем список карт
            notification = "Successfully imported: " .. map_name
            notification_timer = 5
        else
            notification = "Failed to open archive (corrupted?)"
            notification_timer = 5
        end
    else
        notification = "Only .osz or .zip files are supported!"
        notification_timer = 3
    end
end

function love.wheelmoved(x, y)
    if mode == "editor" then
        editor.wheelmoved(x, y)
    end
end

function love.mousemoved(x, y)
    if console.isOpen then return end
    if mode == "gameplay" and game and game.mousemoved then
        game.mousemoved(x, y)
        return
    end

    -- Масштабируем координаты мыши для меню
    local s, ox, oy = get_menu_scale()
    x = (x - ox) / s
    y = (y - oy) / s

    local start_y = 80
    local line_h = 30
    local count = 0
    
    if mode == "main_menu" then count = #main_menu_items
    elseif mode == "settings" then count = #settings_options
    elseif mode == "osu_menu" then count = #get_song_list()
    elseif mode == "difficulties" and selected_song then count = #(maps[selected_song] or {})
    elseif mode == "custom_select" then count = #custom_maps
    elseif mode == "editor_select" then count = #custom_maps + 1
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

function love.resize(w, h)
    -- w и h здесь в логических единицах (points), но для сравнения с разрешениями нужны пиксели
    local pw = love.graphics.getPixelWidth()
    local ph = love.graphics.getPixelHeight()
    
    -- Обновляем игру
    if game and game.resize then
        game.resize(w, h)
    end
    
    -- Проверяем, совпадает ли текущий размер с пресетами
    local found = false
    for i, r in ipairs(settings.resolutions) do
        if r[1] == pw and r[2] == ph then
            settings.resolution_index = i
            if mode == "settings" then temp_settings.resolution_index = i end
            found = true
            break
        end
    end
    if not found then
        settings.resolution_index = 0 -- 0 = Custom
        if mode == "settings" then temp_settings.resolution_index = 0 end
    end
end

function love.quit()
    save_game_config()
end
