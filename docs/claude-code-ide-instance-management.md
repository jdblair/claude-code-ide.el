# Claude Code IDE: Instance Management Implementation Guide

**Purpose**: This document provides implementation requirements for multi-instance coordination in Claude Code IDE, enabling multiple Claude sessions to work together via Emacs.

**Context**: Extracted from Sunshine project's multi-instance architecture needs, but this is a general-purpose capability for Claude Code IDE.

**Target project**: `claude-code-ide` (Emacs integration for Claude Code)

---

## Problem Statement

Currently, Claude Code runs as single sessions. For complex projects, it would be valuable to have **specialized instances** that:
- Hold different contexts (focused, minimal)
- Communicate with each other via Emacs buffers
- Are coordinated by a "main" instance (orchestrator pattern)
- Can be spawned/killed on demand

**Use case**: Sunshine project wants:
- **Main instance**: Orchestrator, conversational, full context
- **Brief generator**: Heavy data pipeline, runs periodically
- **Quick query**: Fast lookups from cache only
- **Team dev**: Coaching context, sensitive files

Each instance has its own CLAUDE.md (instructions) and directory, but they share tools/data.

---

## Required Capabilities

### 1. Spawn Instance

**Function**: Start a new Claude Code session in a different directory

**Elisp interface** (example):
```elisp
(claude-code-spawn-instance
  :directory "~/sunshine/brief-generator/"
  :buffer-name "*Claude Brief Generator*"
  :initial-message "Update all caches and generate briefing data"
  :async t)
```

**Behavior**:
- Opens Claude Code in specified directory
- Creates named Emacs buffer for that instance
- Instance reads its own `CLAUDE.md` from that directory
- Optionally sends initial message to get started
- Returns buffer name or instance ID

**Implementation notes**:
- Could use `start-process` to launch `claude` CLI in different directory
- Or integrate with existing Claude Code Emacs mode
- Buffer should be identifiable (unique name)

### 2. Send Message to Instance

**Function**: Insert text into instance's input buffer and trigger send

**Elisp interface**:
```elisp
(claude-code-send-to-instance
  :instance "*Claude Brief Generator*"
  :message "Run daily briefing generation")
```

**Behavior**:
- Finds the instance's buffer
- Inserts message into input area
- Triggers send (as if user pressed Enter)
- Returns immediately (async)

**Implementation notes**:
- Needs to know how Claude Code input works
- May need to simulate keypress or call Claude Code send function
- Should validate instance exists before sending

### 3. Read Instance Output

**Function**: Read recent output from instance's buffer

**Elisp interface**:
```elisp
(claude-code-read-instance-output
  :instance "*Claude Brief Generator*"
  :lines 50  ; optional, how many lines to read
  :wait-for-completion t)  ; optional, wait for instance to finish
```

**Behavior**:
- Reads content from instance's output buffer
- Can read last N lines or full buffer
- Optionally waits for instance to signal completion
- Returns text content

**Implementation notes**:
- Uses existing `claude-code-ide-mcp-read-buffer` tool
- Needs to detect when instance is "done" responding
- Could poll buffer for changes

### 4. Kill Instance

**Function**: Terminate a running instance

**Elisp interface**:
```elisp
(claude-code-kill-instance
  :instance "*Claude Brief Generator*")
```

**Behavior**:
- Gracefully shuts down the instance
- Closes buffer
- Cleans up resources

### 5. List Instances

**Function**: Get list of running Claude Code instances

**Elisp interface**:
```elisp
(claude-code-list-instances)
```

**Returns**:
```elisp
(("*Claude Main*" . "~/sunshine/main/")
 ("*Claude Brief Generator*" . "~/sunshine/brief-generator/")
 ("*Claude Quick Query*" . "~/sunshine/quick-query/"))
```

**Behavior**:
- Returns alist of (buffer-name . directory) pairs
- Only includes Claude Code buffers, not other buffers

### 6. Instance Status/Health

**Function**: Check if instance is responsive

**Elisp interface**:
```elisp
(claude-code-instance-status
  :instance "*Claude Brief Generator*")
```

**Returns**: `'running`, `'idle`, `'error`, `'dead`

---

## Communication Patterns

### Pattern 1: Task Delegation

**Main instance** delegates task to specialized instance:

```elisp
;; Main instance spawns brief generator
(claude-code-spawn-instance
  :directory "~/sunshine/brief-generator/"
  :buffer-name "*Brief Gen*"
  :initial-message "Run daily briefing pipeline")

;; Wait for completion (or poll)
(sleep-for 60)  ; Or use callback

;; Read results from shared state file
(let ((briefing-data
       (json-read-file "~/sunshine/shared/data/cache/sunshine-today.json")))
  ;; Use the data
  ...)
```

### Pattern 2: Quick Query

**Main instance** asks quick question to specialized instance:

```elisp
;; Quick query instance already running
(claude-code-send-to-instance
  :instance "*Quick Query*"
  :message "When is my next 1:1 with Oli?")

;; Read response
(claude-code-read-instance-output
  :instance "*Quick Query*"
  :wait-for-completion t)
```

### Pattern 3: Git Coordination

**Main instance** commits changes to another instance's CLAUDE.md:

```elisp
;; Main instance updates brief generator instructions
(with-temp-file "~/sunshine/brief-generator/CLAUDE.md"
  (insert "New instructions: also fetch AMS notes"))

;; Commit change
(shell-command "cd ~/sunshine && git add brief-generator/CLAUDE.md && git commit -m 'Update brief gen'")

;; Tell brief generator to reload
(claude-code-send-to-instance
  :instance "*Brief Gen*"
  :message "Git pull and re-read your CLAUDE.md")
```

---

## Implementation Approach

