# Plan: pi Support in claude-code-ide.el

**Goal:** Allow `claude-code-ide.el` to launch [pi](https://github.com/badlogic/pi-mono/) (the `pi` coding agent CLI) instead of the Claude Code CLI, so pi sessions get the same Emacs MCP tool surface (xref, project, imenu, buffers, tree-sitter, eval, instance management, etc.).

**Decision: modify `claude-code-ide.el`, not pi.**
Pi intentionally has no built-in MCP, but it is extensible via TypeScript extensions/packages. Existing ecosystem support already exists, so no pi-side changes are needed.

## Git Workflow

All work happens on a new branch in the personal fork, never on `main` and
never pushed to upstream.

Remotes (already configured):
- `origin` → https://github.com/manzaltu/claude-code-ide.el (upstream, read-only)
- `fork`   → git@github.com:jdblair/claude-code-ide.el (personal fork)

Steps:
1. Sync: `git fetch origin && git checkout main && git merge --ff-only origin/main`
2. Create branch: `git checkout -b pi-support`
3. Develop + test on `pi-support`; commit per plan item (no self-referential
   commit messages per project rules).
4. Push only to fork: `git push fork pi-support`
5. Optionally open a PR against upstream `manzaltu/claude-code-ide.el:main`
   once the feature is stable — user decision, not done automatically.

Note: this plan document (`docs/PI_INTEGRATION_PLAN.md`) is currently
untracked; include it in the first branch commit.

## Prior Art / Existing pi MCP Support

**`pi-mcp-adapter`** (npm package, actively maintained) is the de-facto MCP client for pi:

- Install once: `pi install npm:pi-mcp-adapter`
- Supports HTTP / Streamable HTTP MCP servers via `"url"` — exactly the transport
  `claude-code-ide-mcp-http-server.el` implements (`POST /mcp/<session-id>`,
  JSON-RPC methods `initialize`, `tools/list`, `tools/call`).
- Registers its own `--mcp-config <path>` pi flag (file path — unlike claude,
  which takes inline JSON: `--mcp-config '<json>'`).
- `directTools: true` registers each MCP tool as a first-class pi tool
  (matches the claude `--allowedTools mcp__emacs-tools__*` UX). Default is a
  single `mcp` proxy tool.
- Supports `${VAR}` / `$env:VAR` interpolation in `url` and `headers`.
- Config precedence: `~/.config/mcp/mcp.json` > `~/.agents/mcp.json` >
  `<pi agent dir>/mcp.json` > `.mcp.json` > `.pi/mcp.json`. The
  `--mcp-config` flag path takes precedence over all of these.

### pi CLI flag compatibility (verified via `pi --help`)

| claude flag used today | pi equivalent | Notes |
|---|---|---|
| `-c` (continue) | `-c` / `--continue` | Same |
| `-r` (resume) | `-r` / `--resume` | Same |
| `--append-system-prompt <text>` | `--append-system-prompt <text>` | Same |
| `-d` (debug) | `--verbose` | Different — only forces verbose *startup* output, not full debug parity |
| `--mcp-config '<inline json>'` | `--mcp-config <file>` (pi-mcp-adapter) | File path, requires adapter |
| `--allowedTools <tools>` | `--tools, -t <tools>` | Optional; pi has its own tool allowlist |
| `CLAUDE_CODE_SSE_PORT` env | none | Claude-specific IDE websocket; drop for pi |

**Not portable to pi (Claude IDE protocol specific):** the WebSocket IDE-mode
features in `claude-code-ide-mcp.el` / `claude-code-ide-mcp-handlers.el`
(IDE openDiff, selection/active-editor tracking, `getDiagnostics` push).
The HTTP `emacs-tools` MCP server covers the tool surface; IDE-mode niceties
are out of scope for v1.

## Changes

> This section incorporates findings from an independent agent review of the
> plan against the codebase (see review highlights at the end of the doc).

### 1. New customization: agent backend (`claude-code-ide.el`)

```elisp
(defcustom claude-code-ide-agent 'claude
  "Which coding agent CLI to launch.
`claude' uses the Claude Code CLI; `pi' uses the pi coding agent.
Pi support requires the pi-mcp-adapter package: pi install npm:pi-mcp-adapter"
  :type '(choice (const :tag "Claude Code" claude)
                 (const :tag "pi" pi))
  :group 'claude-code-ide)

