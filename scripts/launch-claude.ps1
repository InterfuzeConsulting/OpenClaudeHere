#Requires -Version 5.1
<#
.SYNOPSIS
    Opens a portable WezTerm window with 5 Claude tabs over a target directory.

.DESCRIPTION
    Called by the Explorer context menu ("Open Claude Workspace Here").

    Tab layout:
        1 -- Sonnet 1  (claude-sonnet-4-6)   <- active on open
        2 -- Sonnet 2  (claude-sonnet-4-6)
        3 -- Sonnet 3  (claude-sonnet-4-6)
        4 -- Haiku     (claude-haiku-4-5-20251001)
        5 -- Opus      (claude-opus-4-8)

    All tabs use --permission-mode auto.
    Window title is set to "Claude - <TargetDir>" via workspace rename so it
    persists even after Claude CLI emits its own OSC 2 title sequences.

.PARAMETER TargetDir
    The directory to open (passed by Explorer via %1 / %V).

.PARAMETER UseApiKey
    When set, the 5 Claude instances authenticate with a user-supplied Anthropic
    API key (ANTHROPIC_API_KEY) instead of the existing logged-in auth. The key
    is stored DPAPI-encrypted at config\api-key.dat and reused on later launches.
    On first use (file missing/empty) a masked dialog prompts for the key.
    The window title is tagged "[Using API Key]" vs "[Using Login]" accordingly.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetDir,

    [switch]$UseApiKey
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
$keyFile    = Join-Path $repoRoot 'config\api-key.dat'
$authTag    = if ($UseApiKey) { '[Using API Key]' } else { '[Using Login]' }
$winTitle   = "Claude - $TargetDir $authTag"

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
# Step 0: Resolve the Anthropic API key (only when -UseApiKey)
#
# Storage model (option C): the key lives DPAPI-encrypted at config\api-key.dat,
# encrypted to the current Windows user account (ConvertFrom-SecureString). It is
# entered once via a masked WinForms dialog on first click and reused thereafter.
#
# Validation:
#   - Cancel / empty input  -> abort cleanly (save nothing, spawn no tabs).
#   - Must start with "sk-ant-"; otherwise show a MessageBox and abort.
#
# Because the script runs under -WindowStyle Hidden, all user-facing messaging
# uses GUI dialogs (Read-Host / Write-Host would be invisible).
#
# IMPORTANT — env propagation: WezTerm spawns every pane (including tab 1) from a
# mux server that may already be running with its own captured environment, so
# setting $env:ANTHROPIC_API_KEY in THIS process does NOT reliably reach the tabs
# (verified empirically). Instead, each pane runs a small -EncodedCommand wrapper
# (see Get-PaneArgv) that decrypts api-key.dat itself and sets ANTHROPIC_API_KEY
# in its own process before exec'ing claude. The key is never placed on any
# command line; only the decrypt code + file path are. This step therefore only
# needs to guarantee a valid encrypted key file exists.
# =============================================================================

function Show-MessageBox {
    param([string]$Text, [string]$Title = 'Claude Workspace')
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

function Read-MaskedApiKey {
    # Returns the entered string, or $null if the user cancelled / closed the dialog.
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form              = New-Object System.Windows.Forms.Form
    $form.Text         = 'Anthropic API Key'
    $form.Size         = New-Object System.Drawing.Size(440, 170)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox  = $false
    $form.MinimizeBox  = $false
    $form.TopMost      = $true

    $label             = New-Object System.Windows.Forms.Label
    $label.Text        = "Enter your Anthropic API key (starts with sk-ant-).`r`nIt will be stored encrypted for this Windows account."
    $label.AutoSize    = $false
    $label.Size        = New-Object System.Drawing.Size(410, 40)
    $label.Location    = New-Object System.Drawing.Point(12, 10)
    $form.Controls.Add($label)

    $textBox           = New-Object System.Windows.Forms.TextBox
    $textBox.UseSystemPasswordChar = $true
    $textBox.Size      = New-Object System.Drawing.Size(410, 24)
    $textBox.Location  = New-Object System.Drawing.Point(12, 55)
    $form.Controls.Add($textBox)

    $okButton          = New-Object System.Windows.Forms.Button
    $okButton.Text     = 'OK'
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $okButton.Location = New-Object System.Drawing.Point(255, 90)
    $okButton.Size     = New-Object System.Drawing.Size(75, 26)
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    $cancelButton          = New-Object System.Windows.Forms.Button
    $cancelButton.Text     = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Location = New-Object System.Drawing.Point(347, 90)
    $cancelButton.Size     = New-Object System.Drawing.Size(75, 26)
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    $form.Add_Shown({ $textBox.Focus() })
    $result = $form.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return $null
    }

    $value = $textBox.Text
    $form.Dispose()
    return $value
}

