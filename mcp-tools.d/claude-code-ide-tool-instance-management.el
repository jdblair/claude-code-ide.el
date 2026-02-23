;;; claude-code-ide-tool-instance-management.el --- Multi-instance coordination MCP tools  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Jeremy Blair
;; Keywords: ai, claude, mcp, tools, instances

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This file provides MCP tools for multi-instance coordination in Claude Code IDE.
;; It enables:
;; - Spawning new Claude Code instances in different directories
;; - Sending messages to running instances
;; - Listing all running instances
;; - Managing instance lifecycle
;;
;; This supports orchestrator patterns where a main Claude instance can delegate
;; work to specialized instances with different contexts and instruction sets.
;;
;; Security: These tools allow spawning and controlling additional Claude
;; instances. Workers can potentially spawn sub-workers, send messages to
;; any instance including the orchestrator, and create unlimited working
;; directories. Use with caution and only enable when needed.

;;; Code:

(require 'claude-code-ide-mcp-server)
(require 'claude-code-ide-debug)

;;; Customization

(defcustom claude-code-ide-instance-management-enabled t
  "Enable instance management MCP tools.
When nil, tools will refuse to spawn, send, or kill instances.
Set to t to enable instance management."
  :type 'boolean
  :group 'claude-code-ide)

;; Forward declarations for main claude-code-ide functions
(declare-function claude-code-ide--start-session "claude-code-ide")
(declare-function claude-code-ide--get-process "claude-code-ide")
(declare-function claude-code-ide--terminal-send-string "claude-code-ide")
(declare-function claude-code-ide--terminal-send-return "claude-code-ide")
(declare-function claude-code-ide--cleanup-dead-processes "claude-code-ide")

;; External variables from claude-code-ide.el
(defvar claude-code-ide--processes)
(defvar claude-code-ide-buffer-name-function)

;;; Implementation Functions

(defun claude-code-ide-instance--spawn (directory buffer-name initial-message)
  "Spawn a new Claude Code instance in DIRECTORY with BUFFER-NAME.
If INITIAL-MESSAGE is non-nil, send it to the instance after spawning.
Returns information about the spawned instance."
  ;; Check if instance management is enabled
  (unless claude-code-ide-instance-management-enabled
    (error "Instance management is disabled. Set claude-code-ide-instance-management-enabled to t to enable"))

  (unless (file-directory-p directory)
    (error "Directory does not exist: %s" directory))

  (let ((default-directory (expand-file-name directory))
        (custom-buffer-name buffer-name))
    ;; Temporarily override buffer name function if custom name provided
    (let ((orig-buffer-name-fn claude-code-ide-buffer-name-function))
      (when custom-buffer-name
        (setq claude-code-ide-buffer-name-function
              (lambda (_dir) custom-buffer-name)))
      (unwind-protect
          (progn
            ;; Start the session (this will use the temporary buffer name function)
            (claude-code-ide--start-session)

            ;; Wait for terminal to be ready
            (sleep-for 0.5)

            ;; Send initial message if provided
            (when (and initial-message
                       (not (string-empty-p initial-message))
                       custom-buffer-name
                       (get-buffer custom-buffer-name))
              (with-current-buffer custom-buffer-name
                ;; Wait a bit more for Claude to be fully initialized
                (sleep-for 1.0)
                (claude-code-ide--terminal-send-string initial-message)
                (sit-for 0.1)
                (claude-code-ide--terminal-send-return)))

            ;; Return instance information
            (list :directory directory
                  :buffer-name (or custom-buffer-name
                                   (funcall claude-code-ide-buffer-name-function directory))
                  :status "running"))
        ;; Restore original buffer name function
        (setq claude-code-ide-buffer-name-function orig-buffer-name-fn)))))

(defun claude-code-ide-instance--send-message (buffer-name message)
  "Send MESSAGE to the Claude Code instance with BUFFER-NAME.
Returns success status."
  ;; Check if instance management is enabled
  (unless claude-code-ide-instance-management-enabled
    (error "Instance management is disabled. Set claude-code-ide-instance-management-enabled to t to enable"))

  (let ((buffer (get-buffer buffer-name)))
    (if (not buffer)
        (error "Instance buffer not found: %s" buffer-name)
      (if (not (buffer-live-p buffer))
          (error "Instance buffer is not alive: %s" buffer-name)
        (with-current-buffer buffer
          (claude-code-ide--terminal-send-string message)
          (sit-for 0.1)
          (claude-code-ide--terminal-send-return)
          (list :status "sent"
                :buffer buffer-name
                :message message))))))

(defun claude-code-ide-instance--list ()
  "List all running Claude Code instances.
Returns a list of instance information."
  ;; Clean up dead processes first
  (claude-code-ide--cleanup-dead-processes)

  (let ((instances '())
        (seen-buffers (make-hash-table :test 'equal)))
    ;; First, collect instances from the process table
    (maphash (lambda (directory process)
               (let* ((buffer (process-buffer process))
                      (buffer-name (when (buffer-live-p buffer)
                                     (buffer-name buffer)))
                      (status (if (and buffer-name (buffer-live-p buffer))
                                  "running"
                                "dead")))
                 (when buffer-name
                   (puthash buffer-name t seen-buffers)
                   (push (list :directory directory
                               :buffer-name buffer-name
                               :status status)
                         instances))))
             claude-code-ide--processes)

    ;; Also check for any Claude Code buffers not in the process table
    ;; (handles custom buffer names from spawn-instance)
    (dolist (buffer (buffer-list))
      (let ((buffer-name (buffer-name buffer)))
        (when (and (not (gethash buffer-name seen-buffers))
                   (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (and (boundp 'claude-code-ide--session-directory)
                          claude-code-ide--session-directory)))
          (with-current-buffer buffer
            (push (list :directory claude-code-ide--session-directory
                        :buffer-name buffer-name
                        :status "running")
                  instances)))))

    (nreverse instances)))

(defun claude-code-ide-instance--kill (buffer-name)
  "Kill the Claude Code instance with BUFFER-NAME.
Returns success status."
  ;; Check if instance management is enabled
  (unless claude-code-ide-instance-management-enabled
    (error "Instance management is disabled. Set claude-code-ide-instance-management-enabled to t to enable"))

  (let ((buffer (get-buffer buffer-name)))
    (if (not buffer)
        (error "Instance buffer not found: %s" buffer-name)
      (kill-buffer buffer)
      (list :status "killed"
            :buffer buffer-name))))

;;; MCP Tool Handlers

(defun claude-code-ide-mcp-spawn-instance (args)
  "MCP tool handler for spawning a new Claude Code instance.
ARGS should contain:
  :directory - Working directory for the new instance (required)
  :buffer_name - Custom buffer name (optional)
  :initial_message - Message to send after spawning (optional)"
  (claude-code-ide-mcp-server-with-session-context nil
    (let ((directory (plist-get args :directory))
          (buffer-name (plist-get args :buffer_name))
          (initial-message (plist-get args :initial_message)))
      (unless directory
        (error "directory parameter is required"))
      (claude-code-ide-instance--spawn directory buffer-name initial-message))))

(defun claude-code-ide-mcp-send-to-instance (args)
  "MCP tool handler for sending a message to an instance.
ARGS should contain:
  :buffer_name - Name of the instance buffer (required)
  :message - Message to send (required)"
  (claude-code-ide-mcp-server-with-session-context nil
    (let ((buffer-name (plist-get args :buffer_name))
          (message (plist-get args :message)))
      (unless buffer-name
        (error "buffer_name parameter is required"))
      (unless message
        (error "message parameter is required"))
      (claude-code-ide-instance--send-message buffer-name message))))

(defun claude-code-ide-mcp-list-instances (&optional _args)
  "MCP tool handler for listing all running instances.
ARGS is ignored."
  (claude-code-ide-mcp-server-with-session-context nil
    (claude-code-ide-instance--list)))

(defun claude-code-ide-mcp-kill-instance (args)
  "MCP tool handler for killing an instance.
ARGS should contain:
  :buffer_name - Name of the instance buffer to kill (required)"
  (claude-code-ide-mcp-server-with-session-context nil
    (let ((buffer-name (plist-get args :buffer_name)))
      (unless buffer-name
        (error "buffer_name parameter is required"))
      (claude-code-ide-instance--kill buffer-name))))

;;; Tool Registration

;;;###autoload
(defun claude-code-ide-tool-instance-management-setup ()
  "Register multi-instance coordination MCP tools."
  (claude-code-ide-make-tool
   :function #'claude-code-ide-mcp-spawn-instance
   :name "claude-code-ide-mcp-spawn-instance"
   :description "Spawn a new Claude Code instance in a different directory. The new instance will read its own CLAUDE.md from that directory and run independently. Use this for orchestrator patterns where a main instance delegates work to specialized instances with different contexts."
   :args '((:name "directory"
                  :type string
                  :description "Working directory for the new instance (absolute path)")
           (:name "buffer_name"
                  :type string
                  :description "Custom buffer name for the instance (optional, e.g., \"*Claude Brief Generator*\")"
                  :optional t)
           (:name "initial_message"
                  :type string
                  :description "Message to send to the instance after spawning (optional)"
                  :optional t)))

  (claude-code-ide-make-tool
   :function #'claude-code-ide-mcp-send-to-instance
   :name "claude-code-ide-mcp-send-to-instance"
   :description "Send a message to a running Claude Code instance. The message will be inserted into the instance's input buffer and sent (as if the user typed it and pressed Enter)."
   :args '((:name "buffer_name"
                  :type string
                  :description "Name of the instance buffer to send the message to")
           (:name "message"
                  :type string
                  :description "Message to send to the instance")))

  (claude-code-ide-make-tool
   :function #'claude-code-ide-mcp-list-instances
   :name "claude-code-ide-mcp-list-instances"
   :description "List all running Claude Code instances with their directories, buffer names, and status. Use this to discover what instances are available for coordination."
   :args '())

  (claude-code-ide-make-tool
   :function #'claude-code-ide-mcp-kill-instance
   :name "claude-code-ide-mcp-kill-instance"
   :description "Kill a running Claude Code instance. The instance's buffer will be closed and resources cleaned up."
   :args '((:name "buffer_name"
                  :type string
                  :description "Name of the instance buffer to kill"))))

;;;###autoload
(defun claude-code-ide-instance-management-toggle ()
  "Toggle instance management tools enabled/disabled."
  (interactive)
  (setq claude-code-ide-instance-management-enabled
        (not claude-code-ide-instance-management-enabled))
  (message "Claude Code instance management %s"
           (if claude-code-ide-instance-management-enabled "enabled" "disabled")))

(provide 'claude-code-ide-tool-instance-management)
;;; claude-code-ide-tool-instance-management.el ends here
