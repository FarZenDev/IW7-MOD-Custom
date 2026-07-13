@echo off
setlocal EnableDelayedExpansion
title Installation IW7-Mod EasyMP
cd /d "%~dp0"
echo ==========================================================
echo   IW7-Mod EasyMP - Installation (une seule fois)
echo ==========================================================
echo.

rem --- localiser le jeu ---
set "GAMEDIR=C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Infinite Warfare"
if exist "%GAMEDIR%\iw7_ship.exe" goto found
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

rem --- telecharger le lanceur auto-updatable dans le dossier du jeu ---
echo Telechargement du lanceur...
curl -L -s -o "%GAMEDIR%\IW7-EasyMP.bat" "https://raw.githubusercontent.com/FarZenDev/IW7-MOD-Custom/main/IW7-EasyMP.bat"
if not exist "%GAMEDIR%\IW7-EasyMP.bat" (
    echo [ERREUR] Impossible de telecharger le lanceur (verifiez internet).
    pause
    exit /b 1
)
echo [OK] Lanceur installe.

rem --- memoriser le chemin du jeu (pour jouer sans Steam) ---
>"%GAMEDIR%\steam_path.txt" echo %GAMEDIR%
echo [OK] Chemin du jeu memorise.

rem --- raccourci sur le bureau ---
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop')+'\IW7-Mod EasyMP.lnk'); $s.TargetPath='%GAMEDIR%\IW7-EasyMP.bat'; $s.WorkingDirectory='%GAMEDIR%'; $s.IconLocation='%GAMEDIR%\iw7_ship.exe,0'; $s.Save()"
echo [OK] Raccourci "IW7-Mod EasyMP" cree sur le bureau.
echo.
echo ==========================================================
echo   Installation terminee !
echo.
echo   Lancez le jeu via le raccourci "IW7-Mod EasyMP"
echo   sur votre bureau. Il met tout a jour automatiquement
echo   (jeu + menus) a chaque lancement, sans Steam.
echo ==========================================================
pause
