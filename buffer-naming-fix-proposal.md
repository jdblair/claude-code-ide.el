# Buffer Naming Collision Fix Proposal

**Target project**: claude-code-ide.el
**Issue**: Buffer naming collisions when projects have identical directory names or when multiple instances use visibility mode
**Date**: 2025-11-28

---

## Problems Identified

### Problem 1: Instance Buffer Naming Collision

**Current behavior:**
```
~/sunshine.2/sunshine/  → *claude-code[sunshine]*
~/sunshine/             → *claude-code[sunshine]*<2>
```

**Issue:** When spawning instances in directories with the same final path component, Emacs appends `<2>` to disambiguate, but this:
- Makes it hard to predict buffer names
- Causes orchestrator to send commands to wrong buffer
- Led to orchestrator killing itself during cleanup (from cache test)

### Problem 2: Visibility Mode Buffer Naming Collision

**Current behavior:**
```
Orchestrator: *Claude Planning*, *Claude Thinking*
Worker:       *Claude Planning*, *Claude Thinking*
```

**Issue:** Workers and orchestrator share the same Emacs instance via MCP, so buffers overwrite each other:
- Worker's planning buffer overwrites orchestrator's
- Orchestrator cannot distinguish its own buffers from worker buffers
- Loss of visibility into reasoning for both instances

---

## Proposed Solutions

### Solution 1: Instance Buffer Names Use Full Path Hash

**Change `claude-code-ide` buffer naming to include path hash:**

```elisp
;; Current (collision-prone)
(format "*claude-code[%s]*" (file-name-nondirectory (directory-file-name directory)))

;; Proposed (collision-resistant)
(defun claude-code-ide--unique-buffer-name (directory)
  "Generate unique buffer name for Claude Code instance in DIRECTORY."
  (let* ((dir-name (file-name-nondirectory (directory-file-name directory)))
         (parent-dir (file-name-nondirectory
                      (directory-file-name
                       (file-name-directory (directory-file-name directory)))))
         (full-path (abbreviate-file-name directory))
         (path-hash (substring (secure-hash 'sha256 full-path) 0 6)))
    (format "*claude-code[%s/%s:%s]*" parent-dir dir-name path-hash)))

;; Examples:
;; ~/sunshine.2/sunshine/  → *claude-code[sunshine.2/sunshine:a1b2c3]*
;; ~/sunshine/             → *claude-code[sunshine:d4e5f6]*
```

**Benefits:**
- Guaranteed unique buffer names
- Human-readable (includes parent directory)
- Predictable (hash is stable for same path)
- No Emacs `<2>` suffixes needed

**Alternative (simpler):**
```elisp
;; Just include parent directory
(format "*claude-code[%s/%s]*" parent-dir dir-name)

;; Examples:
;; ~/sunshine.2/sunshine/  → *claude-code[sunshine.2/sunshine]*
;; ~/sunshine/             → *claude-code[~/sunshine]*
```

**Recommendation:** Use simpler parent/dir approach first, add hash only if collisions still occur.

### Solution 2: Visibility Mode Buffers Use Instance Context

**Update visibility mode buffer naming to include instance context:**

```elisp
;; NEW: Function to determine buffer namespace
(defun claude-code-ide--visibility-namespace ()
  "Determine namespace for this instance's visibility buffers.

Returns project name derived from working directory, or 'Claude' for main instance."
  (let* ((default-dir (or default-directory "~"))
         (dir-name (file-name-nondirectory
                    (directory-file-name default-dir))))
    ;; Capitalize first letter for aesthetics
    (capitalize dir-name)))

;; Usage in visibility mode setup
(let ((namespace (claude-code-ide--visibility-namespace)))
  (get-buffer-create (format "*%s Planning*" namespace))
  (get-buffer-create (format "*%s Thinking*" namespace)))

;; Results:
;; Main instance:  *Claude Planning*, *Claude Thinking*
;; Worker in ~/sunshine:  *Sunshine Planning*, *Sunshine Thinking*
;; Worker in ~/brief-generator:  *Brief-generator Planning*, *Brief-generator Thinking*
```

**Benefits:**
- No buffer collisions between instances
- Clear ownership (which instance created which buffer)
- Orchestrator can read worker buffers to monitor progress
- Consistent with existing buffer naming conventions

