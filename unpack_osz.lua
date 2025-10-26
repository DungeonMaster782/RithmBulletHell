package.path = package.path .. ";/home/master/.luarocks/share/lua/5.4/?.lua;/home/master/.luarocks/share/lua/5.4/?/init.lua"
package.cpath = package.cpath .. ";/home/master/.luarocks/lib/lua/5.4/?.so"
local map_osz = arg[1]

if not map_osz then
    print("Usage: lua unpack_osz.lua <map.osz>")
    os.exit(1)
end

local lfs = require("lfs")

local function mkdir_p(path)
    local current = ""
    for dir in path:gmatch("[^/]+") do
        current = current .. dir .. "/"
        lfs.mkdir(current)
    end
end

-- Получаем имя карты без расширения
local folder_name = map_osz:match("([^/\\]+)%.osz$")
if not folder_name then
    print("Bad filename")
    os.exit(1)
end

local target_dir = "maps/" .. folder_name

mkdir_p("maps")
mkdir_p(target_dir)

local cmd = string.format("unzip -o '%s' -d '%s'", map_osz, target_dir)
print("Running: " .. cmd)
os.execute(cmd)
print("Done unpacking to " .. target_dir)
