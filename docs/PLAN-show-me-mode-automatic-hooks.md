# Show Me Mode: Automatic Hooks Implementation Plan

**Status**: Future Enhancement
**Created**: 2025-11-27
**Related**: ide-visibility-mode.md

---

## Problem Statement

**Current implementation:** Show Me mode requires manual eval calls after each Read/Edit/Write tool to display files in Windows 3 and 4.

**Limitation:** This is inefficient and requires repetitive code after every tool use.

---

## Proposed Solution

Hook file display directly into tool execution, similar to how the existing diff hook works in claude-code-ide.

**Automatic behavior:**
- After Read tool → automatically display file in Window 4 (top-right)
- After Edit/Write tools → automatically display file in Window 3 (bottom-right)
- Only when visibility mode and "show me" are active

---

## Implementation Approach

### 1. After-Read Hook

```elisp
(defun claude-code-ide-after-read-hook (file-path start-line)
  "Automatically display read files in Window 4 when Show Me mode is active."
  (when (and claude-visibility-show-me-active
             (claude-visibility-grid-valid-p))
    (let ((window-4 (claude-visibility-get-window 4)))
      (when window-4
        (let ((file-size (nth 7 (file-attributes file-path))))
          (when (and file-size (<= file-size 131072))  ; 128KB limit
            (let ((buf (find-file-noselect file-path)))
              (set-window-buffer window-4 buf)
              (with-selected-window window-4
                (goto-char (point-min))
                (when start-line
                  (forward-line start-line))
                (recenter)))))))))
```

### 2. After-Edit/Write Hook

```elisp
(defun claude-code-ide-after-edit-hook (file-path edit-line)
  "Automatically display edited files in Window 3 when Show Me mode is active."
  (when (and claude-visibility-show-me-active
             (claude-visibility-grid-valid-p))
    (let ((window-3 (claude-visibility-get-window 3)))
      (when window-3
        (let ((file-size (nth 7 (file-attributes file-path))))
          (when (and file-size (<= file-size 131072))  ; 128KB limit
            (let ((buf (find-file-noselect file-path)))
              (set-window-buffer window-3 buf)
              (with-selected-window window-3
                (goto-char (point-min))
                (when edit-line
                  (forward-line (1- edit-line)))
                (recenter)))))))))
```

### 3. Integration Points

**Where to hook:**
- `claude-code-ide-mcp-handlers.el` - MCP tool handlers for Read/Edit/Write
- Add hooks at the end of each tool's execution
- Pass file path and position information to hook functions

**Example integration:**
```elisp
(defun claude-code-ide-handle-read (file-path offset limit)
  "Handle Read tool MCP request."
  ;; ... existing read logic ...
  (let ((result ...))
    ;; Call the hook after successful read
    (claude-code-ide-after-read-hook file-path offset)
    result))
```

---

## Benefits

1. **Seamless UX**: No manual eval calls needed after every Read/Edit/Write
2. **Consistency**: Follows existing diff hook pattern in claude-code-ide
3. **Automatic**: Windows update as Claude works, user sees progress
4. **Less duplication**: Hook logic centralized, not repeated in prompts

---

## Challenges & Considerations

### 1. Coordination with Existing Diff Hook

**Issue:** claude-code-ide already has a diff hook that shows file changes, which can:
- Create new windows
- Destroy the 2x2 grid
- Prompt users for confirmation

**Solution approaches:**
- Disable diff hook when Show Me mode is active
- Coordinate both hooks to display in designated windows
- Make diff hook respect the grid structure

### 2. Grid Stability

**Issue:** Automatic window manipulation could break the grid.

**Solution:**
- Always check `claude-visibility-grid-valid-p` before displaying
- Optionally auto-restore grid if broken
- Add safeguards against recursive hook calls

### 3. Performance

**Issue:** Displaying files after every tool use could be slow.

**Solution:**
- Skip very large files (> 128KB)
- Skip binary files
- Only activate when user explicitly enables "show me"
- Consider debouncing rapid tool calls

### 4. State Management

**Issue:** Need to track whether "show me" mode is active.

**Solution:**
```elisp
(defvar claude-visibility-show-me-active nil
  "Whether Show Me mode is currently active.")

(defun claude-visibility-show-me-enable ()
  "Enable Show Me mode."
  (interactive)
  (setq claude-visibility-show-me-active t)
  (message "Show Me mode enabled"))

(defun claude-visibility-show-me-disable ()
  "Disable Show Me mode."
  (interactive)
  (setq claude-visibility-show-me-active nil)
  (message "Show Me mode disabled"))
```

---

## Implementation Steps

1. **Define hook functions** (after-read-hook, after-edit-hook)
2. **Add state management** (enable/disable show me mode)
3. **Integrate with MCP handlers** (call hooks after tool execution)
4. **Test with grid stability** (ensure no breakage)
5. **Coordinate with diff hook** (avoid conflicts)
6. **Add user commands** (enable/disable show me mode)
7. **Document behavior** (update user-facing docs)

---

## Testing Plan

1. **Basic functionality:**
   - Read file → appears in Window 4
   - Edit file → appears in Window 3
   - No manual eval needed

2. **Grid stability:**
   - Multiple reads/edits in sequence
   - Grid remains intact
   - Windows don't multiply

3. **Performance:**
   - Large files skipped
   - Binary files skipped
   - No noticeable lag

4. **Edge cases:**
   - Grid broken → no display attempt
   - Show me disabled → no automatic display
   - File doesn't exist → graceful failure

---

## Related Work

- **Existing diff hook**: Needs investigation and coordination
- **Grid restoration**: Already have `claude-visibility-restore-grid`
- **Window identification**: Already have `claude-visibility-get-window`

---

## Success Criteria

- [ ] Show Me mode can be enabled/disabled via command
- [ ] Read tool automatically displays in Window 4
- [ ] Edit/Write tools automatically display in Window 3
- [ ] Grid remains stable during automatic updates
- [ ] No conflicts with existing diff hook
- [ ] Performance is acceptable (no user-visible lag)
- [ ] Works reliably across multiple sessions

---

## Notes

- This plan assumes the existing diff hook behavior will be addressed
- May need to make diff hook "grid-aware"
- Consider adding this as an opt-in feature initially
- Could expand to other tools (Grep, Glob) showing results in designated windows