**Implementation locations in claude-code-ide.el:**
1. Quick setup 2x2 grid code (line ~23-61 in visibility guide)
2. Alternative layout code (line ~660-691)
3. Any other buffer creation calls for `*Claude Planning*` or `*Claude Thinking*`

---

## Required Changes to claude-code-ide.el

### Change 1: Add Namespace Detection Function

```elisp
(defun claude-code-ide--instance-namespace ()
  "Determine namespace for this Claude instance.

Uses the final directory name from default-directory.
Returns 'Claude' as fallback if directory detection fails."
  (condition-case nil
      (let ((dir-name (file-name-nondirectory
                       (directory-file-name
                        (or default-directory "~")))))
        (if (string-empty-p dir-name)
            "Claude"
          (capitalize dir-name)))
    (error "Claude")))
```

### Change 2: Update Buffer Name Generation

**For instance buffers:**
```elisp
(defun claude-code-ide--buffer-name (directory)
  "Generate buffer name for Claude instance in DIRECTORY."
  (let* ((dir (directory-file-name directory))
         (dir-name (file-name-nondirectory dir))
         (parent (file-name-nondirectory
                  (directory-file-name
                   (file-name-directory dir)))))
    (if (string= parent ".")
        (format "*claude-code[%s]*" dir-name)
      (format "*claude-code[%s/%s]*" parent dir-name))))
```

**For visibility mode buffers:**
```elisp
;; Replace all instances of:
(get-buffer-create "*Claude Planning*")
(get-buffer-create "*Claude Thinking*")

;; With:
(let ((ns (claude-code-ide--instance-namespace)))
  (get-buffer-create (format "*%s Planning*" ns))
  (get-buffer-create (format "*%s Thinking*" ns)))
```

### Change 3: Update MCP Tool Responses

When MCP tools report buffer names, use the namespaced names:
```elisp
;; In visibility mode activation response
(format "Visibility mode activated with %s Planning and %s Thinking buffers"
        namespace namespace)
```

---

## Testing Strategy

### Test 1: Instance Buffer Naming
```bash
# Terminal 1: Start instance in sunshine.2/sunshine/
cd ~/sunshine.2/sunshine/
claude

# Terminal 2: Start instance in sunshine/
cd ~/sunshine/
claude

# Emacs: List buffers
M-x ibuffer

# Expected:
# *claude-code[sunshine.2/sunshine]*
# *claude-code[~/sunshine]*  (or [jblair/sunshine])
# NO <2> suffixes
```

### Test 2: Visibility Buffer Naming
```bash
# Terminal 1: Main instance
cd ~/sunshine.2/sunshine/
claude

# In Claude: Enable visibility
user: show me your planning and thinking

# Expected buffers:
# *Sunshine Planning*
# *Sunshine Thinking*

# Terminal 2: Worker instance
cd ~/sunshine/
claude

# In Claude: Enable visibility
user: show me your planning and thinking

# Expected buffers (in addition to above):
# *Sunshine Planning*  # From sunshine/ worker (different from sunshine.2!)
# *Sunshine Thinking*

# Verify no overwrites
```

### Test 3: Multi-Instance Orchestration
```elisp
;; Spawn worker from orchestrator
(claude-code-ide-spawn-instance
  :directory "~/sunshine/"
  :buffer-name "*Worker*"
  :initial-message "enable visibility mode")

;; After worker starts, list buffers
(mcp__emacs-tools__claude-code-ide-mcp-list-buffers)

;; Expected:
;; *claude-code[sunshine.2/sunshine:abc123]* (orchestrator)
;; *claude-code[~/sunshine:def456]*         (worker)
;; *Sunshine.2 Planning*                     (orchestrator visibility)
;; *Sunshine.2 Thinking*                     (orchestrator visibility)
;; *Sunshine Planning*                       (worker visibility)
;; *Sunshine Thinking*                       (worker visibility)

;; Orchestrator can read worker buffers
(read-buffer "*Sunshine Planning*")  ; Shows worker's planning state
```

---

## Edge Cases

### Same Directory Name in Different Parent Dirs
```
~/projects/foo/bar/sunshine/
~/staging/foo/bar/sunshine/
```

**Solution:** Parent-based naming handles this:
- `*claude-code[foo/sunshine]*` vs `*claude-code[foo/sunshine]*` ← Still collision!
- Need to add grandparent or hash: `*claude-code[bar/sunshine:a1b2c3]*`