### Option A: Extend Existing Claude Code Emacs Mode

If `claude-code-ide` already has Emacs integration:
- Add functions to existing mode
- Leverage existing buffer management
- Reuse communication mechanisms

### Option B: New Process Management Layer

If starting fresh:
- Create `claude-code-instances.el` module
- Use `start-process` to spawn `claude` CLI
- Manage multiple processes explicitly
- Implement buffer coordination

### Option C: Use Existing MCP Tools

Leverage what's already working:
- `mcp__emacs-tools__claude-code-ide-mcp-eval` - Already can eval code
- `mcp__emacs-tools__claude-code-ide-mcp-read-buffer` - Already can read buffers
- Build coordination layer on top

**Recommended**: Option C first (leverage existing), then enhance with native Elisp (Option A/B) for better integration.

---

## Example Usage (Sunshine Project)

### Scenario: Morning Briefing

```elisp
;; Main Sunshine instance (user talking to)
;; User says: "Generate morning briefing"

;; Check if brief generator is running
(if (claude-code-instance-running-p "*Brief Gen*")
    ;; Already running, send task
    (claude-code-send-to-instance
      :instance "*Brief Gen*"
      :message "Generate briefing for today")
  ;; Not running, spawn it
  (claude-code-spawn-instance
    :directory "~/sunshine/brief-generator/"
    :buffer-name "*Brief Gen*"
    :initial-message "Generate briefing for today"))

;; Wait for completion (or set up callback)
(while (not (file-exists-p "~/sunshine/shared/data/cache/sunshine-today.json"))
  (sleep-for 1))

;; Read the generated data and create briefing
(let ((data (json-read-file "~/sunshine/shared/data/cache/sunshine-today.json")))
  ;; Main instance generates intelligent briefing from data
  ...)
```

### Scenario: Quick Query

```elisp
;; Main Sunshine instance
;; User asks: "When's my next meeting with Sarah?"

;; Spawn quick query instance (or reuse existing)
(unless (get-buffer "*Quick Query*")
  (claude-code-spawn-instance
    :directory "~/sunshine/quick-query/"
    :buffer-name "*Quick Query*"))

;; Send query
(claude-code-send-to-instance
  :instance "*Quick Query*"
  :message "When's my next meeting with Sarah?")

;; Read answer (blocks until complete)
(let ((answer (claude-code-read-instance-output
                :instance "*Quick Query*"
                :wait-for-completion t
                :lines 5)))
  ;; Display to user
  (message answer))
```

---

## Testing Strategy

### Unit Tests

Test each function independently:
- `test-spawn-instance`: Can spawn instance in directory
- `test-send-message`: Message reaches instance
- `test-read-output`: Can read instance buffer
- `test-kill-instance`: Instance terminates cleanly
- `test-list-instances`: Returns correct list

### Integration Tests

Test coordination patterns:
- `test-task-delegation`: Main spawns worker, gets result
- `test-multiple-instances`: Multiple instances run simultaneously
- `test-git-coordination`: CLAUDE.md updates propagate

### Real-World Test

Implement Sunshine multi-instance architecture:
- Main + brief-generator coordination
- Quick query spawning
- Verify performance improvements

---

## Success Criteria

Implementation is successful when:
- [ ] Can spawn Claude Code instance in different directory
- [ ] Instance reads its own CLAUDE.md from that directory
- [ ] Can send messages to instance programmatically
- [ ] Can read instance output from buffer
- [ ] Can list running instances
- [ ] Can gracefully kill instances
- [ ] Multiple instances can run simultaneously
- [ ] Main instance can coordinate workers
- [ ] Works on both personal and work Claude setups

---

## Future Enhancements

Once basic capabilities work:

### Instance Templates
Pre-configured instance types:
```elisp
(claude-code-spawn-from-template
  :template 'quick-query
  :project "~/my-project/")
```

### Callback-Based Communication
Non-blocking coordination:
```elisp
(claude-code-send-to-instance
  :instance "*Worker*"
  :message "Do work"
  :callback (lambda (result) (message "Done: %s" result)))
```

### Instance Health Monitoring
Automatic restart if instance dies:
```elisp
(claude-code-watch-instance
  :instance "*Critical Worker*"
  :restart-on-failure t)
```

### Shared Context Registry
Instances can publish/subscribe to shared state:
```elisp
(claude-code-publish :key "calendar-cache-updated" :value t)
(claude-code-subscribe :key "calendar-cache-updated"
                       :callback #'reload-cache)
```

---

## References

**Existing MCP tools** (already working):
- `mcp__emacs-tools__claude-code-ide-mcp-eval`
- `mcp__emacs-tools__claude-code-ide-mcp-read-buffer`
- `mcp__emacs-tools__claude-code-ide-mcp-reload-buffer`
- `mcp__emacs-tools__claude-code-ide-mcp-goto-location`
- `mcp__emacs-tools__claude-code-ide-mcp-list-buffers`

**Sunshine project files** (usage examples):
- `~/sunshine/docs/repo-restructure-plan.md` - Multi-instance architecture
- `~/sunshine/docs/intelligent-agenda-prep-design.md` - Query tool patterns

---

## Questions for Implementation

1. **Process model**: Should instances be separate OS processes, or threads within Emacs?
2. **Buffer naming**: Convention for instance buffer names?
3. **CLAUDE.md loading**: How does instance know to read from its directory?
4. **Completion detection**: How to know when instance finished responding?
5. **Error handling**: What if instance crashes or hangs?
6. **Resource limits**: Maximum number of concurrent instances?

---

*Created*: 2025-11-27 14:20 CET
*For project*: claude-code-ide
*Source*: Sunshine multi-instance architecture requirements
*Status*: Ready for implementation
