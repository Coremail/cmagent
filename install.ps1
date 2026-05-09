# cmagent installer for Windows (PowerShell).
#
# Usage (run in PowerShell as normal user):
#   irm https://raw.githubusercontent.com/Coremail/cmagent/main/install.ps1 | iex
#
# Installs cmagent.exe to %LOCALAPPDATA%\cmagent and adds it to the user PATH.

$ErrorActionPreference = "Stop"

$Repo      = "Coremail/cmagent"
$BinName   = "cmagent.exe"
$InstallDir = "$env:LOCALAPPDATA\cmagent"
$Archive   = "cmagent-windows-x86_64.zip"
$Url       = "https://github.com/$Repo/releases/latest/download/$Archive"

function Say { Write-Host $args[0] -ForegroundColor Cyan }
function Err { Write-Host "ERROR: $($args[0])" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# Check arch
# ---------------------------------------------------------------------------
if ($env:PROCESSOR_ARCHITECTURE -notmatch "AMD64|x86_64") {
    Err "Only x86_64 Windows is supported. Download manually from https://github.com/$Repo/releases"
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
Say "Downloading cmagent (windows-x86_64)..."

$TmpDir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $TmpDir | Out-Null

try {
    $TmpZip = "$TmpDir\$Archive"
    Invoke-WebRequest -Uri $Url -OutFile $TmpZip -UseBasicParsing

    # ---------------------------------------------------------------------------
    # Install
    # ---------------------------------------------------------------------------
    Say "Installing to $InstallDir..."
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Expand-Archive -Path $TmpZip -DestinationPath $TmpDir -Force
    Copy-Item "$TmpDir\$BinName" "$InstallDir\$BinName" -Force

    # ---------------------------------------------------------------------------
    # Add to user PATH if not already present
    # ---------------------------------------------------------------------------
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($UserPath -notlike "*$InstallDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$InstallDir;$UserPath", "User")
        Say "Added $InstallDir to your user PATH."
        Say "Restart your terminal for the PATH change to take effect."
    }

    Say "cmagent installed to $InstallDir\$BinName"
    Write-Host ""
    Write-Host "Run 'cmagent --help' to get started." -ForegroundColor Green

} finally {
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}
