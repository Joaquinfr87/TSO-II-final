# dc/gpo/wallpaper.ps1 — Aplica el wallpaper del dominio usando la API
# oficial SystemParametersInfo (SPI_SETDESKWALLPAPER), que es lo que
# refresca el fondo en Windows 10/11 (el truco de rundll32 no alcanza).
# Lo invoca logon.cmd al inicio de sesión del usuario.

param()

$netlogonUrl = "\\dc1.sudoers.lan\NETLOGON\ooo-wall.jpg"
$wallDir     = Join-Path $env:USERPROFILE "Pictures"
$wallFile    = Join-Path $wallDir "ooo-wall.jpg"

if (-not (Test-Path $wallDir)) {
    New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
}

if (Test-Path $netlogonUrl) {
    Copy-Item -Path $netlogonUrl -Destination $wallFile -Force
}

$reg = "HKCU:\Control Panel\Desktop"
New-ItemProperty -Path $reg -Name "Wallpaper"      -PropertyType String -Value $wallFile -Force | Out-Null
New-ItemProperty -Path $reg -Name "WallpaperStyle" -PropertyType String -Value "10"       -Force | Out-Null
New-ItemProperty -Path $reg -Name "TileWallpaper"  -PropertyType String -Value "0"        -Force | Out-Null

Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class WallSetter {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool SystemParametersInfo(uint uAction, uint uParam, string lpvParam, uint fuWinIni);
}
'@

# SPI_SETDESKWALLPAPER (20), fuWinIni = SPIF_UPDATEINIFILE|SPIF_SENDCHANGE (3)
[WallSetter]::SystemParametersInfo(20, 0, $wallFile, 3) | Out-Null