**Revised approach:** Always include 2 parent levels + hash:
```elisp
(format "*claude-code[%s/%s/%s:%s]*"
        grandparent parent dir-name (substring hash 0 6))
```

### Root or Home Directory
```
cd /
claude   → *claude-code[root]*

cd ~
claude   → *claude-code[jblair]*  (or $USER)
```

### Worker Doesn't Know Its Namespace
Worker should detect namespace from its own `default-directory`, not from orchestrator's instruction. This ensures correct namespacing even if orchestrator forgets to specify.

---

## Migration Path

### Phase 1: Instance Buffer Names (Critical)
Fixes the cache test issue where orchestrator killed itself.

1. Update `claude-code-ide--buffer-name` function
2. Test with sunshine/sunshine.2 directories
3. Verify orchestrator can reliably target worker buffers

### Phase 2: Visibility Buffer Names (Critical)
Fixes buffer collision between instances in shared Emacs.

1. Add `claude-code-ide--instance-namespace` function
2. Update all buffer creation code for visibility mode
3. Test with orchestrator + worker scenario
4. Update visibility mode guide documentation

### Phase 3: Documentation Updates
1. Update `/Users/jblair/.claude/docs/ide-visibility-mode.md`
2. Update `/Users/jblair/src/claude-code-ide.el/claude-code-ide-instance-management.md`
3. Add examples of namespace detection to guides

---

## Implementation Priority

**Priority 1 (Immediate):** Instance buffer naming fix
- Blocks multi-instance work
- Caused orchestrator self-kill bug
- Required for cache architecture testing

**Priority 2 (High):** Visibility buffer namespacing
- Blocks visibility mode with multi-instance
- Required for orchestrator monitoring worker progress
- Prevents buffer overwrites

**Priority 3 (Medium):** Documentation updates
- Can be done after implementation
- Helps users understand the changes

---

## Critical: Instance Self-Awareness and Self-Preservation

**Problem:** During cache testing, orchestrator accidentally killed itself due to buffer name confusion.

**Root cause:** Instances don't know their own buffer name, so they can't protect themselves from accidental deletion.

### Solution: Instance Identity Detection

Every Claude instance must be able to determine its own buffer name to avoid self-termination.

#### Implementation: Environment Variable

When `claude-code-ide` spawns an instance, set an environment variable:

```elisp
;; In claude-code-ide spawn function
(let ((buffer-name (claude-code-ide--buffer-name directory)))
  (start-process
    "claude-code"
    buffer-name
    "claude"
    ;; Pass buffer name to the process
    (format "CLAUDE_BUFFER_NAME=%s" buffer-name)
    ...))
```

#### Implementation: MCP Tool

Provide an MCP tool for instances to query their own buffer name:

```elisp
(defun claude-code-ide-mcp-my-buffer-name ()
  "Return the buffer name of the Claude instance making this call.

This allows instances to identify themselves and avoid self-deletion."
  (let ((calling-buffer (current-buffer)))
    (buffer-name calling-buffer)))
```

**Register as MCP tool:**
```json
{
  "name": "mcp__emacs-tools__claude-code-ide-mcp-my-buffer-name",
  "description": "Get the buffer name of the current Claude instance",
  "parameters": {}
}
```

#### Usage Pattern: Safe Buffer Operations

Before any buffer deletion, instances must verify they're not targeting themselves:

```elisp
;; WRONG - No safety check
(kill-buffer "*claude-code[sunshine]*")

;; CORRECT - Verify not self
(let ((my-buffer (call-mcp "mcp__emacs-tools__claude-code-ide-mcp-my-buffer-name"))
      (target-buffer "*claude-code[sunshine]*"))
  (if (string= my-buffer target-buffer)
      (error "Cannot kill own buffer! I am %s" my-buffer)
    (kill-buffer target-buffer)))
```

#### Required Checks

**Every instance must check before:**
1. `(kill-buffer ...)` - Never kill own buffer
2. `(delete-window ...)` - Never delete window showing own buffer
3. `(bury-buffer ...)` - Be careful with own buffer
4. Any eval that manipulates buffer list

**Safety pattern:**
```elisp
;; Safe buffer kill function
(defun claude-safe-kill-buffer (buffer-name)
  "Kill BUFFER-NAME only if it's not the current instance's buffer."
  (let ((my-buffer (mcp__emacs-tools__claude-code-ide-mcp-my-buffer-name)))
    (when (string= buffer-name my-buffer)
      (error "Attempted self-termination! My buffer: %s, Target: %s"
             my-buffer buffer-name))
    (when (get-buffer buffer-name)
      (kill-buffer buffer-name))))
```

