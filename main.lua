local maps_dir = "maps"
local maps = {}
local selected_index = 1
local mode = "main_menu" -- main_menu, osu_menu, difficulties, settings, gameplay
local selected_song = nil
local selected_difficulty = nil
local font

local game = nil -- Изменено: будет хранить загруженный модуль игры

-- Фоны
local main_menu_background_path = "res/menu.png"
local main_menu_background = nil

local osu_menu_background_path = "res/osu_menu_bg.png"
local osu_menu_background = nil

local backgrounds = {}

local main_menu_items = {
    "osu-mode",
    "Settings",
    "Exit"
}

-- Настройки
local settings = {
    music_volume = 0.5,
    resolution_index = 1,
    resolutions = {
        {1920, 1080},
        {1600, 900},
        {1280, 720}
    },
    fullscreen_mode_index = 1,
    fullscreen_modes = {"fullscreen", "windowed", "borderless"},
    lives = 3
}
local settings_options = {"Music Volume", "Resolution", "Window Mode", "Lives", "Back"}
local settings_selected_index = 1

local menu_music = nil
local menu_music_path = "res/menu_music.mp3" -- путь к mp3

-- Функции
function love.load()
font = love.graphics.newFont(18)
love.graphics.setFont(font)

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
                    local r = settings.resolutions[settings.resolution_index]
                    local fs_mode = settings.fullscreen_modes[settings.fullscreen_mode_index]
                    love.window.setMode(r[1], r[2], {
                        fullscreen = (fs_mode == "fullscreen"),
                                        borderless = (fs_mode == "borderless"),
                                        resizable = true
                    })
                    end

                    function scan_maps()
                    maps = {}
                    backgrounds = {}

                    if love.filesystem.getInfo(maps_dir) then
                        local folders = love.filesystem.getDirectoryItems(maps_dir)
                        for _, folder in ipairs(folders) do
                            local folder_path = maps_dir .. "/" .. folder
                            local info = love.filesystem.getInfo(folder_path)
                            if info and info.type == "directory" then
                                local files = love.filesystem.getDirectoryItems(folder_path)
                                maps[folder] = {}
                                for _, file in ipairs(files) do
                                    if file:match("%.osu$") then
                                        table.insert(maps[folder], file)
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

                                                        local function draw_text_with_outline(text, x, y)
                                                        local outline_color = {0, 0, 0, 1}
                                                        local text_color = {1, 1, 1, 1}

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
                                                                            local value = ""
                                                                            if option == "Music Volume" then
                                                                                value = math.floor(settings.music_volume * 100) .. "%"
                                                                                elseif option == "Resolution" then
                                                                                    local r = settings.resolutions[settings.resolution_index]
                                                                                    value = r[1].."x"..r[2]
                                                                                    elseif option == "Window Mode" then
                                                                                        value = settings.fullscreen_modes[settings.fullscreen_mode_index]
                                                                                        elseif option == "Lives" then
                                                                                            value = settings.lives
                                                                                            end
                                                                                            draw_text_with_outline(prefix .. option .. ": " .. value, 70, 80 + i * 30)
                                                                                            end
                                                                                            end

                                                                                            -- Функция для применения настроек видео
                                                                                            local function apply_video_settings()
                                                                                            local r = settings.resolutions[settings.resolution_index]
                                                                                            local fs_mode = settings.fullscreen_modes[settings.fullscreen_mode_index]
                                                                                            love.window.setMode(r[1], r[2], {
                                                                                                fullscreen = (fs_mode == "fullscreen"),
                                                                                                                borderless = (fs_mode == "borderless"),
                                                                                                                resizable = true
                                                                                            })
                                                                                            end

                                                                                            -- Функция для обработки клавиш в меню настроек
                                                                                            function handle_settings_key(key)
                                                                                            if key == "up" then
                                                                                                settings_selected_index = math.max(1, settings_selected_index - 1)
                                                                                                elseif key == "down" then
                                                                                                    settings_selected_index = math.min(#settings_options, settings_selected_index + 1)
                                                                                                    elseif key == "left" then
                                                                                                        if settings_options[settings_selected_index] == "Music Volume" then
                                                                                                            settings.music_volume = math.max(0, settings.music_volume - 0.05)
                                                                                                            elseif settings_options[settings_selected_index] == "Resolution" then
                                                                                                                settings.resolution_index = math.max(1, settings.resolution_index - 1)
                                                                                                                elseif settings_options[settings_selected_index] == "Window Mode" then
                                                                                                                    settings.fullscreen_mode_index = math.max(1, settings.fullscreen_mode_index - 1)
                                                                                                                    elseif settings_options[settings_selected_index] == "Lives" then
                                                                                                                        settings.lives = math.max(1, settings.lives - 1)
                                                                                                                        end
                                                                                                                        elseif key == "right" then
                                                                                                                            if settings_options[settings_selected_index] == "Music Volume" then
                                                                                                                                settings.music_volume = math.min(1, settings.music_volume + 0.05)
                                                                                                                                elseif settings_options[settings_selected_index] == "Resolution" then
                                                                                                                                    settings.resolution_index = math.min(#settings.resolutions, settings.resolution_index + 1)
                                                                                                                                    elseif settings_options[settings_selected_index] == "Window Mode" then
                                                                                                                                        settings.fullscreen_mode_index = math.min(#settings.fullscreen_modes, settings.fullscreen_mode_index + 1)
                                                                                                                                        elseif settings_options[settings_selected_index] == "Lives" then
                                                                                                                                            settings.lives = math.min(10, settings.lives + 1)
                                                                                                                                            end
                                                                                                                                            elseif key == "return" then
                                                                                                                                                if settings_options[settings_selected_index] == "Back" then
                                                                                                                                                    apply_video_settings() -- ПРИМЕНЯЕМ НАСТРОЙКИ
                                                                                                                                                    mode = "main_menu"
                                                                                                                                                    end
                                                                                                                                                    elseif key == "escape" then
                                                                                                                                                        apply_video_settings() -- ПРИМЕНЯЕМ НАСТРОЙКИ
                                                                                                                                                        mode = "main_menu"
                                                                                                                                                        end

                                                                                                                                                        -- Обновляем громкость немедленно (для обратной связи)
                                                                                                                                                        if menu_music then
                                                                                                                                                            menu_music:setVolume(settings.music_volume)
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
                                                                                                                                                                        draw_text_with_outline(prefix .. item, 70, 80 + i * 30)
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
                                                                                                                                                                                                        draw_text_with_outline(prefix .. folder, 70, 80 + i * 30)
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
                                                                                                                                                                                                                    draw_text_with_outline(prefix .. diff, 70, 80 + i * 30)
                                                                                                                                                                                                                    end

                                                                                                                                                                                                                    elseif mode == "gameplay" then
                                                                                                                                                                                                                        if game and game.draw then
                                                                                                                                                                                                                            game.draw()
                                                                                                                                                                                                                            else
                                                                                                                                                                                                                                draw_text_with_outline("Game started: " .. (selected_song or "") .. " - " .. (selected_difficulty or ""), 50, 50)
                                                                                                                                                                                                                                draw_text_with_outline("Press ESC to return to menu", 50, 80)
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                function love.update(dt)
                                                                                                                                                                                                                                if mode == "gameplay" and game and game.update then
                                                                                                                                                                                                                                    local status = game.update(dt) -- Получаем статус из game.lua
                                                                                                                                                                                                                                    if status == "game_over" then -- Если игра окончена
                                                                                                                                                                                                                                        mode = "main_menu" -- Переходим в главное меню
                                                                                                                                                                                                                                        selected_index = 1
                                                                                                                                                                                                                                        game = nil -- Сбрасываем модуль игры

                                                                                                                                                                                                                                        -- *** ИСПРАВЛЕНИЕ: Возобновляем музыку меню ***
                                                                                                                                                                                                                                        if menu_music and not menu_music:isPlaying() then
                                                                                                                                                                                                                                            menu_music:play()
                                                                                                                                                                                                                                            end
                                                                                                                                                                                                                                            end
                                                                                                                                                                                                                                            end
                                                                                                                                                                                                                                            end

                                                                                                                                                                                                                                            function love.keypressed(key)
                                                                                                                                                                                                                                            if mode == "main_menu" then
                                                                                                                                                                                                                                                if key == "up" then
                                                                                                                                                                                                                                                    selected_index = math.max(1, selected_index - 1)
                                                                                                                                                                                                                                                    elseif key == "down" then
                                                                                                                                                                                                                                                        selected_index = math.min(#main_menu_items, selected_index + 1)
                                                                                                                                                                                                                                                        elseif key == "return" then
                                                                                                                                                                                                                                                            local choice = main_menu_items[selected_index]
                                                                                                                                                                                                                                                            if choice == "osu-mode" then
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                mode = "osu_menu"
                                                                                                                                                                                                                                                                elseif choice == "Settings" then
                                                                                                                                                                                                                                                                settings_selected_index = 1
                                                                                                                                                                                                                                                                mode = "settings"
                                                                                                                                                                                                                                                                elseif choice == "Exit" then
                                                                                                                                                                                                                                                                love.event.quit()
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif mode == "settings" then
                                                                                                                                                                                                                                                                handle_settings_key(key)

                                                                                                                                                                                                                                                                elseif mode == "osu_menu" then
                                                                                                                                                                                                                                                                local keys = get_song_list()
                                                                                                                                                                                                                                                                if #keys > 0 then
                                                                                                                                                                                                                                                                if key == "up" then
                                                                                                                                                                                                                                                                selected_index = math.max(1, selected_index - 1)
                                                                                                                                                                                                                                                                elseif key == "down" then
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
                                                                                                                                                                                                                                                                if key == "up" then
                                                                                                                                                                                                                                                                selected_index = math.max(1, selected_index - 1)
                                                                                                                                                                                                                                                                elseif key == "down" then
                                                                                                                                                                                                                                                                selected_index = math.min(#difficulties, selected_index + 1)
                                                                                                                                                                                                                                                                elseif key == "return" then
                                                                                                                                                                                                                                                                selected_difficulty = difficulties[selected_index]

                                                                                                                                                                                                                                                                -- *** ИСПРАВЛЕНИЕ: ОСТАНОВКА МУЗЫКИ МЕНЮ ***
                                                                                                                                                                                                                                                                if menu_music and menu_music:isPlaying() then
                                                                                                                                                                                                                                                                menu_music:stop()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                -- Загрузка и инициализация игры
                                                                                                                                                                                                                                                                game = require("game")
                                                                                                                                                                                                                                                                game.load(selected_song, selected_difficulty)

                                                                                                                                                                                                                                                                mode = "gameplay"
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                if key == "escape" then
                                                                                                                                                                                                                                                                mode = "osu_menu"
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif mode == "gameplay" then
                                                                                                                                                                                                                                                                if key == "escape" then
                                                                                                                                                                                                                                                                if game and game.stopMusic then game.stopMusic() end
                                                                                                                                                                                                                                                                mode = "main_menu"
                                                                                                                                                                                                                                                                selected_index = 1
                                                                                                                                                                                                                                                                game = nil -- Сбрасываем модуль игры

                                                                                                                                                                                                                                                                -- *** ИСПРАВЛЕНИЕ: Возобновляем музыку меню ***
                                                                                                                                                                                                                                                                if menu_music and not menu_music:isPlaying() then
                                                                                                                                                                                                                                                                menu_music:play()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif game and game.keypressed then
                                                                                                                                                                                                                                                                game.keypressed(key)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
