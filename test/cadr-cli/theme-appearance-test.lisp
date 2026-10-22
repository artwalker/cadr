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
