#Requires -Version 5.1
<#
.SYNOPSIS
    Shows a folder picker dialog then opens the Claude 5-tab workspace.

.DESCRIPTION
    Designed to be pinned to the taskbar via "Launch Claude Workspace.lnk"
    in the repo root. Pick a folder, click OK, and the workspace opens.
#>

Add-Type -AssemblyName System.Windows.Forms

$repoRoot = Split-Path $PSScriptRoot -Parent

# =============================================================================
# Folder picker dialog
# =============================================================================

$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description    = 'Select a folder to open as a Claude workspace'
$dialog.ShowNewFolderButton = $false

# Start the picker in a sensible location
$dialog.SelectedPath = $env:USERPROFILE

$result = $dialog.ShowDialog()

if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    # User cancelled -- do nothing
    exit 0
}

$targetDir = $dialog.SelectedPath

# =============================================================================
# Hand off to the main launcher
# =============================================================================

$launchScript = Join-Path $repoRoot 'scripts\launch-claude.ps1'

& $launchScript -TargetDir $targetDir
