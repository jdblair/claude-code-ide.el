# Notes: pi Support Implementation

Date: 2026-08-31
Branch: `pi-support` (based on local `main`, not pushed)
Plan: `docs/PI_INTEGRATION_PLAN.md`

## What was done

All work follows the implementation order in the plan, which was reviewed
critically by an independent agent pass before implementation (review
findings G1–G10 are folded into the plan).

### Commits (oldest → newest)

1. `Add pi integration plan` — the plan document itself.
2. `Fix stale MCP tool tests for modular tools refactor` — pre-existing
   breakage, unrelated to pi: the suite failed to *load* because tests still
   called removed `claude-code-ide-mcp-handle-goto-location` /
   `…-handle-reload-buffer` (moved to
   `mcp-tools.d/claude-code-ide-tool-buffer-management.el`). Rewrote both
   tests against the new positional-argument functions and added a
   `claude-code-ide-mcp-tests--with-session-context` helper (modular tools
   require a registered session).
3. `Add pi agent backend support` — the implementation.
4. `Add tests for pi agent backend` — 10 new ERT tests.
5. `Document pi agent support` — README.org + CLAUDE.md.

### Implementation details

**`claude-code-ide.el`**
- New defcustoms: `claude-code-ide-agent` (`'claude` default | `'pi`),
  `claude-code-ide-pi-cli-path` (`"pi"`).
- Helpers: `claude-code-ide--agent-cli-path`,
  `claude-code-ide--agent-display-name` — used by `--detect-cli`,
  `claude-code-ide-check-status`, and all user-facing messages.
- `claude-code-ide--combined-system-prompt` — the Emacs-context prompt
  factored out of `--build-claude-command` so both builders share it.
- `claude-code-ide--build-pi-command` — `pi [-c] [-r] [--verbose]
  --append-system-prompt <quoted prompt> [extra flags] [--mcp-config <file>]`.
- `claude-code-ide--build-agent-command` — dispatcher on
  `claude-code-ide-agent`.
- `claude-code-ide--build-env-vars (agent port)` — claude gets
  `CLAUDE_CODE_SSE_PORT`, `TERM_PROGRAM=emacs`, `FORCE_CODE_TERMINAL`,
  optional `CLAUDE_CODE_NO_FLICKER`; pi gets only `TERM_PROGRAM=emacs`.
- `claude-code-ide--create-terminal-session` binds `default-directory`
  *before* building the command (the deterministic config filename depends
  on it) and uses the dispatcher + env helper.
- `claude-code-ide--start-session`:
  - WebSocket IDE server (`claude-code-ide-mcp-start`) is skipped entirely
    for pi — nothing would connect to it.
  - Adapter prerequisite checked before anything starts.
  - Session-id prefix is `pi-<dir>-<ts>` for pi, `claude-<dir>-<ts>` for
    claude.
  - Error path deletes any already-written config file.
- `claude-code-ide--cleanup-on-exit` deletes the config file.
- Adapter probe: `claude-code-ide--pi-adapter-available-p` runs `pi list`
  once per Emacs session (cached in `claude-code-ide--pi-adapter-checked` /
  `--pi-adapter-available`); `claude-code-ide--ensure-pi-mcp-adapter`
  signals a `user-error` with the install hint when the agent is pi, the
  MCP server is enabled, and the adapter is missing.

**`claude-code-ide-mcp-server.el`**
- `claude-code-ide-pi-direct-tools` defcustom (default nil → proxy mode).
- `claude-code-ide-mcp-server-config-file-path` — deterministic
  `temporary-file-directory/claude-code-ide-mcp-<sha1 of dir>.json`.
  No tracking table needed: one session per directory, crash leftovers
  self-heal on next start.
- `claude-code-ide-mcp-server-write-config-file` — writes the
  pi-mcp-adapter config (`url`, `lifecycle: eager`, optional
  `directTools: true`).
- `claude-code-ide-mcp-server-delete-config-file` — idempotent.

**`claude-code-ide-transient.el`**
- Version info and the "Set CLI path" suffix route through the agent-aware
  helper; `--save-config` persists the two new defcustoms.

