@echo off
rem =============================================================
rem dc/gpo/logon.cmd - Script de inicio de sesion del dominio
rem Ejecutado por Windows en cada login (via atributo scriptPath
rem del AD). Aplica el wallpaper y abre la web del equipo.
rem =============================================================

echo %date% %time% %USERDOMAIN%\%USERNAME% >> "%USERPROFILE%\logon-debug.txt"

rem --- 1) Aplicar wallpaper (helper PS: SystemParametersInfo, funciona en Win10) ---
powershell.exe -NoProfile -ExecutionPolicy Bypass ^
    -File "\\dc1.sudoers.lan\NETLOGON\wallpaper.ps1"

rem --- 2) Abrir la web de la organizacion ---
start "" "http://www.sudoers.lan"