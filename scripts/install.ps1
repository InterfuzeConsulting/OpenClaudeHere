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
$iconFile     = Join-Path $repoRoot 'assets\claude-workspace.ico'
$menuLabel    = 'Open Claude Workspace Here (5 tabs)'
$menuKey      = 'OpenWezTermClaude'
$apiMenuLabel = 'Open Claude Workspace Here (5 tabs on API Key)'
$apiMenuKey   = 'OpenWezTermClaudeApiKey'

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

# Two menu items, each registered under both context-menu roots:
#   - default 5-tab item            (login auth)
#   - "(5 tabs on API Key)" variant (adds -UseApiKey to the launch command)
$menus = @(
    @{ Key = $menuKey;    Label = $menuLabel;    ExtraArgs = '' },
    @{ Key = $apiMenuKey; Label = $apiMenuLabel; ExtraArgs = ' -UseApiKey' }
)

$roots = @(
    @{ Base = 'HKCU:\Software\Classes\Directory\shell';            Token = '%1' },  # right-click a folder
    @{ Base = 'HKCU:\Software\Classes\Directory\Background\shell'; Token = '%V' }   # right-click inside a folder
)

foreach ($menu in $menus) {
    foreach ($root in $roots) {
        $regKey   = "$($root.Base)\$($menu.Key)"
        $cmdKey   = "$regKey\command"
        $cmdValue = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launchScript`" -TargetDir `"$($root.Token)`"$($menu.ExtraArgs)"

        # Create/overwrite parent key, set default value (label), Icon, and Position
        New-Item -Path $regKey -Force | Out-Null
        Set-Item -Path $regKey -Value $menu.Label
        New-ItemProperty -Path $regKey -Name 'Icon'     -Value $iconFile -Force | Out-Null
        New-ItemProperty -Path $regKey -Name 'Position' -Value 'Top'     -Force | Out-Null

        # Create/overwrite command subkey
        New-Item -Path $cmdKey -Force | Out-Null
        Set-Item -Path $cmdKey -Value $cmdValue

        Write-Host "[OK] Registered: $regKey"
    }
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
$shortcut.IconLocation = "$iconFile,0"
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
Write-Host "Menu label     : $apiMenuLabel"
Write-Host ''
Write-Host 'Right-click any folder (or folder background) in Explorer and choose:'
Write-Host "  - ""$menuLabel"" to open 5 Claude tabs (login auth)."
Write-Host "  - ""$apiMenuLabel"" to open 5 tabs that"
Write-Host '    authenticate with an Anthropic API key. The first launch prompts for'
Write-Host '    the key and stores it encrypted; later launches reuse it. Delete'
Write-Host '    config\api-key.dat to rotate/clear it.'
Write-Host ''
Write-Host "To uninstall   : powershell -ExecutionPolicy Bypass -File ""$uninstallScript"""