function Test-StoredKey {
    # True if api-key.dat exists, is non-empty, and decrypts under this account.
    if (-not ((Test-Path $keyFile) -and ((Get-Item $keyFile).Length -gt 0))) { return $false }
    try {
        $secure = Get-Content $keyFile -Raw | ConvertTo-SecureString
        $bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $plain  = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        return -not [string]::IsNullOrWhiteSpace($plain)
    } catch {
        # Corrupt / undecryptable (e.g. copied from another Windows account).
        return $false
    }
}

if ($UseApiKey) {
    # Ensure a valid encrypted key file exists; prompt + persist on first use.
    if (-not (Test-StoredKey)) {
        $entered = Read-MaskedApiKey

        if ($null -eq $entered -or $entered.Trim().Length -eq 0) {
            # Cancel or empty -> abort cleanly: save nothing, spawn no tabs.
            exit 1
        }

        $entered = $entered.Trim()

        if (-not $entered.StartsWith('sk-ant-')) {
            Show-MessageBox -Text (
                "That doesn't look like a valid Anthropic API key.`r`n`r`n" +
                "Keys begin with `"sk-ant-`". Nothing was saved.`r`n" +
                "Re-run the menu item to try again.")
            exit 1
        }

        # Persist DPAPI-encrypted (current-user scope) for reuse by the panes.
        $secure = ConvertTo-SecureString $entered -AsPlainText -Force
        $secure | ConvertFrom-SecureString | Set-Content -Path $keyFile -NoNewline
        Write-Host 'API key stored (encrypted) for this workspace.'
    }
}

# =============================================================================
# Per-pane program arguments
#
# Both modes launch claude via a small powershell -EncodedCommand wrapper that
# first normalises the auth environment IN ITS OWN PROCESS, so each pane uses the
# intended credential regardless of any ambient ANTHROPIC_* vars inherited from
# the WezTerm mux server (which may already be running with its own environment):
#
#   API-key mode: drop any ambient ANTHROPIC_AUTH_TOKEN (it outranks the API key),
#     decrypt api-key.dat, set ANTHROPIC_API_KEY -> our key is authoritative.
#   Login  mode: drop ambient ANTHROPIC_API_KEY *and* ANTHROPIC_AUTH_TOKEN so
#     claude falls back to the claude.ai subscription login cleanly (no dual-auth
#     warning, and no accidental API billing).
#
# The key is never placed on a command line; only the decrypt code + file path
# are. The pane closes when claude exits (no -NoExit).
#
# Note: API-key panes may still show the one-off "Both claude.ai and
# ANTHROPIC_API_KEY set" notice while you remain logged into claude.ai -- the API
# key is still used (it takes precedence). Approving the key once when prompted
# is remembered by claude; a global `claude /logout` would also remove it.
# =============================================================================

function Get-PaneArgv {
    param([Parameter(Mandatory=$true)][string]$Model)

    if ($UseApiKey) {
        $script = @'
$ErrorActionPreference = 'Stop'
Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
$sec = Get-Content -Raw -LiteralPath "__KEYFILE__" | ConvertTo-SecureString
$b   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
$env:ANTHROPIC_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
claude --permission-mode auto --model __MODEL__
'@
        $script = $script.Replace('__KEYFILE__', $keyFile).Replace('__MODEL__', $Model)
    }
    else {
        $script = @'
Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
claude --permission-mode auto --model __MODEL__
'@
        $script = $script.Replace('__MODEL__', $Model)
    }

    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    return @('powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)
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
    '--'
) + (Get-PaneArgv -Model 'claude-sonnet-4-6')

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
    @{ Label = 'Haiku';    Model = 'claude-haiku-4-5-20251001'  },
    @{ Label = 'Opus';     Model = 'claude-opus-4-8'   }
)

$spawnedPaneIds = @()

foreach ($tab in $tabs) {
    $paneArgv = Get-PaneArgv -Model $tab.Model

    $paneIdRaw = & $wezterm --config-file $configFile cli spawn `
        --window-id $windowId `
        --cwd $TargetDir `
        -- $paneArgv

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
