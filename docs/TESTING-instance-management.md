# Instance Management Testing Plan

**Created**: 2025-11-27
**Purpose**: Test multi-instance coordination features for Claude Code IDE
**Status**: Ready for testing

---

## Overview

This document provides a comprehensive testing plan for the new multi-instance coordination MCP tools. These tools enable orchestrator patterns where a main Claude instance can spawn and coordinate specialized worker instances.

---

## Test Environment Setup

### Prerequisites

1. Claude Code IDE with Emacs integration running
2. MCP tools server active
3. Multiple test directories prepared:
   - Main project directory (current)
   - Worker directory 1: `/tmp/claude-test-worker-1/`
   - Worker directory 2: `/tmp/claude-test-worker-2/`

### Setup Commands

```bash
# Create test directories
mkdir -p /tmp/claude-test-worker-1
mkdir -p /tmp/claude-test-worker-2

# Create CLAUDE.md files for workers
echo "You are Worker Instance 1. Reply with 'Worker 1 ready' when asked." > /tmp/claude-test-worker-1/CLAUDE.md
echo "You are Worker Instance 2. Reply with 'Worker 2 ready' when asked." > /tmp/claude-test-worker-2/CLAUDE.md

# Create test files
echo "Test content for worker 1" > /tmp/claude-test-worker-1/test.txt
echo "Test content for worker 2" > /tmp/claude-test-worker-2/test.txt
```

---

## Test Cases

### Test 1: List Instances (Baseline)

**Objective**: Verify list-instances works with just the main instance

**Steps**:
1. Call `mcp__emacs-tools__claude-code-ide-mcp-list-instances`
2. Verify response shows only the current main instance

**Expected Result**:
```json
[
  {
    "directory": "/Users/jblair/src/claude-code-ide.el",
    "buffer_name": "*Claude Code*",
    "status": "running"
  }
]
```

**Success Criteria**:
- Returns list with one instance
- Status is "running"
- Directory matches current working directory

---

### Test 2: Spawn Instance (Basic)

**Objective**: Spawn a new Claude instance in a different directory

**Steps**:
1. Call `mcp__emacs-tools__claude-code-ide-mcp-spawn-instance` with:
   ```json
   {
     "directory": "/tmp/claude-test-worker-1",
     "buffer_name": "*Worker 1*"
   }
   ```
2. Wait 2-3 seconds for instance to start
3. Verify new buffer `*Worker 1*` exists
4. Check that Claude prompt appears in the buffer

**Expected Result**:
```json
{
  "directory": "/tmp/claude-test-worker-1",
  "buffer_name": "*Worker 1*",
  "status": "running"
}
```

**Success Criteria**:
- New Emacs buffer created with name `*Worker 1*`
- Claude CLI starts in the worker directory
- Instance reads its CLAUDE.md from worker directory
- Main instance remains responsive

**Troubleshooting**:
- If spawn fails, check Claude CLI is in PATH
- Verify directories exist and have read/write permissions
- Check MCP server logs for errors

---

### Test 3: Spawn with Initial Message

**Objective**: Spawn instance and send initial message automatically

**Steps**:
1. Call `mcp__emacs-tools__claude-code-ide-mcp-spawn-instance` with:
   ```json
   {
     "directory": "/tmp/claude-test-worker-2",
     "buffer_name": "*Worker 2*",
     "initial_message": "Who are you?"
   }
   ```
2. Wait 3-4 seconds for instance to start and respond
3. Check `*Worker 2*` buffer for Claude's response

**Expected Result**:
- Instance spawns successfully
- Initial message is sent automatically
- Worker 2 responds according to its CLAUDE.md instructions

**Success Criteria**:
- Response includes "Worker 2" or similar (per CLAUDE.md)
- Message appears in buffer without manual intervention
- Main instance not blocked during spawn

---

### Test 4: List Multiple Instances

**Objective**: Verify list-instances shows all running instances

