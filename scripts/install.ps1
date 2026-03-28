#Requires -Version 5.1
<#
.SYNOPSIS
    One-time (idempotent) setup for the portable WezTerm + Claude workspace.

.DESCRIPTION
    1. Downloads the portable WezTerm zip from GitHub and extracts it to bin\.
    2. Registers a right-click context menu entry in HKCU (no admin required):
       - "Directory\shell"            -> appears when right-clicking a folder
       - "Directory\Background\shell" -> appears when right-clicking inside a folder
    3. Warns if claude is not found on PATH.

    Safe to re-run: binary download is skipped if bin\wezterm.exe already exists.
    Registry keys are always written/overwritten to ensure they point to the
    current repo location (useful after moving the folder).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Paths
# =============================================================================

$repoRoot     = Split-Path $PSScriptRoot -Parent
$binDir       = Join-Path $repoRoot 'bin'
$weztermExe   = Join-Path $binDir   'wezterm.exe'
$configFile   = Join-Path $repoRoot 'config\wezterm.lua'
$launchScript = Join-Path $repoRoot 'scripts\launch-claude.ps1'
$menuLabel    = 'Open Claude Workspace Here (5 tabs)'
$menuKey      = 'OpenWezTermClaude'

# =============================================================================
# Step 1: Create bin\
# =============================================================================

if (-not (Test-Path $binDir)) {
    New-Item -Path $binDir -ItemType Directory -Force | Out-Null
    Write-Host '[OK] Created bin\'
}

# =============================================================================
# Step 2: Download + extract portable WezTerm
# =============================================================================

if (Test-Path $weztermExe) {
    Write-Host '[SKIP] bin\wezterm.exe already exists -- skipping download.'
    Write-Host '       Delete bin\ and re-run to force a fresh download.'
} else {
    Write-Host '[....] Fetching latest WezTerm release metadata from GitHub...'

    $headers = @{ 'User-Agent' = 'portable-wezterm-installer' }
    $release = Invoke-RestMethod `
        -Uri     'https://api.github.com/repos/wez/wezterm/releases/latest' `
        -Headers $headers

    $tagName = $release.tag_name

    # Asset name is WezTerm-windows-<datestamp>-<hash>.zip (no "-portable-" segment)
    $asset = $release.assets | Where-Object {
        $_.name -like 'WezTerm-windows-*.zip' -and $_.name -notlike '*.sha256'
    } | Select-Object -First 1

    if (-not $asset) {
        $assetList = ($release.assets | Select-Object -ExpandProperty name) -join "`n"
        Write-Error "Could not find a Windows zip asset in release $tagName. Assets available:`n$assetList"
        exit 1
    }

    $sizeMB = [math]::Round($asset.size / 1MB, 1)
    Write-Host "[....] Downloading $($asset.name) ($sizeMB MB)..."

    $zipPath    = Join-Path $env:TEMP 'wezterm-portable.zip'
    $stagingDir = Join-Path $env:TEMP 'wezterm-extract'

    Invoke-WebRequest `
        -Uri     $asset.browser_download_url `
        -OutFile $zipPath `
        -UseBasicParsing

    Write-Host '[....] Extracting...'

    if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $stagingDir -Force

    # The zip contains one top-level subfolder (e.g. WezTerm-windows-<tag>\)
    $subFolder = Get-ChildItem $stagingDir -Directory | Select-Object -First 1
    if (-not $subFolder) {
        # Fallback: zip was flat -- copy directly
        $subFolder = Get-Item $stagingDir
    }

    # Move everything (exe, DLLs, mesa\, etc.) into bin\
    Get-ChildItem $subFolder.FullName | ForEach-Object {
        Move-Item $_.FullName -Destination $binDir -Force
    }

    # Clean up temp files
    Remove-Item $zipPath    -Force -ErrorAction SilentlyContinue
    Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "[OK] WezTerm $tagName extracted to bin\"
}

# =============================================================================
# Step 3: Check for Claude CLI
# =============================================================================

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning 'claude not found on PATH. Install it with: npm install -g @anthropic-ai/claude-code'
} else {
    Write-Host '[OK] claude found on PATH.'
}

# =============================================================================
# Step 4: Write registry context menu entries
#
# %1 = selected folder path  (Directory\shell)
# %V = current folder path   (Directory\Background\shell)
#
# Key structure:
#   HKCU:\Software\Classes\<root>\shell\<key>
#       (default) = "<menu label>"
#       Icon      = "<path to wezterm.exe>"
#   HKCU:\Software\Classes\<root>\shell\<key>\command
#       (default) = "powershell.exe ... -TargetDir <token>"
# =============================================================================

$entries = @(
    @{
        Root  = "HKCU:\Software\Classes\Directory\shell\$menuKey"
        Token = '%1'
    },
    @{
        Root  = "HKCU:\Software\Classes\Directory\Background\shell\$menuKey"
        Token = '%V'
    }
)

foreach ($entry in $entries) {
    $cmdValue = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launchScript`" -TargetDir `"$($entry.Token)`""
    $cmdKey   = "$($entry.Root)\command"

    # Create/overwrite parent key, set default value (label), Icon, and Position
    New-Item -Path $entry.Root -Force | Out-Null
    Set-Item -Path $entry.Root -Value $menuLabel
    New-ItemProperty -Path $entry.Root -Name 'Icon'     -Value $weztermExe -Force | Out-Null
    New-ItemProperty -Path $entry.Root -Name 'Position' -Value 'Top'       -Force | Out-Null

    # Create/overwrite command subkey
    New-Item -Path $cmdKey -Force | Out-Null
    Set-Item -Path $cmdKey -Value $cmdValue

    Write-Host "[OK] Registered: $($entry.Root)"
}

# =============================================================================
# Step 5: Create pinnable taskbar shortcut
# =============================================================================

$shortcutPath   = Join-Path $repoRoot 'Launch Claude Workspace.lnk'
$pickScript     = Join-Path $repoRoot 'scripts\pick-and-launch.ps1'

$wsh      = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath   = 'powershell.exe'
$shortcut.Arguments    = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$pickScript`""
$shortcut.IconLocation = "$weztermExe,0"
$shortcut.Description  = 'Pick a folder and open it as a Claude workspace'
$shortcut.Save()

Write-Host "[OK] Shortcut created: $shortcutPath"
Write-Host "     Right-click it and choose 'Pin to taskbar' to add it to your taskbar."

# =============================================================================
# Done
# =============================================================================

$uninstallScript = Join-Path $repoRoot 'scripts\uninstall.ps1'

Write-Host ''
Write-Host '=== Installation Complete ==='
Write-Host "WezTerm binary : $weztermExe"
Write-Host "Config file    : $configFile"
Write-Host "Launch script  : $launchScript"
Write-Host "Menu label     : $menuLabel"
Write-Host ''
Write-Host 'Right-click any folder (or folder background) in Explorer and'
Write-Host "choose ""$menuLabel"" to open 5 Claude tabs."
Write-Host ''
Write-Host "To uninstall   : powershell -ExecutionPolicy Bypass -File ""$uninstallScript"""
