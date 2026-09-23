@echo off
rem =============================================================
rem dc/gpo/logon.cmd - Script de inicio de sesion del dominio
rem Ejecutado por Windows en cada login (via atributo scriptPath
rem del AD). Aplica el wallpaper y abre la web del equipo.
rem =============================================================

echo %date% %time% %USERDOMAIN%\%USERNAME% >> "%USERPROFILE%\logon-debug.txt"

set "WALL=%USERPROFILE%\Pictures\ooo-wall.jpg"

rem --- 1) Bajar el fondo si aun no lo tiene el perfil ---
if not exist "%WALL%" (
    copy /y "\\dc1.sudoers.lan\NETLOGON\ooo-wall.jpg" "%WALL%" >nul
)

rem --- 2) Aplicar wallpaper (centro del control de Samba) ---
reg add "HKCU\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "%WALL%" /f >nul
reg add "HKCU\Control Panel\Desktop" /v WallpaperStyle /t REG_SZ /d "10" /f >nul
reg add "HKCU\Control Panel\Desktop" /v TileWallpaper /t REG_SZ /d "0" /f >nul

rem --- 3) Forzar el refresco sin reiniciar ---
rundll32.exe user32.dll,UpdatePerUserSystemParameters

rem --- 4) Abrir la web de la organizacion ---
start "" "http://www.sudoers.lan"