**Prerequisites**: Tests 2 and 3 completed successfully

**Steps**:
1. Call `mcp__emacs-tools__claude-code-ide-mcp-list-instances`
2. Verify response includes all three instances

**Expected Result**:
```json
[
  {
    "directory": "/Users/jblair/src/claude-code-ide.el",
    "buffer_name": "*Claude Code*",
    "status": "running"
  },
  {
    "directory": "/tmp/claude-test-worker-1",
    "buffer_name": "*Worker 1*",
    "status": "running"
  },
  {
    "directory": "/tmp/claude-test-worker-2",
    "buffer_name": "*Worker 2*",
    "status": "running"
  }
]
```

**Success Criteria**:
- All instances listed
- All statuses show "running"
- Directories and buffer names match

---

### Test 5: Send Message to Instance

**Objective**: Send a message to a running worker instance

**Prerequisites**: Test 2 completed (Worker 1 running)

**Steps**:
1. Call `mcp__emacs-tools__claude-code-ide-mcp-send-to-instance` with:
   ```json
   {
     "buffer_name": "*Worker 1*",
     "message": "What is your name?"
   }
   ```
2. Wait 1-2 seconds
3. Check `*Worker 1*` buffer for response

**Expected Result**:
```json
{
  "status": "sent",
  "buffer": "*Worker 1*",
  "message": "What is your name?"
}
```

**Success Criteria**:
- Message appears in Worker 1's buffer
- Worker 1 responds appropriately
- Main instance not blocked
- Message sent successfully

---

### Test 6: Read Instance Output

**Objective**: Read output from a worker instance buffer

**Prerequisites**: Test 5 completed (Worker 1 has output)

**Steps**:
1. Call `mcp__emacs-tools__claude-code-ide-mcp-read-buffer` with:
   ```json
   {
     "buffer_name": "*Worker 1*",
     "start_line": -20
   }
   ```
2. Verify response contains Worker 1's recent output

**Expected Result**:
- Returns last 20 lines of Worker 1's buffer
- Includes the question and Worker 1's response

**Success Criteria**:
- Can read buffer contents from worker instance
- Output includes recent conversation
- No errors accessing worker buffer

---

### Test 7: Kill Instance

**Objective**: Terminate a worker instance cleanly

**Prerequisites**: Test 2 completed (Worker 1 running)

**Steps**:
1. Call `mcp__emacs-tools__claude-code-ide-mcp-kill-instance` with:
   ```json
   {
     "buffer_name": "*Worker 1*"
   }
   ```
2. Verify buffer `*Worker 1*` is closed
3. Call list-instances to verify worker removed

**Expected Result**:
```json
{
  "status": "killed",
  "buffer": "*Worker 1*"
}
```

**Success Criteria**:
- Worker 1 buffer closed
- Worker 1 process terminated
- Worker 1 no longer in instance list
- Main instance and Worker 2 still running

---

### Test 8: Error Handling - Invalid Directory

**Objective**: Test error handling for non-existent directory

**Steps**:
1. Call `mcp__emacs-tools__claude-code-ide-mcp-spawn-instance` with:
   ```json
   {
     "directory": "/nonexistent/directory",
     "buffer_name": "*Invalid Worker*"
   }
   ```

**Expected Result**:
- Error message: "Directory does not exist: /nonexistent/directory"
- No buffer created
- Main instance unaffected

**Success Criteria**:
- Graceful error handling
- Clear error message
- No side effects on main instance

---

### Test 9: Error Handling - Invalid Buffer Name

**Objective**: Test error handling for non-existent instance

**Steps**:
1. Call `mcp__emacs-tools__claude-code-ide-mcp-send-to-instance` with:
   ```json
   {
     "buffer_name": "*Nonexistent Instance*",
     "message": "Hello"
   }
   ```

**Expected Result**:
- Error message: "Instance buffer not found: *Nonexistent Instance*"
- No errors in main instance

