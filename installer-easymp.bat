@echo off
setlocal EnableDelayedExpansion
title Installation IW7-Mod EasyMP
echo ==========================================================
echo   IW7-Mod EasyMP - Installation
echo ==========================================================
echo.

rem -- locate the compiled client
set "EXE=%~dp0build\bin\x64\Release\iw7-mod.exe"
if not exist "%EXE%" (
    echo [ERREUR] iw7-mod.exe introuvable. Compilez d'abord le projet:
    echo    generate.bat puis build\iw7-mod.sln en Release x64
    pause
    exit /b 1
)

rem -- locate the game folder
set "GAMEDIR=C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Infinite Warfare"
if exist "%GAMEDIR%\iw7_ship.exe" goto :found

echo Dossier Steam par defaut introuvable.
set /p GAMEDIR="Chemin du dossier Call of Duty Infinite Warfare: "
if not exist "%GAMEDIR%\iw7_ship.exe" (
    echo [ERREUR] iw7_ship.exe introuvable dans ce dossier.
    pause
    exit /b 1
)

:found
echo [OK] Jeu trouve: %GAMEDIR%
echo.

rem -- install the client
copy /Y "%EXE%" "%GAMEDIR%\iw7-mod.exe" >nul
echo [OK] iw7-mod.exe (version EasyMP) copie dans le dossier du jeu.

rem -- install the UI scripts and client data
set "CDATA=%LOCALAPPDATA%\auroramod\iw7-mod\cdata"
xcopy /E /Y /I /Q "%~dp0data\cdata" "%CDATA%" >nul
echo [OK] Scripts d'interface copies dans %CDATA%

rem -- record the game path so the client finds the game files even if Steam is closed
> "%GAMEDIR%\steam_path.txt" echo %GAMEDIR%
echo [OK] steam_path.txt ecrit (chemin du jeu memorise).
echo.
echo ==========================================================
echo   Installation terminee !
echo.
echo   Lancez iw7-mod.exe : Steam n'a PAS besoin d'etre ouvert.
echo   (Pour forcer l'ancien mode Steam: iw7-mod.exe -steam)
echo.
echo   Le bouton "JOUER ENTRE AMIS" est dans les menus
echo   MULTIJOUEUR et ZOMBIES.
echo ==========================================================
pause
