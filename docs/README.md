# Claude Code IDE Documentation

This directory contains design documents, implementation plans, and testing guides for Claude Code IDE features.

---

## Feature Documentation

### Instance Management (Multi-Instance Coordination)

**Status**: ⚠️ Implemented (MCP tools not yet available)

Enables orchestrator patterns where a main Claude instance can spawn and coordinate specialized worker instances with different contexts.

- **[Requirements & Architecture](claude-code-ide-instance-management.md)** - Comprehensive design document covering use cases, implementation approach, and API design
- **[Testing Plan](TESTING-instance-management.md)** - Complete test suite with 10 test cases, setup instructions, and success criteria

**Key Capabilities**:
- Spawn new Claude instances in different directories
- Send messages to running instances programmatically
- List all running instances with status
- Clean instance lifecycle management
- Structured message queue IPC system for efficient coordination
- Buffer reference passing for large data transfer
- Multi-perspective workflows with specialized worker personas

**Advanced Patterns**:
- **Message Queue IPC** - Structured communication with correlation IDs, avoiding vterm message parsing
- **Buffer References** - Pass buffer names in messages for large data, formatted results, real-time monitoring
- **Multi-Perspective Review** - Spawn multiple workers with different personas (positive/negative/neutral) to analyze same input
- **Creative Applications** - CTF competitions, collaborative editing, code review pipelines

**Implementation**: `mcp-tools.d/claude-code-ide-tool-instance-management.el`

**Current Limitation**: MCP tools are not yet exposed via the MCP server interface. Use the eval tool as a workaround:

```elisp
;; Load the module first
(load-file "/path/to/mcp-tools.d/claude-code-ide-tool-instance-management.el")

;; Spawn an instance
(let ((result (claude-code-ide-instance--spawn
                "/path/to/directory"
                "*Custom-Buffer-Name*"
                "Initial message")))
  ;; Display in a window
  (set-window-buffer (selected-window)
                     (get-buffer (plist-get result :buffer-name))))

;; Send a message to an instance (basic)
(claude-code-ide-instance--send-message "*Custom-Buffer-Name*" "Your message")

;; OR use structured message queue (advanced)
(claude-ipc-send "*Custom-Buffer-Name*"
                 (claude-ipc-create-message
                  "orchestrator"
                  "*Custom-Buffer-Name*"
                  "task"
                  '(:action "analyze" :data "content")))

;; Receive messages from queue
(claude-ipc-receive "*Custom-Buffer-Name*")

;; List all instances
(claude-code-ide-instance--list)

;; Kill an instance
(claude-code-ide-instance--kill "*Custom-Buffer-Name*")
```

See the [architecture document](claude-code-ide-instance-management.md) for complete documentation of the message queue IPC system and advanced patterns.

---

### Show Me Mode (Automatic Visual Mode)

**Status**: 📋 Planned

Proposal for automatically displaying files in visibility mode windows as they are read or edited by Claude.

- **[Implementation Plan](PLAN-show-me-mode-automatic-hooks.md)** - Design for hooking file display into Read/Edit/Write tool execution

**Proposed Features**:
- Automatic display of read files in Window 4
- Automatic display of edited files in Window 3
- Integration with existing diff hook
- Configurable enable/disable

**Implementation**: Planned for future enhancement

---

## Additional Resources

### Main Project Documentation

- **[CLAUDE.md](../CLAUDE.md)** - Primary guidance for Claude when working on this project
  - Architecture overview
  - Testing procedures
  - Security considerations
  - Multi-instance coordination usage

### Code Organization

- **Core**: `claude-code-ide*.el` files in root directory
- **Modular Tools**: `mcp-tools.d/` directory
  - Buffer management tools
  - Emacs Lisp eval tool
  - Instance management tools (NEW)
  - LSP-aware xref tools

### Testing

- **Test Suite**: `claude-code-ide-tests.el`
- **Test Execution**: See CLAUDE.md for commands
- **Interactive Testing**: Follow procedures in TESTING-*.md documents

---

## Document Types

This directory contains several types of documents:

- **Requirements/Architecture** (`*.md` without prefix) - Design specifications and architecture decisions
- **Plans** (`PLAN-*.md`) - Implementation plans for future work
- **Testing** (`TESTING-*.md`) - Test plans and procedures
- **Guides** (`GUIDE-*.md`) - User and developer guides (future)

---

## Contributing Documentation

When adding new features to Claude Code IDE:

1. Create design document with requirements and architecture
2. Create test plan with comprehensive test cases
3. Update CLAUDE.md with feature overview
4. Update this README.md with links to new documents
5. Follow naming conventions:
   - `feature-name.md` for requirements/architecture
   - `PLAN-feature-name.md` for implementation plans
   - `TESTING-feature-name.md` for test plans

---

**Last Updated**: 2025-11-27
