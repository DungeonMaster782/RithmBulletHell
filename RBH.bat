@echo off
setlocal

:: Перечисляем исходники и соответствующие классы
set SOURCES=Main.java MainMenu.java Config.java Game.java
set CLASSES=Main.class MainMenu.class Config.class Game.class

:: Флаг, указывающий, что нужна компиляция
set NEED_COMPILE=false

:: Проверяем, что все .class-файлы существуют
for %%F in (%CLASSES%) do (
    if not exist "%%~F" (
        set NEED_COMPILE=true
    )
)

if "%NEED_COMPILE%"=="true" (
    echo Компиляция исходников...
    javac -encoding UTF-8 %SOURCES%
    if errorlevel 1 (
        echo ОШИБКА: Компиляция не удалась.
        pause
        exit /b 1
    )
) else (
    echo Все файлы уже скомпилированы. Пропускаем компиляцию.
)

echo Запуск игры...
java Main

endlocal
