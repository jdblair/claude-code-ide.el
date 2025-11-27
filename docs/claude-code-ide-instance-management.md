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

## Message Queue IPC System

### Overview

For efficient inter-instance communication, a structured message queue system is available as an alternative to parsing vterm buffer output.

**Architecture**:
- **Shared Emacs environment**: All Claude instances connect to the same Emacs via MCP
- **Global queue registry**: Hash table mapping instance names to message queues
- **Structured messages**: Native elisp plists (no parsing required)
- **FIFO semantics**: Messages processed in order (oldest first)

### Message Structure

Every message is a plist with metadata:

```elisp
(:from "Orchestrator"
 :to "Worker-Instance"
 :type "task-request"
 :payload (:task "analyze-data" :options (:verbose t))
 :timestamp (26920 39367 315412 0))
```

**Fields**:
- `:from` - Sender instance name (string)
- `:to` - Recipient instance name (string)
- `:type` - Message type (string) - e.g., "task-request", "task-complete", "ping", "pong"
- `:payload` - Message data (plist, can be any structure)
- `:timestamp` - When message was created (Emacs time format)

### API Reference

#### Initialize System

The queue system must be initialized once in the shared Emacs environment:

```elisp
;; This code should be run once to set up the queue system
(defvar claude-ipc-queues (make-hash-table :test 'equal)
  "Hash table mapping instance names to their message queues.")

(defun claude-ipc-create-message (from to type payload)
  "Create a structured IPC message."
  (list :from from
        :to to
        :type type
        :payload payload
        :timestamp (current-time)))

(defun claude-ipc-send (to-instance message)
  "Send MESSAGE to TO-INSTANCE's queue."
  (let ((queue (gethash to-instance claude-ipc-queues)))
    (unless queue
      (setq queue '())
      (puthash to-instance queue claude-ipc-queues))
    (puthash to-instance (cons message (gethash to-instance claude-ipc-queues))
             claude-ipc-queues)
    message))

(defun claude-ipc-receive (instance &optional count)
  "Receive up to COUNT messages from INSTANCE's queue (all if COUNT is nil).
Messages are returned oldest-first and removed from queue."
  (let* ((queue (gethash instance claude-ipc-queues))
         (reversed (reverse queue))
         (to-return (if count (butlast reversed (- (length reversed) count)) reversed))
         (remaining (if count (nthcdr count reversed) nil)))
    (puthash instance (reverse remaining) claude-ipc-queues)
    to-return))

(defun claude-ipc-peek (instance &optional count)
  "Peek at up to COUNT messages from INSTANCE's queue without removing."
  (let* ((queue (gethash instance claude-ipc-queues))
         (reversed (reverse queue)))
    (if count (butlast reversed (- (length reversed) count)) reversed)))

(defun claude-ipc-list-queues ()
  "List all instance queues and their message counts."
  (let (result)
    (maphash (lambda (instance queue)
               (push (list instance (length queue)) result))
             claude-ipc-queues)
    result))
```

#### Sending Messages

**From orchestrator to worker:**

```elisp
;; Orchestrator sends task request
(claude-ipc-send "Worker-Instance"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Worker-Instance"
                  "task-request"
                  '(:task "analyze-docs"
                    :directory "~/project/docs")))
```

**From worker to orchestrator:**

```elisp
;; Worker sends result back (via eval tool)
(claude-ipc-send "Orchestrator"
                 (claude-ipc-create-message
                  "Worker-Instance"
                  "Orchestrator"
                  "task-complete"
                  '(:result "found 7 documents"
                    :files ("doc1.md" "doc2.md" "doc3.md"))))
```

#### Receiving Messages

**Receive all messages:**

```elisp
;; Worker checks its queue
(let ((messages (claude-ipc-receive "Worker-Instance")))
  (dolist (msg messages)
    (pcase (plist-get msg :type)
      ("task-request"
       (let ((task (plist-get (plist-get msg :payload) :task)))
         ;; Process task...
         ))
      ("ping"
       ;; Respond to ping...
       ))))
```

**Receive one message at a time:**

```elisp
;; Process messages incrementally
(let ((msg (car (claude-ipc-receive "Worker-Instance" 1))))
  (when msg
    ;; Process single message...
    ))
```

#### Peeking Without Consuming

```elisp
;; Check if there are messages without removing them
(let ((pending (claude-ipc-peek "Worker-Instance")))
  (message "Pending messages: %d" (length pending)))
```