### Verification

- Full suite: `emacs -batch -L . -l ert -l claude-code-ide-tests.el -f
  ert-run-tests-batch-and-exit` → 88 tests, 80 pass, 8 skipped (same skips
  as before), 0 failures.
- New tests cover: pi command flags (`-c`/`-r`/`--verbose`/extra flags),
  system prompt inclusion, `--mcp-config` presence/absence, shell-parse
  round-trip through `claude-code-ide--parse-command-string` (guards the
  eat/ghostel backends), dispatcher, env vars for both agents, config file
  write/overwrite/delete + `directTools` toggle, adapter probe (mock
  `call-process`, cache behavior, user-error paths), CLI detection/status
  for pi.
- HTTP round-trip smoke test (batch Emacs with real `web-server` from
  `~/.emacs.d/elpa`, curl against `/mcp/<session-id>`): `initialize` →
  `notifications/initialized` → `tools/list` → `tools/call`
  (`claude-code-ide-mcp-list-buffers`) all succeeded; config JSON and file
  cleanup verified. Script was throwaway and not committed.
- Byte-compilation clean (only pre-existing warnings).

### Environment notes

- `pi` is on PATH via `/home/jdblair/.pi/agent/bin` (first entry), so the
  default `claude-code-ide-pi-cli-path` of `"pi"` resolves in Emacs if the
  Emacs process inherits that PATH (verify with `(executable-find "pi")`).
- Batch `emacs` on this machine does **not** see elpa packages; tests mock
  websocket/web-server. The user's interactive Emacs has web-server,
  websocket in `~/.emacs.d/elpa/`; vterm/eat/ghostel availability in the
  interactive session should be confirmed during manual testing.
- `pi-mcp-adapter` is **not installed** yet (`pi list` shows no packages).
- The local `main` branch has diverged from upstream `manzaltu` origin
  (35 local commits + upstream 0.3.0 advance); `pi-support` was branched
  from local `main` by decision. Reconciling with upstream is deferred.

## Next steps

1. **Install the adapter:** `pi install npm:pi-mcp-adapter`.
2. **Manual interactive test** (plan step 7), in the user's Emacs:
   ```elisp
   (setq claude-code-ide-agent 'pi)
   (setq claude-code-ide-enable-mcp-server t)
   (claude-code-ide-emacs-tools-setup)   ; if not already in init
   ```
   - Start a session (`M-x claude-code-ide`), confirm pi launches with the
     `--mcp-config` flag (enable `claude-code-ide-debug` to log the
     command).
   - Ask pi to call an Emacs tool (e.g. list buffers) through the `mcp`
     proxy tool; verify the request sequence `initialize` →
     `notifications/initialized` → `tools/list` → `tools/call` reaches the
     Emacs HTTP server.
   - Stop the session; verify buffer/process cleanup and that
     `/tmp/claude-code-ide-mcp-*.json` is deleted.
   - Test failure modes: MCP server stopped mid-session (eager reconnect
     behavior), adapter uninstalled (expect the install-hint user-error).
   - Optionally try `(setq claude-code-ide-pi-direct-tools t)` together
     with a fixed `(setq claude-code-ide-mcp-server-port 8765)` and
     observe the adapter's first-session cache fallback.
3. **Optional:** test the `claude` backend end-to-end once to confirm no
   regressions in real usage (command/env behavior is unchanged by
   construction, and unit tests pass).
4. **Push** when satisfied: `git push fork pi-support`.
5. **Optional:** PR against `manzaltu/claude-code-ide.el:main` once stable
   — user decision. Note the branch currently includes the divergent local
   commits; a PR would likely need a rebased/clean branch against upstream.

## Deferred / out of scope (v1)

- Mapping `claude-code-ide-mcp-allowed-tools` to pi `--tools` (would need
  the adapter's `toolPrefix` naming, not `mcp__*`).
- Claude IDE WebSocket protocol features for pi (ediff-via-IDE, selection
  tracking, diagnostics push).
- Agent-aware buffer names (kept `*claude-code[dir]*`; documented instead).
