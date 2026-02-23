;;; claude-code-ide-tool-window-management.el --- Window management MCP tools  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: John D. Blair
;; Keywords: ai, claude, mcp, window

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Window management tools for "IDE visibility mode" - allowing Claude to
;; show code to the user without disrupting their workflow.
;;
;; Key behaviors:
;; - Display code in a stable "display window" (file-visiting, non-special)
;; - Never steal focus from the Claude terminal
;; - Support highlighting to draw attention to specific lines

;;; Code:

(require 'claude-code-ide-mcp-server)

;;; Customization

(defface claude-code-ide-show-code-highlight
  '((t :background "#006666" :foreground "white"))
  "Face for temporarily highlighting shown code lines."
  :group 'claude-code-ide)

(defcustom claude-code-ide-show-code-highlight-duration 2.0
  "Duration in seconds for the show-code highlight."
  :type 'number
  :group 'claude-code-ide)

;;; Window Selection

(defun claude-code-ide-mcp--find-display-window ()
  "Find a suitable window for displaying code.
Prefers windows showing file-visiting buffers over special buffers.
Never returns a *claude-code* or *terminal* window."
  (or
   ;; First choice: window with a file-visiting buffer
   (get-window-with-predicate
    (lambda (w)
      (with-current-buffer (window-buffer w)
        (and buffer-file-name
             (not (string-match-p "\\*" (buffer-name)))))))
   ;; Fallback: any non-claude, non-terminal window
   (get-window-with-predicate
    (lambda (w)
      (not (string-match-p "\\*claude-code\\|\\*terminal"
                           (buffer-name (window-buffer w))))))))

;;; Show Code Tool

(defun claude-code-ide-mcp-show-code (file-path line &optional column highlight)
  "Display FILE-PATH at LINE in the display window without stealing focus.
FILE-PATH is the absolute path to the file.
LINE is the line number (1-based).
COLUMN is the column number (0-based, optional).
HIGHLIGHT temporarily highlights the line if non-nil (optional, default t)."
  (claude-code-ide-mcp-server-with-session-context nil
    (condition-case err
        (let* ((original-window (selected-window))
               (expanded-path (expand-file-name file-path))
               (buf (find-file-noselect expanded-path))
               (display-window (claude-code-ide-mcp--find-display-window)))
          (if (not display-window)
              (format "No suitable display window found for %s" file-path)
            ;; Show buffer in the display window
            (set-window-buffer display-window buf)
            (with-selected-window display-window
              ;; Navigate to position
              (goto-char (point-min))
              (forward-line (1- line))
              (when column
                (move-to-column column))
              (recenter)
              ;; Highlight (default to t if not specified)
              (when (or highlight (null highlight))
                (let ((ov (make-overlay (line-beginning-position)
                                        (line-end-position))))
                  (overlay-put ov 'face 'claude-code-ide-show-code-highlight)
                  (run-with-timer claude-code-ide-show-code-highlight-duration
                                  nil (lambda () (delete-overlay ov))))))
            ;; Return to original window
            (when (window-live-p original-window)
              (select-window original-window))
            (format "Showing %s:%d%s"
                    (file-name-nondirectory file-path)
                    line
                    (if column (format ":%d" column) ""))))
      (error
       (format "Failed to show code: %s" (error-message-string err))))))

;;; Tool Registration

;;;###autoload
(defun claude-code-ide-tool-window-management-setup ()
  "Register window management MCP tools."
  (claude-code-ide-make-tool
   :function #'claude-code-ide-mcp-show-code
   :name "claude-code-ide-mcp-show-code"
   :description "Display a file at a specific location in the user's code window without stealing focus. Use this to show the user what you're discussing or working on. The highlight makes it easy to spot the relevant line."
   :args '((:name "file_path"
                  :type string
                  :description "Absolute path to the file to display")
           (:name "line"
                  :type number
                  :description "Line number (1-based)")
           (:name "column"
                  :type number
                  :description "Column number (0-based)"
                  :optional t)
           (:name "highlight"
                  :type boolean
                  :description "Whether to temporarily highlight the line (default: true)"
                  :optional t))))

(provide 'claude-code-ide-tool-window-management)
;;; claude-code-ide-tool-window-management.el ends here