### Testing Self-Awareness

**Test 1: Instance knows its own name**
```elisp
;; In orchestrator (~/sunshine.2/sunshine/)
(mcp__emacs-tools__claude-code-ide-mcp-my-buffer-name)
;; Expected: "*claude-code[sunshine.2/sunshine]*"

;; In worker (~/sunshine/)
(mcp__emacs-tools__claude-code-ide-mcp-my-buffer-name)
;; Expected: "*claude-code[~/sunshine]*"
```

**Test 2: Self-preservation works**
```elisp
;; Orchestrator tries to kill itself (should fail)
(claude-safe-kill-buffer
  (mcp__emacs-tools__claude-code-ide-mcp-my-buffer-name))
;; Expected: Error message, buffer remains alive
```

**Test 3: Can kill other buffers**
```elisp
;; Orchestrator kills worker (should succeed)
(claude-safe-kill-buffer "*claude-code[~/sunshine]*")
;; Expected: Worker buffer killed, orchestrator remains alive
```

### Documentation for Claude Instances

Add to CLAUDE.md or instance management docs:

```markdown
## Instance Identity

You are running in a specific Emacs buffer. To find out which buffer:

\`\`\`elisp
(mcp__emacs-tools__claude-code-ide-mcp-my-buffer-name)
\`\`\`

**CRITICAL:** Before deleting any buffer, verify it's not your own:

\`\`\`elisp
;; ALWAYS check before killing buffers
(let ((my-buffer (mcp__emacs-tools__claude-code-ide-mcp-my-buffer-name)))
  (when (string= target-buffer my-buffer)
    (error "Cannot kill own buffer!")))
\`\`\`

Never execute code that would terminate yourself unless explicitly
requested by the user to shut down.
```

### Graceful Shutdown Protocol

When instance needs to terminate itself (legitimate shutdown):

```elisp
;; Worker responding to "goodbye" message
(defun claude-graceful-shutdown ()
  "Perform cleanup and signal ready for termination."
  ;; Save state
  (save-some-buffers t)

  ;; Cleanup temp files
  (cleanup-temp-resources)

  ;; Signal ready (orchestrator will kill our buffer)
  (message "Cleanup complete. Ready for termination.")

  ;; DO NOT kill own buffer - orchestrator does that
  ;; DO NOT call (kill-buffer (mcp__...-my-buffer-name))
  )
```

**Only orchestrator kills worker buffers, never self-termination.**

---

## Open Questions

1. **Should namespace be configurable?**
   - Could allow user to set custom namespace in CLAUDE.md
   - Would override directory-based detection
   - Useful for workers with specific roles ("Brief Generator", "Quick Query")

2. **Should orchestrator namespace always be "Claude"?**
   - Makes it clear which is the main instance
   - Or should it also use directory name for consistency?

3. **Hash length for instance buffers?**
   - 6 chars (proposed) = 16M combinations
   - 4 chars = 65K combinations (probably sufficient)
   - Tradeoff: shorter = cleaner, longer = more unique

4. **Should we support nested instance spawning?**
   - Worker spawns its own sub-worker
   - Would need multi-level namespacing
   - Probably YAGNI (you ain't gonna need it)

5. **Should my-buffer-name be cached or always queried?**
   - Cached: Faster, but could become stale if buffer renamed
   - Always query: Slower, but guaranteed current
   - Recommendation: Cache on first call, provide refresh function

---

## Success Criteria

Implementation successful when:
- ✓ Different directories with same name produce unique instance buffer names
- ✓ Orchestrator can reliably send commands to worker without confusion
- ✓ Visibility mode buffers are namespaced per instance
- ✓ Worker buffers don't overwrite orchestrator buffers
- ✓ Orchestrator can read worker visibility buffers to monitor progress
- ✓ Buffer names are human-readable and predictable
- ✓ No `<2>` or `<3>` suffixes appear in buffer names

---

**Next Steps:**
1. Review this proposal with claude-code-ide maintainers
2. Implement Phase 1 (instance buffer names)
3. Test with sunshine multi-instance scenario
4. Implement Phase 2 (visibility buffer names)
5. Update documentation

**Status:** Ready for implementation
