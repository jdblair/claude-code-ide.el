# Notes

## 2025-12-08: Hyper Key Not Working After Ubuntu Update

### Problem
Hyper key stopped being recognized by Emacs after Ubuntu update.

### Root Cause
- Running **emacs-pgtk** (Pure GTK/Wayland Emacs build)
- Session is **Wayland** (`XDG_SESSION_TYPE=wayland`)
- Keyboard config uses X11 XKB (`ctrl:hyper_capscontrol` in `/usr/share/X11/xkb/symbols/ctrl`)
- xev shows Hyper_L (via XWayland), but emacs-pgtk is native Wayland
- emacs-pgtk uses libxkbcommon which doesn't interpret mod3 as Hyper the same way X11 does

### Current XKB Setup
- gsettings xkb-options: `['shift:both_capslock', 'ctrl:hyper_capscontrol', 'lv3:ralt_switch_multikey']`
- Caps Lock → Control_L
- Left Ctrl → Hyper_L (on mod3)

### Fix to Test
Run Emacs under XWayland instead of native Wayland:
```bash
GDK_BACKEND=x11 emacs
```

### Next Steps
1. Start Emacs with `GDK_BACKEND=x11 emacs`
2. Test if `C-h k H-m` now shows Hyper modifier
3. If it works, make permanent by:
   - Creating a wrapper script, OR
   - Modifying desktop entry, OR
   - Setting env var in shell profile

### Investigation Results

Tested `GDK_BACKEND=x11 emacs` - **did not help**.

Further diagnostics:
- `xmodmap -pm` shows Hyper_L correctly on mod3 ✓
- `gsettings get org.gnome.desktop.input-sources xkb-options` has correct options ✓
- `setxkbmap -query` shows NO options (XWayland not getting full config from GNOME)
- XKB rule `/usr/share/X11/xkb/symbols/ctrl` `hyper_capscontrol` is correct ✓
- **Hyper keypress never reaches Emacs** - `(read-event)` sees nothing

Root cause: On Wayland with emacs-pgtk, modifier-only keypresses (or Hyper specifically) don't propagate to applications. The XKB settings are correct but the Wayland compositor/libxkbcommon chain doesn't deliver Hyper events to native Wayland apps.

### Decision

Abandon Hyper key on Wayland/pgtk - too fragile. Migrate keybindings to **C-c prefix** (standard Emacs user namespace). Super is already used by Ubuntu for search.

## 2025-12-08: MCP Tools Dispatch Bug

### Problem
MCP tools failing with "Wrong type argument: stringp" or "Wrong number of arguments" errors.

Example errors:
- `project-info`: `Wrong number of arguments: #[nil ...], 1`
- `read-buffer`: `Wrong type argument: stringp, ("*Messages*" :buffer_name nil :start_line nil :end_line)`

### Root Cause
Bug introduced in commit `0b7cce4` (Yoav's `claude-code-ide-make-tool` API).

Two issues in `claude-code-ide-mcp-http-server.el`:

1. **`--validate-args` returns plist instead of list**
   - Old (working): returned `(value1 value2 value3)`
   - New (broken): returned `(:key1 value1 :key2 value2 ...)` but with pairs reversed due to push order bug

2. **Dispatch uses `funcall` instead of `apply`**
   - Old: `(apply tool-symbol args)` - unpacks list as positional args
   - New: `(funcall tool-function args)` - passes whole plist as single arg

### Fix
Changed `claude-code-ide-mcp-http-server.el`:

1. `--validate-args` now returns list of values (no keywords):
```elisp
;; Just push values, not keywords
(push value result)
```

2. Dispatch uses `apply`:
```elisp
(let ((result (apply tool-function args)))
```

### Testing
- All 74 tests pass
- Need to restart MCP server to pick up changes: `(claude-code-ide-emacs-tools-restart)`
- Then restart Claude Code session

**Interactive testing (2025-12-08):** All MCP tools working after fix:
- `project-info` ✓
- `read-buffer` ✓ (with line range params)
- `list-buffers` ✓
- `imenu-list-symbols` ✓
- `treesit-info` ✓
- `getDiagnostics` ✓

### Context
- Maintaining two dev environments: Linux (Emacs 30.1) / macOS (Emacs 30.2)
- Bug is code logic, not Emacs version-specific
- Bug exists in upstream `origin/main`
