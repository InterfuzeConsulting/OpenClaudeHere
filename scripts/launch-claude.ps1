#Requires -Version 5.1
<#
.SYNOPSIS
    Opens a portable WezTerm window with 5 Claude tabs over a target directory.

.DESCRIPTION
    Called by the Explorer context menu ("Open Claude Workspace Here").

    Tab layout:
        1 -- Sonnet 1  (claude-sonnet-4-6)          <- active on open
        2 -- Sonnet 2  (claude-sonnet-4-6)
        3 -- Sonnet 3  (claude-sonnet-4-6)
        4 -- Haiku     (claude-haiku-4-5-20251001)
        5 -- Opus      (claude-opus-4-6)

    All tabs use --dangerously-skip-permissions.
    Window title is set to "Claude - <TargetDir>" via workspace rename so it
    persists even after Claude CLI emits its own OSC 2 title sequences.

.PARAMETER TargetDir
    The directory to open (passed by Explorer via %1 / %V).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Paths
# =============================================================================

$repoRoot   = Split-Path $PSScriptRoot -Parent
$wezterm    = Join-Path $repoRoot 'bin\wezterm.exe'
$configFile = Join-Path $repoRoot 'config\wezterm.lua'
$socketDir  = "$env:USERPROFILE\.local\share\wezterm"
$winTitle   = "Claude - $TargetDir"

# =============================================================================
# Validate
# =============================================================================

if (-not (Test-Path $wezterm)) {
    Write-Error "wezterm.exe not found at: $wezterm`nRun install.ps1 first."
    exit 1
}

if (-not (Test-Path $TargetDir)) {
    Write-Error "TargetDir does not exist: $TargetDir"
    exit 1
}

# =============================================================================
# Step 1: Snapshot existing IPC sockets
# =============================================================================

$existingSockets = @()
if (Test-Path $socketDir) {
    $existingSockets = (Get-ChildItem $socketDir -Filter 'gui-sock-*' -ErrorAction SilentlyContinue).Name
}

# =============================================================================
# Step 2: Launch WezTerm with Tab 1 (Sonnet 1)
#
# --always-new-process forces a fresh GUI process even if another WezTerm is
# running, giving us an isolated IPC socket we can identify by diffing sockets.
# =============================================================================

$env:WEZTERM_CONFIG_FILE = $configFile

$startArgs = @(
    '--config-file', $configFile,
    'start',
    '--always-new-process',
    '--cwd', $TargetDir,
    '--',
    'claude', '--dangerously-skip-permissions', '--model', 'claude-sonnet-4-6'
)

Start-Process -FilePath $wezterm -ArgumentList $startArgs -WindowStyle Hidden

# =============================================================================
# Step 3: Poll for new IPC socket (timeout 30 s)
#
# wezterm-gui.exe writes %USERPROFILE%\.local\share\wezterm\gui-sock-<GUI_PID>
# We diff against the pre-launch snapshot to identify our instance's socket.
# =============================================================================

Write-Host 'Waiting for WezTerm IPC socket...'
$newSocketPath = $null
$deadline = (Get-Date).AddSeconds(30)

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200

    if (Test-Path $socketDir) {
        $current = Get-ChildItem $socketDir -Filter 'gui-sock-*' -ErrorAction SilentlyContinue
        $new = $current | Where-Object { $existingSockets -notcontains $_.Name }
        if ($new) {
            $newSocketPath = $new[0].FullName
            break
        }
    }
}

if (-not $newSocketPath) {
    Write-Error "Timed out (30 s) waiting for WezTerm IPC socket in $socketDir"
    exit 1
}

# Point all subsequent wezterm cli calls at our instance specifically
$env:WEZTERM_UNIX_SOCKET = $newSocketPath
Write-Host "IPC socket: $newSocketPath"

# Give the IPC server a moment to become ready for connections
Start-Sleep -Seconds 1

