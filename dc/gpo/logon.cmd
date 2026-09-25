@echo off
rem =============================================================
rem dc/gpo/logon.cmd - Script de inicio de sesion del dominio
rem Ejecutado por Windows en cada login (via atributo scriptPath
rem del AD). Aplica el wallpaper, instala la CA de confianza
rem y abre la web del equipo.
rem =============================================================

rem --- 1) Aplicar wallpaper (helper PS: SystemParametersInfo, funciona en Win10) ---
powershell.exe -NoProfile -ExecutionPolicy Bypass ^
    -File "\\dc1.sudoers.lan\NETLOGON\wallpaper.ps1"

rem --- 2) Instalar CA interna silenciosamente (solo si no esta instalada aun) ---
rem     Instala en CurrentUser\Root: no requiere admin local.
rem     Idempotente: si ya existe el certificado, no hace nada.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "$cert = '\\\\dc1.sudoers.lan\\NETLOGON\\ca.crt'; if (Test-Path $cert) { $thumb = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $cert).Thumbprint; $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root','CurrentUser'); $store.Open('ReadWrite'); if (-not ($store.Certificates | Where-Object { $_.Thumbprint -eq $thumb })) { $store.Add((New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $cert)) }; $store.Close() }"

rem --- 3) Abrir la web de la organizacion (Edge explicito) ---
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" (
    start "" "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" "https://www.sudoers.lan"
) else (
    start "" msedge "https://www.sudoers.lan"
)