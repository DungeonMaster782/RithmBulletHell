local console = {}
console.isOpen = false
console.history = {}
console.cmdHistory = {}
console.historyPos = 0
console.input = ""
-- Support for different Lua versions (5.1/JIT vs 5.2+)
local load_code = loadstring or load

function console.load()
    -- Intercept print to send output to console history
    local old_print = print
    print = function(...)
        local args = {...}
        local str = ""
        for i, v in ipairs(args) do
            str = str .. tostring(v) .. (i < #args and "\t" or "")
        end
        
        -- Проверяем валидность UTF-8, чтобы избежать краша при отрисовке
        if love.utf8 and not love.utf8.len(str) then
            str = "[Invalid UTF-8 Data]"
        end
        
        table.insert(console.history, str)
        if #console.history > 50 then table.remove(console.history, 1) end
        old_print(...)
    end
end

function console.toggle()
    console.isOpen = not console.isOpen
    love.keyboard.setKeyRepeat(console.isOpen)
    
    if console.isOpen and _G.game and _G.game.pause then
        _G.game.pause()
    end
end

function console.keypressed(key)
    if key == "`" then
        console.toggle()
        return true
    end
    
    if not console.isOpen then return false end
    
    if key == "up" then
        if #console.cmdHistory > 0 then
            if console.historyPos < #console.cmdHistory then
                console.historyPos = console.historyPos + 1
                console.input = console.cmdHistory[#console.cmdHistory - console.historyPos + 1]
            end
        end
        return true
    elseif key == "down" then
        if console.historyPos > 0 then
            console.historyPos = console.historyPos - 1
            if console.historyPos == 0 then
                console.input = ""
            else
                console.input = console.cmdHistory[#console.cmdHistory - console.historyPos + 1]
            end
        end
        return true
    elseif key == "tab" then
        local str = console.input
        local s, e = str:find("[%w_%.]+$")
        if s then
            local word = str:sub(s, e)
            local parts = {}
            for p in word:gmatch("[^%.]+") do table.insert(parts, p) end
            
            local t = _G
            local prefix = word
            
            if word:find("%.") then
                local limit = #parts
                if word:sub(-1) ~= "." then limit = limit - 1 end
                
                for i=1, limit do
                    if t[parts[i]] and type(t[parts[i]]) == "table" then
                        t = t[parts[i]]
                    else
                        t = nil
                        break
                    end
                end
                
                if word:sub(-1) == "." then prefix = "" else prefix = parts[#parts] end
            end
            
            if t then
                local matches = {}
                for k,v in pairs(t) do
                    if type(k) == "string" and k:find("^" .. prefix) then
                        table.insert(matches, k)
                    end
                end
                if #matches == 1 then
                    console.input = console.input .. matches[1]:sub(#prefix + 1)
                elseif #matches > 1 then
                    table.sort(matches)
                    print("Candidates: " .. table.concat(matches, " "))
                end
            end
        end
        return true
    elseif key == "return" or key == "kpenter" then
        if console.input ~= "" then
            if #console.cmdHistory == 0 or console.cmdHistory[#console.cmdHistory] ~= console.input then
                table.insert(console.cmdHistory, console.input)
            end
            console.historyPos = 0
            print("> " .. console.input)
            if console.input == "help" then
                print("DESCRIPTION")
                print("    Execute Lua code and modify game state in real-time.")
                print("")
                print("COMMANDS")
                print("    god:true/false  - Enable/Disable God Mode")
                print("    lives:N         - Set lives")
                print("    speed:N         - Set player speed multiplier")
                print("    help    - Display this manual.")
                print("    clear   - Clear console history.")
                print("")
                print("GLOBALS")
                print("    settings           - Game configuration (lives, speed, etc.)")
                print("    require('player')  - Player object (lives, x, y, invuln)")
                print("")
            elseif console.input == "clear" then
                console.history = {}
            else
                -- Simple command parser
                local cmd, arg = console.input:match("^([%w_]+):(.+)$")
                local simple_executed = false
                
                if cmd then
                    if cmd == "god" then
                        local p = require("player")
                        if arg == "true" then
                            p.invuln = true
                            p.invuln_timer = math.huge
                            print("God Mode: ENABLED")
                        elseif arg == "false" then
                            p.invuln = false
                            p.invuln_timer = 0
                            print("God Mode: DISABLED")
                        else
                            print("Usage: god:true or god:false")
                        end
                        simple_executed = true
                    elseif cmd == "lives" then
                        local n = tonumber(arg)
                        if n then
                            require("player").lives = n
                            print("Lives set to " .. n)
                        else
                            print("Usage: lives:<number>")
                        end
                        simple_executed = true
                    elseif cmd == "speed" then
                        local n = tonumber(arg)
                        if n then
                            local p = require("player")
                            p.speed = 200 * n
                            print("Player speed set to " .. n .. "x")
                        else
                            print("Usage: speed:<number>")
                        end
                        simple_executed = true
                    end
                end

                if not simple_executed then
                    -- Try to execute as code
                    local fn, err = load_code(console.input)
                    if not fn then fn, err = load_code("return " .. console.input) end
                    
                    if fn then
                        -- Execute in protected mode
                        local ok, res = pcall(fn)
                        if ok then
                            if res ~= nil then print(tostring(res)) end
                        else
                            print("Error: " .. tostring(res))
                        end
                    else
                        print("Syntax Error: " .. tostring(err))
                    end
                end
            end
            console.input = ""
        end
    elseif key == "backspace" then
        local byteoffset = nil
        -- Пытаемся использовать love.utf8 для корректного удаления символа
        if love.utf8 then
            local status, offset = pcall(love.utf8.offset, console.input, -1)
            if status then
                byteoffset = offset
            end
        end
        
        if byteoffset then
            console.input = string.sub(console.input, 1, byteoffset - 1)
        else
            -- Ручная реализация backspace для UTF-8 (если love.utf8 недоступен или сбойнул)
            local len = #console.input
            if len > 0 then
                local i = len
                -- Пропускаем байты продолжения (10xxxxxx, т.е. 128-191), пока не найдем начало символа
                while i > 1 and (string.byte(console.input, i) >= 128 and string.byte(console.input, i) <= 191) do
                    i = i - 1
                end
                console.input = string.sub(console.input, 1, i - 1)
            end
        end
    end
    
    return true -- Block input for the rest of the game
end

function console.textinput(t)
    if console.isOpen and t ~= "`" then
        console.input = console.input .. t
    end
end

function console.draw()
    if not console.isOpen then return end
    
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()
    local ch = h * 0.4 -- Console height (40% of screen)
    local y_start = h - ch
    
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 0, y_start, w, ch)
    
    love.graphics.setColor(0, 1, 0, 1)
    love.graphics.line(0, y_start, w, y_start)
    
    local font = love.graphics.getFont()
    local fh = font:getHeight()
    
    -- Input line
    love.graphics.print("> " .. console.input .. "_", 10, h - fh - 5)
    
    -- History
    local y = h - fh - 5 - fh
    for i = #console.history, 1, -1 do
        if y < y_start then break end
        love.graphics.print(console.history[i], 10, y)
        y = y - fh
    end
end

return console