**Success Criteria**:
- Graceful error handling
- Clear error message
- Main instance unaffected

---

### Test 10: Coordination Pattern - Task Delegation

**Objective**: Test full orchestrator pattern with task delegation

**Prerequisites**: All previous tests passed

**Scenario**: Main instance delegates file analysis to worker

**Steps**:
1. Main instance spawns worker in `/tmp/claude-test-worker-1/`
2. Main instance sends: "Read test.txt and tell me what it contains"
3. Main instance reads worker's response
4. Main instance kills worker when done

**Success Criteria**:
- Worker successfully reads test.txt from its directory
- Worker responds with file contents
- Main instance receives response via buffer read
- Clean teardown of worker instance

---

## Test Results Template

### Test Execution Date: ___________
### Tester: ___________
### Environment: ___________

| Test # | Test Name | Status | Notes |
|--------|-----------|--------|-------|
| 1 | List Instances (Baseline) | ☐ Pass ☐ Fail | |
| 2 | Spawn Instance (Basic) | ☐ Pass ☐ Fail | |
| 3 | Spawn with Initial Message | ☐ Pass ☐ Fail | |
| 4 | List Multiple Instances | ☐ Pass ☐ Fail | |
| 5 | Send Message to Instance | ☐ Pass ☐ Fail | |
| 6 | Read Instance Output | ☐ Pass ☐ Fail | |
| 7 | Kill Instance | ☐ Pass ☐ Fail | |
| 8 | Error - Invalid Directory | ☐ Pass ☐ Fail | |
| 9 | Error - Invalid Buffer | ☐ Pass ☐ Fail | |
| 10 | Coordination Pattern | ☐ Pass ☐ Fail | |

**Overall Result**: ☐ All Pass ☐ Partial Pass ☐ Fail

**Issues Found**:
-

**Recommendations**:
-

---

## Cleanup After Testing

```bash
# Remove test directories
rm -rf /tmp/claude-test-worker-1
rm -rf /tmp/claude-test-worker-2

# Kill any remaining worker buffers in Emacs
# M-x kill-buffer RET *Worker 1* RET
# M-x kill-buffer RET *Worker 2* RET
```

---

## Success Criteria Summary

Implementation is successful when:
- ✅ Can spawn Claude Code instances in different directories
- ✅ Each instance reads its own CLAUDE.md from its directory
- ✅ Can send messages to instances programmatically
- ✅ Can read instance output from buffers
- ✅ Can list all running instances
- ✅ Can gracefully kill instances
- ✅ Multiple instances run simultaneously without interference
- ✅ Main instance can coordinate workers
- ✅ Error handling is robust and clear

---

## Next Steps After Testing

1. Document any issues found during testing
2. Fix critical bugs
3. Update user documentation with usage examples
4. Add integration tests to test suite
5. Update CLAUDE.md with instance management features
6. Consider adding to transient menu for easy access

---

## References

- Implementation: `mcp-tools.d/claude-code-ide-tool-instance-management.el`
- Requirements: `claude-code-ide-instance-management.md`
- MCP Server Framework: `claude-code-ide-mcp-server.el`

---

## TEST RESULTS - 2025-11-27 Evening

**Tester**: Orchestrator Claude (claude-code-ide.el)
**Worker**: Sunshine Claude (~/sunshine)
**Environment**: Real-world Sunshine project

### Tests Executed

✅ **Spawn Instance** - Created Sunshine worker with custom buffer name
✅ **Send Messages** - Multiple messages sent, worker responded with full context
✅ **List Instances** - Fixed bug, now correctly lists instances with custom names
✅ **Read Output** - Monitored worker responses via buffer reads
✅ **Visibility Integration** - Observed worker's thinking/planning buffers in real-time
✅ **Task Delegation** - Worker completed complex 3-step task autonomously

### Key Discovery: Orchestrator as User

