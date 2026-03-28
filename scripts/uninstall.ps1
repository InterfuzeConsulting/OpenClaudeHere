#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the Explorer context menu entries created by install.ps1.

.DESCRIPTION
    Deletes both HKCU registry keys (and their command subkeys):
        HKCU:\Software\Classes\Directory\shell\OpenWezTermClaude
        HKCU:\Software\Classes\Directory\Background\shell\OpenWezTermClaude

    Does NOT touch bin\ or config\. To fully remove everything, delete the
    Wezterm\ folder manually after running this script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File uninstall.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot    = Split-Path $PSScriptRoot -Parent
$menuKey     = 'OpenWezTermClaude'
$shortcutPath = Join-Path $repoRoot 'Launch Claude Workspace.lnk'

$keys = @(
    "HKCU:\Software\Classes\Directory\shell\$menuKey",
    "HKCU:\Software\Classes\Directory\Background\shell\$menuKey"
)

foreach ($keyPath in $keys) {
    if (Test-Path $keyPath) {
        # -Recurse removes the key and all subkeys (including \command)
        Remove-Item -Path $keyPath -Recurse -Force
        Write-Host "[REMOVED] $keyPath"
    } else {
        Write-Host "[SKIP]    Not found: $keyPath"
    }
}

# Remove taskbar shortcut
if (Test-Path $shortcutPath) {
    Remove-Item -Path $shortcutPath -Force
    Write-Host "[REMOVED] $shortcutPath"
} else {
    Write-Host "[SKIP]    Not found: $shortcutPath"
}

Write-Host ''
Write-Host '=== Uninstall Complete ==='
Write-Host 'Context menu entries and shortcut removed.'
Write-Host 'bin\ and config\ have not been touched.'
Write-Host 'To fully remove, delete the Wezterm\ folder manually.'