#### Monitoring All Queues

```elisp
;; See all instances and their message counts
(claude-ipc-list-queues)
;; Returns: (("Orchestrator" 2) ("Worker-Instance" 5))
```

### Usage Patterns

#### Pattern 1: Task Delegation

**Orchestrator delegates work to worker:**

```elisp
;; 1. Send task
(claude-ipc-send "Data-Processor"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Data-Processor"
                  "task-request"
                  '(:task "process-logs"
                    :input-file "/tmp/logs.txt")))

;; 2. Notify worker via vterm (optional)
(claude-code-ide-instance--send-message
 "*Data-Processor*"
 "Check your queue for a new task!")

;; 3. Poll for completion
(while (not (claude-ipc-peek "Orchestrator"))
  (sleep-for 1))

;; 4. Receive result
(let* ((messages (claude-ipc-receive "Orchestrator"))
       (result-msg (car (seq-filter
                         (lambda (m)
                           (equal (plist-get m :type) "task-complete"))
                         messages))))
  (plist-get (plist-get result-msg :payload) :result))
```

#### Pattern 2: Ping/Pong Health Check

**Check if worker is responsive:**

```elisp
;; Orchestrator pings worker
(claude-ipc-send "Worker-Instance"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Worker-Instance"
                  "ping"
                  '(:timestamp ,(current-time))))

;; Worker responds (in its context)
(let ((msg (car (claude-ipc-receive "Worker-Instance" 1))))
  (when (equal (plist-get msg :type) "ping")
    (claude-ipc-send "Orchestrator"
                     (claude-ipc-create-message
                      "Worker-Instance"
                      "Orchestrator"
                      "pong"
                      '(:status "ready"
                        :capabilities ("analyze" "report"))))))
```

#### Pattern 3: Broadcast to Multiple Workers

**Send same message to multiple instances:**

```elisp
;; Notify all workers of configuration change
(dolist (worker '("Worker-1" "Worker-2" "Worker-3"))
  (claude-ipc-send worker
                   (claude-ipc-create-message
                    "Orchestrator"
                    worker
                    "config-update"
                    '(:setting "log-level"
                      :value "debug"))))
```

### Comparison: Queue vs Vterm Messages

| Aspect | Message Queue | Vterm Messages |
|--------|--------------|----------------|
| **Structure** | Native plists, no parsing | Natural language, must parse |
| **Metadata** | Built-in (from, to, type, timestamp) | Must extract from text |
| **Reliability** | Guaranteed delivery, FIFO | Mixed with UI output |
| **Acknowledgment** | Can implement ack pattern | No built-in ack |
| **Type Safety** | Structured payloads | Unstructured text |
| **Performance** | Direct data access | Requires text parsing |
| **Human Readable** | Requires inspection | Naturally readable |
| **History** | Retained in queue until consumed | Scrollback buffer |

**Recommendation**: Use message queue for programmatic coordination; use vterm messages for human-readable notifications and debugging.

### Best Practices

1. **Use typed messages**: Define standard message types ("task-request", "task-complete", "error", "ping", "pong")
2. **Include correlation IDs**: Add `:request-id` to payload for tracking related messages
3. **Handle errors**: Send "error" type messages when tasks fail
4. **Set timeouts**: Don't wait indefinitely for responses
5. **Clean up queues**: Consume messages promptly to avoid unbounded growth
6. **Namespace instances**: Use descriptive instance names that indicate purpose

### Example: Complete Workflow

```elisp
;; === Orchestrator side ===

;; 1. Send task with correlation ID
(let ((request-id (format-time-string "%Y%m%d%H%M%S")))
  (claude-ipc-send "Sunshine-Worker"
                   (claude-ipc-create-message
                    "Orchestrator"
                    "Sunshine-Worker"
                    "task-request"
                    `(:task "analyze-tracked-docs"
                      :request-id ,request-id)))

  ;; 2. Wait for response with matching request-id
  (let ((max-wait 30) ; seconds
        (waited 0)
        (result nil))
    (while (and (< waited max-wait) (not result))
      (let ((messages (claude-ipc-peek "Orchestrator")))
        (setq result (seq-find
                      (lambda (m)
                        (and (equal (plist-get m :type) "task-complete")
                             (equal (plist-get (plist-get m :payload)
                                               :request-id)
                                    request-id)))
                      messages)))
      (unless result
        (sleep-for 1)
        (setq waited (1+ waited))))

    ;; 3. Process result
    (if result
        (progn
          (claude-ipc-receive "Orchestrator") ; Consume all messages
          (message "Task completed: %s"
                   (plist-get (plist-get result :payload) :result)))
      (message "Task timeout after %d seconds" max-wait))))


