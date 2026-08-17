(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test image-fallback-one-owner
  (let ((lines
          (cadr-tui::render-image-component
           nil "image/png" 20
           :capabilities
           (cadr-tui:make-terminal-capabilities
            :images nil)))
        (source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui" "src/cadr-tui/components/image.lisp"))))
    (is (consp lines))
    (is (stringp (first lines)))
    (is (search "fallback-lines" source))))

(test markdown-table-widths-vectors
  (let ((widths
          (cadr-tui::markdown-table-widths
           '(("a" "bb") ("ccc" "d"))
           40 nil nil #'identity))
        (source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui" "src/cadr-tui/components/markdown.lisp"))))
    (is (= 2 (length widths)))
    (is (every #'integerp widths))
    (is (>= (first widths) 1))
    (is (search "(make-array column-count :initial-element 0)"
                source))
    (is (search "(aref natural-widths index)" source))))

(test tool-block-diff-no-reparse
  (let ((source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui" "src/cadr-tui/components/tool-block.lisp"))))
    (is (search "(pop remaining)" source))
    (is (search "(first remaining)" source))))

(test settings-list-nthcdr-rows
  (let ((source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui"
            "src/cadr-tui/composition/settings-list.lisp"))))
    (is (search "nthcdr" source))))

(test text-box-blank-cache-hits
  (let ((component (cadr-tui:make-text-component "   ")))
    (is (null (cadr-tui:component-render component 20)))
    (is (eq :blank
            (cadr-tui::text-component-cached-lines component)))
    (is (null (cadr-tui:component-render component 20)))))

(test editor-atomic-span-slots
  (let ((span
          (cadr-tui::make-editor-atomic-span
           :start 1 :end 4 :paste-id 7)))
    (is (= 1 (cadr-tui::editor-span-start span)))
    (is (= 4 (cadr-tui::editor-span-end span)))
    (is (= 7 (cadr-tui::editor-atomic-span-paste-id span)))
    (is (= 2 (cadr-tui::editor-span-start '(2 9))))
    (is (= 9 (cadr-tui::editor-span-end '(2 9))))))

(test input-clear-action-owner
  (let ((input (cadr-tui:make-single-line-input :value "hi")))
    (setf (cadr-tui::single-line-input-last-action input) :type-word)
    (cadr-tui::single-line-input-clear-action input)
    (is (null (cadr-tui::single-line-input-last-action input)))))

(test input-kind-dispatch-table
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager))
           (is (consp
                (cadr-tui::keybindings-manager-event-kinds
                 (cadr-tui:get-keybindings))))
           (is (eq :enter
                   (cadr-tui::event-kind-for-raw-key
                    (string #\Return))))
           (is (eq :backspace
                   (cadr-tui::event-kind-for-raw-key
                    (string (code-char 127))))))
      (cadr-tui:set-keybindings previous))))

(test stdin-extract-index-walk
  (let ((source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui" "src/cadr-tui/stdin-buffer.lisp"))))
    (is (search "loop while (< position length)" source))
    (is (null
         (search
          "(loop for index from 0 below (length text)"
          source)))))

(test mermaid-draw-one-finish
  (is (assoc "flowchart" cadr-tui::+gm-draw-kinds+
             :test #'string=))
  (is (assoc "sequence" cadr-tui::+gm-draw-kinds+
             :test #'string=))
  (is (null (cadr-tui::gm-draw ""))))

(test mermaid-list-stream
  (let ((source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui" "src/cadr-tui/mermaid/transform.lisp"))))
    (is (search "raw-stream" source))
    (is (search "with-output-to-string (cur-stream)" source))))

(test mermaid-strip-string
  (is (string= "hello"
               (cadr-tui::gm-strip-markdown "*hello*"))))

(test mermaid-parse-char-at
  (is (char= #\A (cadr-tui::gm-char "ABC" 0)))
  (is (null (cadr-tui::gm-char "A" 3)))
  (is (cadr-tui::gm-char-seq-equal "hello" 1 "ell")))

(test overlay-composite-vector
  (let ((source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui" "src/cadr-tui/overlay.lisp"))))
    (is (search "(make-array" source))
    (is (search "(aref result index)" source))))

(test sync-update-constants
  (is (search "[?2026h" cadr-tui::+synchronized-update-begin+))
  (is (search "[?2026l" cadr-tui::+synchronized-update-end+)))

(test search-whitespace-one-set
  (is (member #\Space cadr-tui::+search-whitespace-characters+))
  (is (member #\Tab cadr-tui::+search-whitespace-characters+)))

(test scroll-to-prompt-vector
  (let ((source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui"
            "src/cadr-tui/renderer/lifecycle-input.lisp"))))
    (is (search "coerce" source))))

(test kitty-prefix-one-owner
  (is (string= (format nil "~C_G" #\Escape)
               cadr-tui::+kitty-control-prefix+))
  (let ((source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui"
            "src/cadr-tui/renderer/main-screen.lisp"))))
    (is (search "+kitty-control-prefix+" source))
    (is (null (search "+kitty-escape-prefix+" source)))))

(test base64-decode-table
  (is (vectorp cadr-tui::+base64-decode-table+))
  (is (= 256 (length cadr-tui::+base64-decode-table+))))

(test terminal-protocol-scanners
  (is (not (null cadr-tui::+kitty-protocol-reply-scanner+)))
  (is (not (null cadr-tui::+device-attributes-reply-scanner+))))

(test unicode-extract-streams
  (multiple-value-bind (before bw after aw)
      (cadr-tui:extract-segments "hello" 2 3 5)
    (declare (ignore bw aw))
    (is (string= "he" before))
    (is (string= "lo" after)))
  (let ((source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui" "src/cadr-tui/unicode.lisp"))))
    (is (search "make-string-output-stream" source))
    (is (search "break-long-wrap-token" source))))

(test latex-line-at-owner
  (let ((layout
          (cadr-tui::make-latex-layout
           :lines (vector "ab" "cd")
           :width 2
           :baseline 0)))
    (is (string= "ab" (cadr-tui::latex-layout-line-at layout 0)))
    (is (string= "cd" (cadr-tui::latex-layout-line-at layout 1)))
    (is (null (cadr-tui::latex-layout-line-at layout 4)))))
