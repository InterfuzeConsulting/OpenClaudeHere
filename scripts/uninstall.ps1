#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the Explorer context menu entries created by install.ps1.

.DESCRIPTION
    Deletes the HKCU registry keys (and their command subkeys) for both menu
    items, under both context-menu roots:
        ...\Directory\shell\OpenWezTermClaude
        ...\Directory\Background\shell\OpenWezTermClaude
        ...\Directory\shell\OpenWezTermClaudeApiKey
        ...\Directory\Background\shell\OpenWezTermClaudeApiKey

    Also deletes the stored, DPAPI-encrypted API key at config\api-key.dat.

    Does NOT touch bin\ or the rest of config\. To fully remove everything,
    delete the Wezterm\ folder manually after running this script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File uninstall.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot    = Split-Path $PSScriptRoot -Parent
$menuKey     = 'OpenWezTermClaude'
$apiMenuKey  = 'OpenWezTermClaudeApiKey'
$shortcutPath = Join-Path $repoRoot 'Launch Claude Workspace.lnk'
$keyFile     = Join-Path $repoRoot 'config\api-key.dat'

$keys = @(
    "HKCU:\Software\Classes\Directory\shell\$menuKey",
    "HKCU:\Software\Classes\Directory\Background\shell\$menuKey",
    "HKCU:\Software\Classes\Directory\shell\$apiMenuKey",
    "HKCU:\Software\Classes\Directory\Background\shell\$apiMenuKey"
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

# Remove stored, DPAPI-encrypted API key
if (Test-Path $keyFile) {
    Remove-Item -Path $keyFile -Force
    Write-Host "[REMOVED] $keyFile"
} else {
    Write-Host "[SKIP]    Not found: $keyFile"
}

Write-Host ''
Write-Host '=== Uninstall Complete ==='
Write-Host 'Context menu entries, shortcut, and stored API key removed.'
Write-Host 'bin\ and the rest of config\ have not been touched.'
Write-Host 'To fully remove, delete the Wezterm\ folder manually.'
