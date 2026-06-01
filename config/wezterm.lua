-- Portable WezTerm config
-- Used exclusively when launched via launch-claude.ps1 or manually with --config-file.
-- Do NOT set default_cwd here — the launcher script provides CWD per invocation.

local wezterm = require 'wezterm'

local config = wezterm.config_builder()

-- ── Appearance ────────────────────────────────────────────────────────────────

config.initial_cols  = 120
config.initial_rows  = 28
config.font_size     = 12
config.color_scheme  = 'AdventureTime'

-- ── Shell ─────────────────────────────────────────────────────────────────────

config.default_prog = { 'powershell.exe' }

-- ── Close behaviour ───────────────────────────────────────────────────────────

config.window_close_confirmation = 'NeverPrompt'
config.skip_close_confirmation_for_processes_named = {
  'cmd.exe', 'pwsh.exe', 'powershell.exe',
  'claude.cmd', 'claude.exe', 'claude', 'node.exe', 'node'
}

-- ── Keyboard ──────────────────────────────────────────────────────────────────

-- Kitty keyboard protocol: lets Claude CLI distinguish Shift+Enter from Enter
-- for multiline prompt input (sends \x1b[13;2u instead of \r).
config.enable_kitty_keyboard = true

-- ── Window title ──────────────────────────────────────────────────────────────

-- When launch-claude.ps1 renames the workspace to "Claude - <dir>", this event
-- returns that name as the window title, overriding any OSC 2 sequences emitted
-- by Claude CLI at startup. Normal WezTerm usage (workspace == "default") falls
-- back to the active pane's title so regular windows are unaffected.
wezterm.on('format-window-title', function(tab, pane, tabs, panes, cfg)
  local workspace = wezterm.mux.get_active_workspace()
  if workspace ~= 'default' then
    return workspace
  end
  return tab.active_pane.title
end)

-- ── Launch menu ───────────────────────────────────────────────────────────────

config.launch_menu = {
  -- Model-specific entries (family aliases: always resolve to latest)
  {
    label = 'Claude — Sonnet',
    args  = { 'claude', '--permission-mode', 'auto', '--model', 'claude-sonnet-4-6' },
  },
  {
    label = 'Claude — Haiku',
    args  = { 'claude', '--permission-mode', 'auto', '--model', 'claude-haiku-4-5-20251001' },
  },
  {
    label = 'Claude — Opus',
    args  = { 'claude', '--permission-mode', 'auto', '--model', 'claude-opus-4-8' },
  },
}

-- ── Key bindings ──────────────────────────────────────────────────────────────

config.keys = {
  -- Shift+^ → show launcher menu
  {
    key   = '^',
    mods  = 'SHIFT',
    action = wezterm.action.ShowLauncher,
  },
  -- Ctrl+Y → open new Claude tab in current pane's working directory
  {
    key  = 'y',
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      window:perform_action(
        wezterm.action.SpawnCommandInNewTab {
          args = { 'claude', '--permission-mode', 'auto' },
          cwd  = pane:get_current_working_dir().file_path,
        },
        pane
      )
    end),
  },
}

return config