;; === Worker side (Sunshine-Worker) ===

;; 1. Check queue for messages
(let ((messages (claude-ipc-receive "Sunshine-Worker")))
  (dolist (msg messages)
    (when (equal (plist-get msg :type) "task-request")
      (let* ((payload (plist-get msg :payload))
             (task (plist-get payload :task))
             (request-id (plist-get payload :request-id)))

        ;; 2. Process task
        (let ((result (pcase task
                        ("analyze-tracked-docs"
                         ;; Do the work...
                         '(:found 7 :docs ("doc1" "doc2" "doc3")))
                        (_ '(:error "Unknown task")))))

          ;; 3. Send result back
          (claude-ipc-send "Orchestrator"
                           (claude-ipc-create-message
                            "Sunshine-Worker"
                            "Orchestrator"
                            "task-complete"
                            `(:request-id ,request-id
                              :result ,result))))))))
```

---

## Advanced Patterns: Buffer References in Messages

Since all Claude instances share the same Emacs environment, buffer names can be passed in message payloads to enable advanced coordination patterns beyond simple message passing.

### Pattern 1: Large Data Transfer

**Problem**: Message payloads have practical size limits.

**Solution**: Create a buffer with the data, pass buffer name in message.

```elisp
;; Orchestrator prepares large dataset
(with-current-buffer (get-buffer-create "*Dataset-Large*")
  (erase-buffer)
  (insert-file-contents "~/data/large-file.json"))

;; Send task with buffer reference
(claude-ipc-send "Data-Processor"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Data-Processor"
                  "process-dataset"
                  '(:input-buffer "*Dataset-Large*"
                    :output-buffer "*Processed-Results*"
                    :format "json")))

;; Worker reads from buffer
(with-current-buffer "*Dataset-Large*"
  (let ((data (json-read)))
    ;; Process...
    (with-current-buffer (get-buffer-create "*Processed-Results*")
      (insert (json-encode results)))))
```

**Benefits**:
- No size limits (buffers can be gigabytes)
- Efficient (no serialization in message)
- Shared memory model

### Pattern 2: Formatted Results Buffers

**Problem**: Results may need rich formatting (markdown, code, etc.)

**Solution**: Worker creates formatted buffer, sends reference.

```elisp
;; Worker generates formatted analysis
(with-current-buffer (get-buffer-create "*Analysis-Report*")
  (erase-buffer)
  (markdown-mode)
  (insert "# Analysis Results\n\n")
  (insert "## Summary\n")
  (insert (format "- Total items: %d\n" count))
  (insert (format "- Errors found: %d\n" errors))
  (insert "\n## Details\n")
  (insert "```python\n")
  (insert code-sample)
  (insert "\n```\n"))

;; Send completion with buffer reference
(claude-ipc-send "Orchestrator"
                 (claude-ipc-create-message
                  "Analyzer"
                  "Orchestrator"
                  "analysis-complete"
                  '(:results-buffer "*Analysis-Report*"
                    :format "markdown"
                    :summary (:items 1247 :errors 3))))
```

**Benefits**:
- Proper syntax highlighting
- Human-readable in Emacs
- Can be edited/refined by orchestrator

### Pattern 3: Real-Time Progress Monitoring

**Problem**: Long-running tasks need progress visibility.

**Solution**: Worker updates progress buffer, sends periodic messages.

```elisp
;; Worker creates progress buffer
(let ((progress-buf (get-buffer-create "*Task-Progress-123*")))
  (with-current-buffer progress-buf
    (erase-buffer)
    (insert "=== Task Progress ===\n\n"))

  ;; Send initial message
  (claude-ipc-send "Orchestrator"
                   (claude-ipc-create-message
                    "Worker"
                    "Orchestrator"
                    "task-started"
                    `(:progress-buffer ,(buffer-name progress-buf)
                      :total-items 100)))

  ;; Process items with updates
  (dotimes (i 100)
    (process-item i)
    (when (zerop (mod i 10))
      ;; Update buffer
      (with-current-buffer progress-buf
        (goto-char (point-max))
        (insert (format "Processed %d/100 items...\n" (1+ i))))
      ;; Send progress message
      (claude-ipc-send "Orchestrator"
                       (claude-ipc-create-message
                        "Worker"
                        "Orchestrator"
                        "progress-update"
                        `(:progress-buffer ,(buffer-name progress-buf)
                          :completed ,(1+ i)
                          :total 100))))))
```

**Benefits**:
- Live progress visibility
- Orchestrator can monitor buffer
- Non-blocking (async updates)

### Pattern 4: Collaborative Document Editing

**Problem**: Multiple workers need to edit different parts of same document.

**Solution**: Coordinate via messages, edit shared buffer.

```elisp
;; Orchestrator creates shared document
(with-current-buffer (get-buffer-create "*Collaborative-Doc*")
  (erase-buffer)
  (insert initial-content))

;; Assign sections to workers
(claude-ipc-send "Worker-1"
                 (claude-ipc-create-message
                  "Orchestrator" "Worker-1"
                  "edit-section"
                  '(:buffer "*Collaborative-Doc*"
                    :section "Introduction"
                    :line-range (1 . 50))))

(claude-ipc-send "Worker-2"
                 (claude-ipc-create-message
                  "Orchestrator" "Worker-2"
                  "edit-section"
                  '(:buffer "*Collaborative-Doc*"
                    :section "Analysis"
                    :line-range (51 . 150))))

;; Workers coordinate completion
(claude-ipc-send "Orchestrator"
                 (claude-ipc-create-message
                  "Worker-1" "Orchestrator"
                  "section-complete"
                  '(:buffer "*Collaborative-Doc*"
                    :section "Introduction")))
```

**Benefits**:
- Parallel work on same document
- Clear section ownership
- Coordinated completion

### Pattern 5: Code Generation Pipeline

**Problem**: Generate, review, and refine code across multiple instances.

**Solution**: Pass code through instances via buffers.

```elisp
;; Generator creates initial code
(with-current-buffer (get-buffer-create "*Generated-Code-v1*")
  (python-mode)
  (insert generated-code))

(claude-ipc-send "Code-Reviewer"
                 (claude-ipc-create-message
                  "Code-Generator"
                  "Code-Reviewer"
                  "review-code"
                  '(:code-buffer "*Generated-Code-v1*"
                    :language "python"
                    :output-buffer "*Code-Review-Comments*")))

;; Reviewer creates comments buffer
(with-current-buffer (get-buffer-create "*Code-Review-Comments*")
  (markdown-mode)
  (insert review-comments))

;; Refiner reads both and creates v2
(with-current-buffer (get-buffer-create "*Generated-Code-v2*")
  (python-mode)
  (insert refined-code))
```

**Benefits**:
- Multiple passes with different perspectives
- Preserves intermediate versions
- Syntax-aware editing

### Creative Example: Multi-Perspective Document Review

**Scenario**: Get diverse feedback on a document by having multiple instances with different personas review it.

```elisp
;; Orchestrator loads document
(with-current-buffer (get-buffer-create "*Document-To-Review*")
  (insert-file-contents "~/docs/proposal.md"))

;; Spawn "Positive Sunshine" - optimistic reviewer
(claude-code-ide-instance--spawn "/Users/jblair/sunshine-positive" "*Positive-Sunshine*")
(claude-ipc-send "Positive-Sunshine"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Positive-Sunshine"
                  "review-document"
                  '(:input-buffer "*Document-To-Review*"
                    :output-buffer "*Positive-Review*"
                    :persona "optimistic"
                    :focus "strengths and opportunities")))

;; Spawn "Negative Sunshine" - critical reviewer
(claude-code-ide-instance--spawn "/Users/jblair/sunshine-negative" "*Negative-Sunshine*")
(claude-ipc-send "Negative-Sunshine"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Negative-Sunshine"
                  "review-document"
                  '(:input-buffer "*Document-To-Review*"
                    :output-buffer "*Critical-Review*"
                    :persona "critical"
                    :focus "risks and weaknesses")))