# =============================================================================
# Step 4: Discover window ID and first pane ID
# =============================================================================

$listJson = & $wezterm --config-file $configFile cli list --format json 2>&1
$panes    = $listJson | ConvertFrom-Json

if (-not $panes -or $panes.Count -eq 0) {
    Write-Error 'wezterm cli list returned no panes. WezTerm may not have started correctly.'
    exit 1
}

$windowId    = $panes[0].window_id
$firstPaneId = $panes[0].pane_id
Write-Host "Window ID: $windowId  |  Pane 1 ID: $firstPaneId"

# =============================================================================
# Step 5: Rename workspace for persistent window title
#
# The format-window-title Lua event in config/wezterm.lua returns the workspace
# name when it is not "default", so renaming it here sets the window title
# persistently -- overriding any OSC 2 sequences Claude CLI emits.
# =============================================================================

& $wezterm --config-file $configFile cli rename-workspace `
    --pane-id $firstPaneId `
    $winTitle

Write-Host "Workspace renamed to: $winTitle"

# =============================================================================
# Step 6: Spawn tabs 2-5
# =============================================================================

$tabs = @(
    @{ Label = 'Sonnet 2'; Model = 'claude-sonnet-4-6' },
    @{ Label = 'Sonnet 3'; Model = 'claude-sonnet-4-6' },
    @{ Label = 'Haiku';    Model = 'claude-haiku-4-5-20251001' },
    @{ Label = 'Opus';     Model = 'claude-opus-4-6' }
)

$spawnedPaneIds = @()

foreach ($tab in $tabs) {
    $paneIdRaw = & $wezterm --config-file $configFile cli spawn `
        --window-id $windowId `
        --cwd $TargetDir `
        -- claude --dangerously-skip-permissions --model $tab.Model

    $spawnedPaneIds += $paneIdRaw.Trim()
    Write-Host "Spawned tab '$($tab.Label)' -- pane ID: $($paneIdRaw.Trim())"

    # Brief pause to avoid IPC contention between rapid spawns
    Start-Sleep -Milliseconds 150
}

# =============================================================================
# Step 7: Set tab titles
#
# set-tab-title is a user-set override; it persists and will not be clobbered
# by OSC 2 sequences from Claude CLI.
# =============================================================================

$allTabs = @(
    @{ PaneId = $firstPaneId;        Label = 'Sonnet 1' },
    @{ PaneId = $spawnedPaneIds[0];  Label = 'Sonnet 2' },
    @{ PaneId = $spawnedPaneIds[1];  Label = 'Sonnet 3' },
    @{ PaneId = $spawnedPaneIds[2];  Label = 'Haiku'    },
    @{ PaneId = $spawnedPaneIds[3];  Label = 'Opus'     }
)

foreach ($t in $allTabs) {
    & $wezterm --config-file $configFile cli set-tab-title `
        --pane-id $t.PaneId `
        $t.Label
    Write-Host "Tab title set: '$($t.Label)' (pane $($t.PaneId))"
}

# =============================================================================
# Step 8: Set window title directly (belt-and-suspenders)
# =============================================================================

& $wezterm --config-file $configFile cli set-window-title `
    --window-id $windowId `
    $winTitle

# =============================================================================
# Step 9: Return focus to Tab 1 (Sonnet 1)
# =============================================================================

& $wezterm --config-file $configFile cli activate-tab `
    --tab-index 0 `
    --pane-id $firstPaneId

Write-Host 'Focus returned to Tab 1 (Sonnet 1).'

# =============================================================================
# Step 10: Re-set window title after Claude startup sequences settle
#
# Claude CLI emits OSC 2 title sequences during startup. Wait then re-assert
# the title as a final safety net (workspace rename handles the real persistence).
# =============================================================================

Start-Sleep -Seconds 2

& $wezterm --config-file $configFile cli set-window-title `
    --window-id $windowId `
    $winTitle

Write-Host "Done. Window: '$winTitle'"
