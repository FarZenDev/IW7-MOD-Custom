@echo off
setlocal EnableDelayedExpansion
title IW7-Mod EasyMP
cd /d "%~dp0"

set "REPO=https://raw.githubusercontent.com/FarZenDev/IW7-MOD-Custom/main/bin"

echo Verification des mises a jour...

rem --- recupere la version distante ---
set "REMOTE="
curl -L -s -o "%TEMP%\iw7_ver.txt" "%REPO%/version.txt" 2>nul
if exist "%TEMP%\iw7_ver.txt" set /p REMOTE=<"%TEMP%\iw7_ver.txt"

rem --- version locale ---
set "LOCAL="
if exist "iw7-mod.version" set /p LOCAL=<"iw7-mod.version"

rem --- telecharge l'exe seulement si la version a change (ou s'il manque) ---
if not defined REMOTE (
    echo [!] Pas d'internet ou GitHub injoignable, lancement de la version locale.
) else if not "%REMOTE%"=="%LOCAL%" (
    echo Mise a jour de IW7-Mod EasyMP vers %REMOTE%...
    curl -L -s -o "iw7-mod.exe.new" "%REPO%/iw7-mod.exe" 2>nul
    if exist "iw7-mod.exe.new" (
        move /Y "iw7-mod.exe.new" "iw7-mod.exe" >nul
        >"iw7-mod.version" echo %REMOTE%
        echo A jour !
    ) else (
        echo [!] Echec du telechargement, lancement de la version actuelle.
    )
) else (
    echo Deja a jour.
)

if not exist "iw7-mod.exe" (
    echo [ERREUR] iw7-mod.exe introuvable et telechargement impossible.
    pause
    exit /b 1
)

echo Lancement...
start "" "iw7-mod.exe" -nosteam
exit
