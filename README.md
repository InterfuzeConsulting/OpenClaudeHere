# Portable WezTerm + Claude Workspace

A self-contained WezTerm setup that opens any folder as a 5-tab Claude workspace directly from Explorer. No system install required — copy the folder to any Windows machine and run `install.ps1`.

**WARNING**: This script launches claude with --dangerously-skip-permissions. Use at your own risk.
---

## What it does

Right-clicking any folder gives you **"Open Claude Workspace Here (5 tabs)"**, which opens a WezTerm window titled `Claude - <folder>` with:

| Tab                 | Model                       |
| ------------------- | --------------------------- |
| Sonnet 1–3 (3 tabs) | `claude-sonnet-4-6`         |
| Haiku               | `claude-haiku-4-5-20251001` |
| Opus                | `claude-opus-4-6`           |

All tabs start with `--dangerously-skip-permissions`. Shift+Enter is enabled for multiline prompts.

A **"Launch Claude Workspace.lnk"** shortcut is also created in this folder — pin it to your taskbar for a folder-picker launcher.

## API key mode

A second menu item, **"Open Claude Workspace Here (5 tabs on API Key)"**, opens the same 5-tab layout but authenticates the Claude instances with an Anthropic API key (billed via the API) instead of your logged-in session.

- **First click** prompts for the key in a masked dialog. The key must start with `sk-ant-`; cancelling or entering nothing aborts without launching, and an invalid key shows an explanation and aborts.
- The key is stored **encrypted** (Windows DPAPI, your account only) at `config\api-key.dat` and **reused** on every later click — you are not prompted again.
- **Rotate / clear the key** by deleting `config\api-key.dat`; the next launch re-prompts. (Uninstall also deletes it.)

The window title shows which auth mode is active: `Claude - <folder> [Using API Key]` vs `Claude - <folder> [Using Login]`.

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

Removes both context menu items, the shortcut, and the stored API key (`config\api-key.dat`). Delete the folder to remove everything else.

## Portability

To use on another machine: copy this folder, run `install.ps1`. The `bin\` folder can be deleted to force a fresh WezTerm download.
