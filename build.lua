return {
    name = "RhythmHell",           -- имя exe-файла
    developer = "WeedSoft",        -- твой ник или "студия"
    output = "dist",               -- папка для билда
    version = "1.0",               -- версия игры
    love = "11.5",                 -- версия LÖVE (совместимая)
    icon = "res/images/menu.png",  -- можешь сменить на свой icon.png, или удалить
    ignore = {"dist", ".git", ".vscode", "temp"},
    platforms = {"windows"},       -- собираем только под винду
}