(defcustom claude-code-ide-pi-cli-path "pi"
  "Path to the pi CLI executable."
  :type 'string
  :group 'claude-code-ide)
```

Add helper `claude-code-ide--agent-cli-path` returning the effective CLI path
(`claude-code-ide-cli-path` or `claude-code-ide-pi-cli-path`) and use it in
`claude-code-ide--detect-cli` and `claude-code-ide-check-status` (both already
use `--version`, which pi supports).

Also route `claude-code-ide-transient.el` through the new helper: it
currently hardcodes `claude-code-ide-cli-path` in
`claude-code-ide-transient-show-version` (with its own "Claude Code CLI not
available" `user-error`) and in the CLI-path setter. Without this, the
transient menu reports/checks the wrong binary when `claude-code-ide-agent`
is `'pi`.

### 2. Pi MCP config file (deterministic per-directory)

New function `claude-code-ide-mcp-server-write-config-file (&optional session-id)`:

- Calls existing `claude-code-ide-mcp-server-get-config` for
  `http://localhost:<port>/mcp/<session-id>` (note: the existing code builds
  `localhost` URLs while the server binds `127.0.0.1`; either resolves, keep
  the existing `localhost` form).
- Adds adapter option `"lifecycle": "eager"`.
- `"directTools"` is controlled by a new defcustom (see below); default `nil`.
- Writes JSON to a **deterministic filename derived from a sanitized
  `default-directory`** in `temporary-file-directory`, e.g.
  `claude-code-ide-mcp-<sanitized-dir-hash>.json`, overwritten on each start.
- Returns the file path.

Rationale vs. `make-temp-file` + tracking table: only one session per
directory can exist (process/buffer tables are keyed by directory), so a
deterministic name needs no bookkeeping, self-heals leftovers from crashed
Emacs sessions on next start, and cleanup is a single `delete-file`.

Config content (proxy mode, the default):

```json
{
  "mcpServers": {
    "emacs-tools": {
      "url": "http://localhost:<port>/mcp/<session-id>",
      "lifecycle": "eager"
    }
  }
}
```

When `claude-code-ide-pi-direct-tools` is non-nil, add `"directTools": true`.

**directTools caveat (from review):** pi-mcp-adapter registers direct tools
from a metadata cache (`~/.pi/agent/mcp-cache.json`); on the first session
after adding a new server the cache is missing and tools fall back to the
single `mcp` proxy tool until the cache populates. Because
`claude-code-ide-mcp-server-port` defaults to nil, the URL port changes on
every Emacs restart, so direct tools may rarely engage unless users pin a
fixed port. Therefore v1 defaults to **proxy mode** and documents the
caveat + fixed-port recommendation; `directTools` stays available as an
option:

```elisp
(defcustom claude-code-ide-pi-direct-tools nil
  "Register each emacs-tools MCP tool as a first-class pi tool.\
Requires pi-mcp-adapter.  Works best with a fixed
`claude-code-ide-mcp-server-port'; see docs for the first-session
cache fallback."
  :type 'boolean
  :group 'claude-code-ide)
```

(Lives in `claude-code-ide-mcp-server.el` next to `…-get-config`.)

### 3. Agent-aware command builder

Split `claude-code-ide--build-claude-command` (line ~862) into:

- `claude-code-ide--build-claude-command` — existing behavior, unchanged.
- `claude-code-ide--build-pi-command (&optional continue resume session-id)`:

```
pi [-c] [-r] [--verbose if claude-code-ide-cli-debug]
   --append-system-prompt '<emacs prompt + claude-code-ide-system-prompt>'
   [claude-code-ide-cli-extra-flags]
   --mcp-config <config-file>     ; only when MCP server enabled
```

Notes:
- Factor the emacs-context system prompt (currently an inline `let` in
  `--build-claude-command`, ~line 885) into a shared helper so the two
  builders can't drift.
- Quote the config path with `shell-quote-argument`. A plain quoted path is
  simpler than the double-escaping the claude inline-JSON path needs
  (~lines 912–916) and works for all terminal backends: vterm runs the
  command through a shell; eat/ghostel parse it with
  `claude-code-ide--parse-command-string` → `split-string-shell-command`.
- Skip `--allowedTools`; optionally map `claude-code-ide-mcp-allowed-tools`
  'auto → pi `--tools read,bash,edit,write,<tool names>` (stretch goal;
  v1: leave pi defaults). If implemented later, note that pi tool names are
  *not* `mcp__emacs-tools__*` — the adapter prefixes per its `toolPrefix`
  setting, so `claude-code-ide-mcp-server-get-tool-names` would need a
  pi-specific prefix.
- Dispatch: `claude-code-ide--build-agent-command` picks based on
  `claude-code-ide-agent`.

### 4. Session start and environment variables

**Skip the WebSocket IDE server for pi (review finding G1).**
`claude-code-ide--start-session` (~line 1130) unconditionally calls
`claude-code-ide-mcp-start` and passes the port only to build
`CLAUDE_CODE_SSE_PORT`. For pi nothing connects to that WebSocket, so skip
`claude-code-ide-mcp-start` entirely and pass `nil` as `port` (the error
cleanup at the end of `--start-session` already guards on `(when port ...)`).
This removes a useless server start/lockfile/refcount/teardown cycle.

**Environment variables (`claude-code-ide--create-terminal-session`, line ~972):**
extract env-var construction into
`claude-code-ide--build-env-vars (agent port session-id)` so the split is
directly unit-testable without terminal mocks.

- claude backend: unchanged (`CLAUDE_CODE_SSE_PORT`, `TERM_PROGRAM`,
  `FORCE_CODE_TERMINAL`, optional `CLAUDE_CODE_NO_FLICKER`).
- pi backend: drop `CLAUDE_CODE_SSE_PORT` and `FORCE_CODE_TERMINAL`; keep
  `TERM_PROGRAM=emacs`. (Review suggested `CLAUDE_CODE_IDE_SESSION_ID`; v1
  drops it since nothing reads it — wire it in only when a consumer exists.)

### 5. Adapter-absence detection (was Open Question 1)

Without `pi-mcp-adapter` installed, `--mcp-config` is an unregistered flag
and pi fails at startup (extensions register that flag). When
`claude-code-ide-agent` is `'pi` and `claude-code-ide-enable-mcp-server` is
non-nil, probe once per Emacs session — `call-process pi nil nil nil "list"`
and match `pi-mcp-adapter` in output — and `user-error` with an install hint
if missing. Document that `agent='pi` with
`claude-code-ide-enable-mcp-server` nil works with no adapter at all.

### 6. Temp-file cleanup

- `claude-code-ide--cleanup-on-exit` (line ~784): delete the deterministic
  config file alongside the existing `claude-code-ide-mcp-server-session-ended`
  bookkeeping.
- Also delete it in the `--start-session` error path (currently stops the WS
  session but would leak the already-written config file).
- No tracking hash table needed (deterministic naming, item 2); crash
  leftovers self-heal on next start.

### 7. Naming (minor)

- `claude-code-ide--default-buffer-name` produces `*claude-code[dir]*`
  regardless of backend; switching agents mid-session yields confusing names.
  Either include the agent in the name or document it.
- Use a `pi-<dir>-<ts>` session-id prefix for the pi backend (helps when
  debugging MCP URLs).

### 8. User-facing messages

- Line ~1105 `user-error`: mention the active agent ("Claude Code CLI" vs
  "pi CLI") and, for pi, hint at `pi install npm:pi-mcp-adapter` when the MCP
  server is enabled but the adapter is missing (see item 5).
- `claude-code-ide-check-status` (line ~1231): report agent name.

### 9. Tests (`claude-code-ide-tests.el`)

- `claude-code-ide--build-pi-command`:
  - bare `pi` + `--append-system-prompt` with emacs prompt;
  - `-c` / `-r` flags;
  - `claude-code-ide-cli-debug` → `--verbose`;
  - extra flags passthrough;
  - `--mcp-config <path>` present when
    `claude-code-ide-enable-mcp-server` is non-nil (mock
    `claude-code-ide-mcp-server-ensure-server`/`…-get-config`), absent otherwise;
  - **parse round-trip:** the built command survives
    `claude-code-ide--parse-command-string` / `split-string-shell-command`
    with the config path and quoted system prompt intact (guards the
    eat/ghostel backends, where quoting bugs would surface).
- `claude-code-ide--build-agent-command` dispatcher with both agent values.
- `claude-code-ide--build-env-vars` for both agents (claude vars present,
  pi vars absent / `TERM_PROGRAM` kept).
- `claude-code-ide-mcp-server-write-config-file`:
  - file exists, JSON parses, contains `url` with session id and
    `lifecycle` eager; `directTools` only when
    `claude-code-ide-pi-direct-tools` is non-nil;
  - second write for the same directory overwrites (no duplicate files);
  - cleanup deletes the file — after `claude-code-ide--cleanup-on-exit` and
    after the `--start-session` error path.
- CLI detection *and* `claude-code-ide-check-status` with
  `claude-code-ide-agent` = 'pi (mock `call-process`).
- Adapter-absence probe: `pi list` output without/with `pi-mcp-adapter`.
- Ensure existing claude-backend tests still pass unchanged.

The real adapter ↔ HTTP-server round trip can't run in ERT batch mode; the
manual test (implementation step 7) is the right place. Enumerate the
expected request sequence there (`initialize` → `notifications/initialized`
→ `tools/list` → `tools/call`) and explicitly verify the eager-connect
failure mode when the Emacs server stops mid-session.

Run: `emacs -batch -L . -l ert -l claude-code-ide-tests.el -f ert-run-tests-batch-and-exit`

### 10. Documentation

- `README.org`: new "pi support" section — setup
  (`setq claude-code-ide-agent 'pi`), prerequisite
  `pi install npm:pi-mcp-adapter` (not needed when the MCP server is
  disabled), feature matrix (what works, what is Claude-IDE-protocol-only),
  `directTools` caveat + fixed-port recommendation
  (`claude-code-ide-mcp-server-port`).
- `CLAUDE.md`: mention the `claude-code-ide-agent` option in architecture
  notes.

## Out of Scope (v1)

- Pi client for the Claude IDE WebSocket protocol (ediff-via-IDE, selection
  tracking, diagnostics push). Possible later via a pi extension speaking the
  SSE protocol, but low value vs. the HTTP MCP tools.
- Writing `.mcp.json` into project dirs (rejected: invasive; `--mcp-config`
  temp file is cleaner).
- Bundling our own minimal MCP-bridge extension (rejected: `pi-mcp-adapter`
  exists and is more capable — lazy loading, proxy mode, OAuth, caching).

## Open Questions

1. ~~Graceful fallback if pi-mcp-adapter is not installed~~ — resolved:
   promoted to plan item 5 (`pi list` probe + `user-error` with install hint).
2. Should `claude-code-ide-mcp-allowed-tools` map to pi `--tools`? v1: no.
   If later, account for the adapter's `toolPrefix` naming (review G9).

## Review Findings Incorporated

Independent agent review verified all plan references against the codebase
and npm (pi-mcp-adapter v2.31.0); findings now folded into the plan above:

- **G1 (structural):** skip `claude-code-ide-mcp-start` / WS IDE server for
  pi → item 4.
- **G2 (UX assumption):** `directTools` first-session cache fallback →
  proxy-mode default + `claude-code-ide-pi-direct-tools` option → item 2.
- **G3:** adapter absence hard-fails startup → item 5.
- **G4:** temp-file leak on crash / error path; hash table over-engineered →
  deterministic per-directory naming → items 2, 6.
- **G5:** `--verbose` is not debug parity → flag table note.
- **G6:** drop speculative `CLAUDE_CODE_IDE_SESSION_ID` → item 4.
- **G7:** buffer naming / session-id prefix → item 7.
- **G8:** `claude-code-ide-transient.el` hardcodes claude CLI path → item 1.
- **G9:** pi tool-name prefix differs from `mcp__*` → item 3 note.
- **G10:** multi-directory concurrency is fine by design; worth a test.
- Factual corrections: `localhost` (not `127.0.0.1`) URLs; terminal backends
  are vterm/eat/ghostel (no ansi-term); shared prompt helper + env-var
  extraction for testability (items 3, 4).

## Implementation Order

0. Create the `pi-support` branch (see Git Workflow above).
1. Backend defcustoms + CLI path helper + detection/status updates +
   transient.el routing (item 1).
2. `…-write-config-file` with deterministic naming +
   `claude-code-ide-pi-direct-tools` (item 2) + cleanup hooks incl. error
   path (item 6).
3. `…-build-pi-command` + dispatcher + shared prompt helper (item 3);
   `…-build-env-vars` + skip WS server for pi (item 4); adapter probe
   (item 5).
4. Naming tweaks (item 7).
5. Tests (item 9).
6. Docs (README.org, CLAUDE.md) (item 10).
7. Manual interactive test: start pi session, call an emacs tool via the
   `mcp` proxy tool, verify the request sequence (`initialize` →
   `notifications/initialized` → `tools/list` → `tools/call`), session
   cleanup, and config file removal; also verify behavior when the Emacs
   MCP server stops mid-session.