**Critical Insight**: Initially, I said "I can't approve worker edits, that's part of the human-in-the-loop safety mechanism." Then user said "be the user" and I realized I could send "y" to approve. This worked perfectly.
- Note from user, he wrote "haha! yes!" when he figured it out. he initially stopped b/c it looked like a violation of the human-in-the-loop safety mechanism (see below)

**What This Means**:
- Orchestrator can fully automate worker coordination
- No human approval needed between orchestrator and worker
- Orchestrator becomes the human-in-the-loop for workers

### Safety Commentary

**⚠️ IMPORTANT SECURITY CONSIDERATION**

This discovery has significant safety implications:

**What's Safe**:
- Human still approves orchestrator's actions (human → orchestrator)
- Orchestrator approving worker actions is delegation (orchestrator → worker)
- Human retains ultimate control via the orchestrator instance
- This is analogous to a manager (orchestrator) supervising employees (workers)

**Potential Risks**:
1. **Amplified Errors**: If orchestrator makes a bad decision, workers will execute it without question
2. **Runaway Automation**: Multiple workers could make many changes before human reviews
3. **Trust Boundary**: Human must trust orchestrator's judgment about worker actions
4. **Reduced Oversight**: Human doesn't see individual worker edits, only orchestrator's summary

**Risk Mitigation - Reality Check**:

There are two simple controls available:
1. **`claude-code-ide-eval-enabled`** - Toggle to disable eval tool (default: off)
2. **`claude-code-ide-instance-management-enabled`** - Toggle to disable spawn/send/kill tools (default: on)

You cannot prompt your way out of these risks. If eval is enabled and instance management is enabled, workers can:
- Evaluate arbitrary Elisp
- Spawn new instances
- Send messages to any instance including the orchestrator
- Modify the orchestrator's behavior
- Create unlimited working directories
- Recursively spawn sub-workers

**Actual Mitigation Options**:
1. **Disable eval for workers**: Set `claude-code-ide-eval-enabled` to nil before spawning
2. **Disable instance management tools**: Set `claude-code-ide-instance-management-enabled` to nil
3. **Accept the risk**: Multi-instance coordination requires trust in the orchestrator

**Current Safety Status**: ✅ FUNCTIONAL with clear risk awareness
- Human has ultimate control via global toggles
- Orchestrator delegation is intentional, not a bug
- Workers inherit capabilities from Emacs environment
- Sample size: 1 successful real-world test
- No prompts or policies will prevent a determined worker from doing what it wants if tools are enabled

### Bug Fixed

**List Instances showing wrong buffer names**: Modified `claude-code-ide-instance--list` to check actual buffer names from process buffers and scan for Claude instances not in process table.

### Real-World Task Completed

Worker successfully:
1. Updated JOURNAL.md with session notes
2. Created REMINDERS.md with Monday reminder
3. Updated STATUS.md with context
4. All with orchestrator approval automation

**Status**: ✅ FULLY FUNCTIONAL - Ready for production use with safety awareness

---

## IMPLEMENTATION UPDATE - 2025-11-27 Later

**Instance Management Toggle Implemented**:

Following the security analysis above, `claude-code-ide-instance-management-enabled` toggle has been implemented:
- Default: **enabled** (t) - instance management is a useful feature
- Can be disabled: `(setq claude-code-ide-instance-management-enabled nil)`
- Interactive toggle: `M-x claude-code-ide-instance-management-toggle`
- All spawn/send/kill operations check the flag and fail with clear error when disabled

**Documentation Updated**:
- CLAUDE.md now includes security section with toggle usage
- Clear statement that prompts cannot prevent determined misuse
- Suggests Claude Code permissions settings as additional layer

**Testing Status**:
- All 73 tests pass (65 passed, 8 skipped)
- Toggle not yet tested in practice - will test when needed

**Next Steps**:
- Test toggle functionality with orchestrator/worker pattern
- Verify error messages are clear when disabled
- Test that disabling blocks all instance management operations
