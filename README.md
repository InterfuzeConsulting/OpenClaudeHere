# Portable WezTerm + Claude Workspace

A self-contained WezTerm setup that opens any folder as a 5-tab Claude workspace directly from Explorer. No system install required — copy the folder to any Windows machine and run `install.ps1`.

**WARNING**: This script launches claude with --dangerously-skip-permissions. Use at your own risk.
---

## What it does

Right-clicking any folder gives you **"Open Claude Workspace Here (5 tabs)"**, which opens a WezTerm window titled `Claude - <folder>` with:

| Tab | Model |
|-----|-------|
| Sonnet 1–3 (3 tabs) | `claude-sonnet-4-6` |
| Haiku | `claude-haiku-4-5-20251001` |
| Opus | `claude-opus-4-6` |

All tabs start with `--dangerously-skip-permissions`. Shift+Enter is enabled for multiline prompts.

A **"Launch Claude Workspace.lnk"** shortcut is also created in this folder — pin it to your taskbar for a folder-picker launcher.

## Install

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

Downloads WezTerm into `bin\`, registers the right-click menu (no admin required), and creates `Launch Claude Workspace.lnk` for taskbar pinning.

**Requires:** `claude` on PATH (`npm install -g @anthropic-ai/claude-code`)

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File scripts\uninstall.ps1
```

Removes the context menu entries and shortcut. Delete the folder to remove everything else.

## Portability

To use on another machine: copy this folder, run `install.ps1`. The `bin\` folder can be deleted to force a fresh WezTerm download.
