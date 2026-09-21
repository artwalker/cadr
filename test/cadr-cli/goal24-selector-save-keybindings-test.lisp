(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; pi@92d8e2d17 model-selector.test.ts / thinking-selector.test.ts
;;; "uses the configured save binding": remap app.*.save to ctrl+r;
;;; footer shows Ctrl+R; ctrl+s no longer saves; ctrl+r persists.

(test thinking-selector-uses-configured-save-binding
  (let* ((keybindings
           (cadr-cli::make-thinking-selector-keybindings
            '(("app.thinking.save" . ("ctrl+r")))))
         (state
           (cadr-cli::make-thinking-selector-state
            :levels '(:off :low :medium :high)
            :current-level :medium
            :default-level :medium
            :keybindings keybindings))
         (rendered
           (format
            nil "~{~A~%~}"
            (mapcar
             #'cadr-tui:strip-terminal-sequences
             (cadr-cli::render-thinking-selector state 80)))))
    (is (search "Ctrl+R to set as default" rendered))
    (is (null (search "Ctrl+S to set as default" rendered)))
    (multiple-value-bind (action level handled-p)
        (cadr-cli::thinking-selector-handle-raw-input
         state
         (string (code-char 19)))
      (declare (ignore level))
      (is (null action))
      (is (null handled-p)))
    (multiple-value-bind (action level handled-p)
        (cadr-cli::thinking-selector-handle-raw-input
         state
         (string (code-char 18)))
      (is (eq :persist action))
      (is (eq :medium level))
      (is (eq t handled-p)))))

(test model-selector-uses-configured-save-binding
  (let* ((model
           (cadr-ai:make-model
            :id "one"
            :name "One"
            :provider :faux
            :api :faux))
         (keybindings
           (cadr-cli::make-models-selector-keybindings
            '(("app.models.save" . ("ctrl+r")))))
         (state
           (cadr-cli::make-model-selector-state
            :all-models (list model)
            :current-model model
            :keybindings keybindings))
         (rendered
           (format
            nil "~{~A~%~}"
            (mapcar
             #'cadr-tui:strip-terminal-sequences
             (cadr-cli::render-model-selector state 120)))))
    (is (search "Ctrl+R to set as default" rendered))
    (is (null (search "Ctrl+S to set as default" rendered)))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::model-selector-handle-raw-input
         state
         (string (code-char 19)))
      (declare (ignore value))
      (is (null action))
      (is (null handled-p)))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::model-selector-handle-raw-input
         state
         (string (code-char 18)))
      (is (eq :persist action))
      (is (eq model value))
      (is (eq t handled-p)))))
