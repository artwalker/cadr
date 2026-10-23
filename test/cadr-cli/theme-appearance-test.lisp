(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defparameter +theme-background-names+
  '("selectedBg" "searchMatchBg" "userMessageBg" "customMessageBg"
    "toolPendingBg" "toolSuccessBg" "toolErrorBg"))

(defun sample-theme-object
    (&key (text "#eeeeee") (background "#111111") appearance)
  (let ((colors (make-hash-table :test #'equal))
        (object (make-hash-table :test #'equal)))
    (dolist (entry cadr-cli::+tui-theme-json-color-map+)
      (setf (gethash (car entry) colors)
            (if (member (car entry) +theme-background-names+
                        :test #'string=)
                background
                text)))
    (setf (gethash "name" object) "sample"
          (gethash "colors" object) colors)
    (when appearance
      (setf (gethash "appearance" object) appearance))
    object))

(test theme-appearance-and-oklch-colors
  ;; pi@4a080252f theme-schema.ts appearance and colors.ts parseColor.
  (is (string= "#ffffff"
               (cadr-tui:normalize-theme-color "oklch(100% 0.3 150)")))
  (is (string= "#000000"
               (cadr-tui:normalize-theme-color "oklch(0% 0.2 40)")))
  (is (string= "#d70071"
               (cadr-tui:normalize-theme-color "okhsl(0 100% 50%)")))
  (is (string= "#7cb8bb"
               (cadr-tui:normalize-theme-color "okhsl(200deg 0.4 70%)")))
  (is (string= "#aabbcc"
               (cadr-tui:normalize-theme-color "#aBc")))
  (is (null (cadr-tui:theme-color-lightness 4)))
  (let ((previous (cadr-tui:current-theme)))
    (unwind-protect
         (progn
           (cadr-cli::apply-tui-theme-summary
            (list :name "sample"
                  :object (sample-theme-object
                           :text "#000000" :background "#ffffff"))
            :background :dark)
           (is (eq :light
                   (cadr-tui:terminal-theme-name
                    (cadr-tui:current-theme))))
           (cadr-cli::apply-tui-theme-summary
            (list :name "sample"
                  :object (sample-theme-object :appearance "light"))
            :background :dark)
           (is (eq :light
                   (cadr-tui:terminal-theme-name
                    (cadr-tui:current-theme))))
           (cadr-cli::apply-tui-theme-summary
            (list :name "light"
                  :object (sample-theme-object
                           :text "#eeeeee" :background "#111111"))
            :background :light)
           (is (eq :dark
                   (cadr-tui:terminal-theme-name
                    (cadr-tui:current-theme))))
           (let* ((object
                    (sample-theme-object :text "oklch(100% 0.3 150)"))
                  (vars (make-hash-table :test #'equal)))
             (setf (gethash "ink" vars) "#abc"
                   (gethash "accent" (gethash "colors" object)) "ink"
                   (gethash "vars" object) vars)
             (is (string=
                  "#ffffff"
                  (cdr
                   (assoc :text
                          (cadr-cli::theme-object-overrides object)))))
             (is (string=
                  "#aabbcc"
                  (cdr
                   (assoc :accent
                          (cadr-cli::theme-object-overrides object))))))
           (let ((condition
                   (nth-value
                    1
                    (ignore-errors
                     (cadr-cli::theme-object-overrides
                      (sample-theme-object :appearance "sideways"))))))
             (is (typep condition 'error))))
      (cadr-tui:set-current-theme previous))))

(test dynamic-resources-example-theme-scrollbar-colors
  ;; v1.4.0 examples/extensions/dynamic-resources/dynamic.json
  ;; (457ae8c79). scrollbarTrack names vars.darkGray "#505050".
  ;; scrollbarThumb "" stays a terminal-default token. Omitting it
  ;; would fall back to selectedBg "#3a3a4a". With no reported
  ;; terminal color, the empty thumb is the dark foreground guess.
  (let* ((path
           (merge-pathnames
            "examples/extensions/dynamic-resources/dynamic.json"
            (asdf:system-source-directory "cadr-cli")))
         (object
           (cadr-ai::parse-json
            (uiop:read-file-string path :external-format :utf-8)))
         (colors (gethash "colors" object))
         (variables (gethash "vars" object))
         (export (gethash "export" object))
         (overrides (cadr-cli::theme-object-overrides object))
         (previous (cadr-tui:current-theme)))
    (is (string= "https://pi.dev/schemas/theme.schema.json"
                 (gethash "$schema" object)))
    (is (string= "dynamic-resources" (gethash "name" object)))
    (is (string= "darkGray" (gethash "scrollbarTrack" colors)))
    (is (string= "" (gethash "scrollbarThumb" colors)))
    (is (string= "#505050" (gethash "darkGray" variables)))
    (is (string= "#3a3a4a" (gethash "selectedBg" variables)))
    (is (string= "#808080" (gethash "gray" variables)))
    (is (string= "gray" (gethash "muted" colors)))
    (is (string= "#18181e" (gethash "pageBg" export)))
    (is (string= "#1e1e24" (gethash "cardBg" export)))
    (is (string= "#3c3728" (gethash "infoBg" export)))
    (is (string= "#505050"
                 (cdr (assoc :scrollbar-track overrides))))
    (is (string= ""
                 (cdr (assoc :scrollbar-thumb overrides))))
    (unwind-protect
         (progn
           (cadr-tui:set-terminal-default-colors)
           (cadr-cli::apply-tui-theme-summary
            (list :name "dynamic-resources" :object object)
            :capabilities
            (cadr-tui:make-terminal-capabilities
             :images nil :true-color-p t))
           (is (eq :dark
                   (cadr-tui:terminal-theme-name
                    (cadr-tui:current-theme))))
           (is (string= "#505050"
                        (cadr-tui:theme-color-value :scrollbar-track)))
           (is (string= "#e5e5e7"
                        (cadr-tui:theme-color-value :scrollbar-thumb)))
           (is (string=
                (format nil "~C[39m" #\Escape)
                (cadr-tui:theme-foreground-ansi
                 :scrollbar-thumb :enabled-p t)))
           (is (string=
                (concatenate
                 'string
                 (format nil "~C[39m" #\Escape)
                 "x"
                 (format nil "~C[39m" #\Escape))
                (cadr-tui:theme-foreground
                 :scrollbar-thumb "x" :enabled-p t)))
           (signals error
             (cadr-tui:theme-background-ansi
              :scrollbar-thumb :enabled-p t))
           (is (string=
                (format nil "~C[38;2;80;80;80m" #\Escape)
                (cadr-tui:theme-foreground-ansi
                 :scrollbar-track :enabled-p t)))
           (signals error
             (cadr-tui:theme-background-ansi
              :scrollbar-track :enabled-p t))
           (cadr-tui:set-terminal-default-colors
            :background '(250 250 250))
           (is (string= "#e5e5e7"
                        (cadr-tui:theme-color-value :scrollbar-thumb)))
           (cadr-tui:set-terminal-default-colors
            :foreground '(200 210 220))
           (let ((light
                   (cadr-tui:make-terminal-theme
                    :light
                    :capabilities
                    (cadr-tui:make-terminal-capabilities
                     :images nil :true-color-p t)
                    :overrides
                    '((:scrollbar-thumb . "")))))
             (is (string= "#c8d2dc"
                          (cadr-tui:theme-color-value
                           :scrollbar-thumb :theme light)))))
      (cadr-tui:set-terminal-default-colors)
      (cadr-tui:set-current-theme previous))))
