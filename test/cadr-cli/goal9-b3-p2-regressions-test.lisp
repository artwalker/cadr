(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal9-b3-plain-lines (lines)
  (mapcar #'cadr-tui:strip-terminal-sequences lines))

(test goal9-b3-model-overlay-copy-matches-unscoped-baseline
  (let* ((width 80)
         (border
           (make-string width :initial-element #\─))
         (model
           (cadr-ai:make-model
            :id "faux-model" :name "Faux Model"
            :provider :faux :api :faux))
         (state
           (cadr-cli::make-model-selector-state
            :all-models (list model)
            :current-model model))
         (plain
           (goal9-b3-plain-lines
            (cadr-cli::render-model-selector
             state width))))
    (is
     (equal
      (list
       border
       ""
       "Only showing models from configured providers. Use /login to add providers."
       ""
       "> "
       ""
       "→ faux-model [faux] ✓"
       ""
       "  Model Name: Faux Model"
       ""
       border)
      plain))))

(test goal9-b3-tree-help-copy-preserves-arrow-glyphs-and-filter-abbreviations
  (let* ((width 120)
         (border
           (make-string width :initial-element #\─))
         (state
           (cadr-cli::make-tree-selector-state
            :entries
            '((:id "u1" :parent-id nil
               :type :message :role :user :text "hello"))
            :current-leaf-id "u1"))
         (plain
           (goal9-b3-plain-lines
            (cadr-cli::render-tree-selector
             state width))))
    (is
     (equal
      (list
       ""
       border
       "  Session Tree"
       "  ↑/↓ move · ←/→ page · ctrl+←/→ branch · ctrl+x copy · shift+l label · shift+t label time · filters ctrl+d/t/u/l/a"
       "  cycle ctrl+o/shift+ctrl+o"
       "  Type to search:"
       border
       ""
       "› • user: hello"
       "  (1/1)"
       ""
       border)
      plain))))

(test goal9-b3-tree-tool-results-render-call-labels-not-raw-output
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_ (ensure-directories-exist
               (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "tree-tools"))
           (assistant
             (cadr-ai:make-assistant-message
              :content
              (list
               (cadr-ai:make-tool-call
                :id "bash-1" :name "bash"
                :arguments
                (cadr-ai::json-object
                 "command" "printf 'ok'"))
               (cadr-ai:make-tool-call
                :id "read-1" :name "read"
                :arguments
                (cadr-ai::json-object
                 "path" "README.md")))
              :api :faux :provider :faux :model "faux"
              :stop-reason :tool-use))
           (bash-result
             (cadr-ai:make-tool-result-message
              :tool-call-id "bash-1" :tool-name "bash"
              :content
              (list
               (cadr-ai:make-text-content
                :text "RAW BASH OUTPUT MUST NOT APPEAR"))))
           (read-result
             (cadr-ai:make-tool-result-message
              :tool-call-id "read-1" :tool-name "read"
              :content
              (list
               (cadr-ai:make-text-content
                :text "RAW FILE CONTENT MUST NOT APPEAR")))))
      (declare (ignore _))
      (dolist (message (list assistant bash-result read-result))
        (cadr-agent:session-append-message session message))
      (multiple-value-bind (entries leaf-id)
          (cadr-cli::session-tree-selector-data session)
        (let* ((state
                 (cadr-cli::make-tree-selector-state
                  :entries entries :current-leaf-id leaf-id
                  :filter :all))
               (plain
                 (goal9-b3-plain-lines
                  (cadr-cli::tree-selector-render-lines
                   state 200))))
          (is
           (equal
            '("  • [bash: printf 'ok']"
              "› • [read: README.md]"
              "  (2/2) [all]")
            plain)))))))

(test goal9-b3-cold-startup-content-is-top-aligned
  (let* ((width 60)
         (rows 16)
         (blank-row
           (make-string width :initial-element #\Space))
         (border
           (make-string width :initial-element #\─))
         (state
           (cadr-cli::make-tui-state
            :model "faux"
            :startup-compact-lines
            '("cadr v0.1.0"
              "escape interrupt · ctrl+c/ctrl+d clear/exit")))
         (editor (cadr-tui:make-multiline-editor)))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor width rows)
      (is (= 17 row))
      (is (zerop column))
      (is
       (equal
        (list
         ""
         "cadr v0.1.0"
         "escape interrupt · ctrl+c/ctrl+d clear/exit"
         ""
         ""
         ""
         ""
         ""
         ""
         blank-row
         blank-row
         border
         blank-row
         border
         ""
         "?/0 (auto)                                              faux")
        (goal9-b3-plain-lines lines))))))