;; Spawn "Neutral Sunshine" - balanced reviewer
(claude-code-ide-instance--spawn "/Users/jblair/sunshine-neutral" "*Neutral-Sunshine*")
(claude-ipc-send "Neutral-Sunshine"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Neutral-Sunshine"
                  "review-document"
                  '(:input-buffer "*Document-To-Review*"
                    :output-buffer "*Balanced-Review*"
                    :persona "balanced"
                    :focus "objective analysis")))

;; Each reviewer creates their commentary buffer
;; Orchestrator collects all three perspectives
(let ((reviews '()))
  (dolist (reviewer '("Positive-Sunshine" "Negative-Sunshine" "Neutral-Sunshine"))
    (push (claude-ipc-receive reviewer) reviews))
  ;; Synthesize feedback from all perspectives
  (synthesize-reviews reviews))
```

**Use cases**:
- **Red team / Blue team**: Security review with attacker and defender perspectives
- **Technical / Business**: Review with different stakeholder viewpoints
- **Detailed / High-level**: Different levels of abstraction
- **Multiple domains**: Expert reviews from different specializations

### Creative Example: CTF Competition Between Instances

**Scenario**: Multiple Claude instances compete in Capture The Flag challenges or red team vs blue team scenarios.

#### Pattern 1: Red Team vs Blue Team

```elisp
;; Orchestrator sets up vulnerable system in buffer
(with-current-buffer (get-buffer-create "*Target-System*")
  (python-mode)
  (insert vulnerable-web-app-code))

;; Spawn Red Team - offensive security
(claude-code-ide-instance--spawn "/tmp/red-team" "*Red-Team*")
(claude-ipc-send "Red-Team"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Red-Team"
                  "find-vulnerabilities"
                  '(:target-buffer "*Target-System*"
                    :findings-buffer "*Red-Findings*"
                    :exploit-buffer "*Exploit-Code*"
                    :goal "Find and exploit vulnerabilities")))

;; Spawn Blue Team - defensive security
(claude-code-ide-instance--spawn "/tmp/blue-team" "*Blue-Team*")
(claude-ipc-send "Blue-Team"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Blue-Team"
                  "defend-system"
                  '(:target-buffer "*Target-System*"
                    :patches-buffer "*Security-Patches*"
                    :monitoring-buffer "*Defense-Log*"
                    :goal "Identify and fix vulnerabilities")))

