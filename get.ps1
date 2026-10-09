# get.ps1 - ArtCraft bootstrap.
#
# Paste this into CMD or PowerShell:
#   powershell -c "iwr -UseBasicParsing https://saltymaud.github.io/ArtcraftInstaller/get.ps1 -OutFile $env:TEMP\get.ps1; & $env:TEMP\get.ps1"
#
# It lands the installer + launchers in the ArtCraft folder and starts the installer.
# Everything after this is handled by install-artcraft.ps1 (self-updating from GitHub).

param([string]$Folder = "$env:SystemDrive\Artcraft")

$repo = 'https://raw.githubusercontent.com/SaltyMaud/ArtcraftInstaller/main'

Write-Host 'Setting up ArtCraft...' -ForegroundColor Cyan
try {
    New-Item -ItemType Directory -Path $Folder -Force -ErrorAction Stop | Out-Null
    foreach ($f in 'install-artcraft.ps1', 'install-artcraft.bat', 'update-artcraft.bat') {
        Invoke-WebRequest -UseBasicParsing -Uri "$repo/$f" -OutFile (Join-Path $Folder $f) -Headers @{ 'User-Agent' = 'artcraft-bootstrap' }
    }
} catch {
    Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Check your internet connection, or download the files from'
    Write-Host "$repo and run install-artcraft.ps1 yourself." -ForegroundColor Yellow
    exit 1
}

Write-Host "ArtCraft is set up in $Folder - launching the installer..." -ForegroundColor Green
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Folder 'install-artcraft.ps1')