;; Red team finds exploit
(claude-ipc-send "Orchestrator"
                 (claude-ipc-create-message
                  "Red-Team"
                  "Orchestrator"
                  "vulnerability-found"
                  '(:type "SQL injection"
                    :location "line 42"
                    :exploit-buffer "*Exploit-Code*"
                    :severity "high")))

;; Blue team patches
(claude-ipc-send "Orchestrator"
                 (claude-ipc-create-message
                  "Blue-Team"
                  "Orchestrator"
                  "patch-applied"
                  '(:vulnerability "SQL injection"
                    :patch-buffer "*Security-Patches*"
                    :line-range (40 . 45))))
```

#### Pattern 2: Multi-Instance CTF Race

```elisp
;; Orchestrator creates CTF challenge
(with-current-buffer (get-buffer-create "*CTF-Challenge-1*")
  (insert ctf-crypto-challenge))

;; Create leaderboard buffer
(with-current-buffer (get-buffer-create "*CTF-Leaderboard*")
  (insert "=== CTF Competition ===\n\n")
  (insert "Scores:\n"))

;; Spawn competing instances
(dolist (team '("Alpha" "Beta" "Gamma" "Delta"))
  (let ((instance-name (format "*Team-%s*" team)))
    (claude-code-ide-instance--spawn
     (format "/tmp/team-%s" (downcase team))
     instance-name)

    ;; Send challenge
    (claude-ipc-send instance-name
                     (claude-ipc-create-message
                      "Orchestrator"
                      instance-name
                      "solve-challenge"
                      `(:challenge-buffer "*CTF-Challenge-1*"
                        :type "crypto"
                        :points 500
                        :time-limit 600)))))

;; Instance submits flag
(claude-ipc-send "Orchestrator"
                 (claude-ipc-create-message
                  "Team-Alpha"
                  "Orchestrator"
                  "flag-submission"
                  '(:challenge-id 1
                    :flag "CTF{cr4ck3d_th3_c1ph3r}"
                    :solution-buffer "*Alpha-Solution*"
                    :time-elapsed 342)))

;; Orchestrator validates and updates leaderboard
(with-current-buffer "*CTF-Leaderboard*"
  (goto-char (point-max))
  (insert (format "[%s] Team-Alpha: +500 points (342s)\n"
                  (current-time-string))))
```

#### Pattern 3: Specialized Attack Team

```elisp
;; Orchestrator distributes challenges by specialty

;; Crypto specialist
(claude-ipc-send "Crypto-Specialist"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Crypto-Specialist"
                  "solve-crypto"
                  '(:challenge-buffer "*Crypto-Challenge*"
                    :hint "RSA with weak key")))

;; Web exploitation specialist
(claude-ipc-send "Web-Hacker"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Web-Hacker"
                  "exploit-webapp"
                  '(:target-url "http://localhost:8080"
                    :source-buffer "*WebApp-Source*"
                    :goal "Gain admin access")))

;; Reverse engineering specialist
(claude-ipc-send "Reverse-Engineer"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Reverse-Engineer"
                  "analyze-binary"
                  '(:binary-buffer "*Binary-Challenge*"
                    :disassembly-buffer "*Disassembly*"
                    :goal "Find flag in binary")))

;; Forensics specialist
(claude-ipc-send "Forensics-Analyst"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Forensics-Analyst"
                  "analyze-pcap"
                  '(:pcap-buffer "*Network-Capture*"
                    :analysis-buffer "*Traffic-Analysis*"
                    :goal "Extract credentials")))
```

#### Pattern 4: Attack/Defend Tournament

```elisp
;; Each instance maintains and defends their own service
;; while trying to attack others

;; Instance maintains service
(with-current-buffer (get-buffer-create "*Team-Alpha-Service*")
  (insert service-code))

;; Instance receives attack notification
(claude-ipc-send "Team-Alpha"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Team-Alpha"
                  "under-attack"
                  '(:attacker "Team-Beta"
                    :attack-type "buffer-overflow"
                    :service-buffer "*Team-Alpha-Service*"
                    :defense-required t)))

;; Instance launches attack on opponent
(claude-ipc-send "Orchestrator"
                 (claude-ipc-create-message
                  "Team-Alpha"
                  "Orchestrator"
                  "launch-attack"
                  '(:target "Team-Gamma"
                    :exploit-buffer "*Alpha-Exploit-3*"
                    :vulnerability "command-injection")))

;; Orchestrator adjudicates
(claude-ipc-send "Team-Gamma"
                 (claude-ipc-create-message
                  "Orchestrator"
                  "Team-Gamma"
                  "attack-successful"
                  '(:attacker "Team-Alpha"
                    :points-lost 100
                    :service-compromised t)))
```

**Competition Modes:**
- **Speed**: First to solve wins
- **Quality**: Best exploit or most thorough analysis
- **Stealth**: Most subtle attack/best detection evasion
- **Defense**: Best patches or hardening
- **Collaborative**: Team combines specialized instances

**Coordination via Message Queue:**
- `flag-submission`: Submit solution with proof
- `vulnerability-found`: Report discovered weakness
- `exploit-attempt`: Try to compromise target
- `defense-update`: Apply security measure
- `score-update`: Leaderboard changes
- `hint-request`: Ask for help (penalty)

**Benefits:**
- **Safe environment**: Test attacks without real targets
- **Learning**: Study different approaches simultaneously
- **Benchmarking**: Compare different strategies
- **Training**: Prepare for real CTFs or security work
- **Fun**: Competitive AI problem-solving!

### Best Practices for Buffer References

1. **Use descriptive buffer names**: `*Task-Results-123*` not `*tmp*`
2. **Clean up buffers**: Delete when no longer needed to avoid clutter
3. **Namespace by task**: Include request-id or task-id in buffer name
4. **Set appropriate modes**: Use `python-mode`, `json-mode`, `markdown-mode` for syntax
5. **Document buffer format**: Specify in message (`:format "json"`)
6. **Handle buffer conflicts**: Check if buffer exists before creating
7. **Use temporary buffers**: Prefix with space for internal buffers (` *internal*`)

### Buffer Reference Message Schema

Recommended payload structure for buffer references:

```elisp
(:input-buffer BUFFER-NAME     ; Buffer to read from (optional)
 :output-buffer BUFFER-NAME    ; Buffer to write to (optional)
 :format FORMAT-STRING         ; "json", "markdown", "python", etc.
 :mode MODE-SYMBOL            ; Major mode for buffer (optional)
 :line-range (START . END)    ; Section to process (optional)
 :encoding ENCODING-STRING    ; "utf-8", etc. (optional)
 :read-only BOOLEAN)          ; If true, don't modify input (optional)
```

**Example**:
```elisp
(:input-buffer "*Source-Data*"
 :output-buffer "*Analysis-Results*"
 :format "markdown"
 :mode 'markdown-mode
 :read-only t)
```

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
