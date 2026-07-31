(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(defparameter +dark-theme-colors+
  '((:accent . "#8abeb7")
    (:border . "#5f87ff")
    (:border-accent . "#00d7ff")
    (:border-muted . "#505050")
    (:success . "#b5bd68")
    (:error . "#cc6666")
    (:warning . "#ffff00")
    (:muted . "#808080")
    (:dim . "#666666")
    (:text . "#d4d4d4")
    (:thinking-text . "#808080")
    (:selected-bg . "#3a3a4a")
    (:user-message-bg . "#343541")
    (:user-message-text . "#d4d4d4")
    (:custom-message-bg . "#2d2838")
    (:custom-message-text . "#d4d4d4")
    (:custom-message-label . "#9575cd")
    (:tool-pending-bg . "#282832")
    (:tool-success-bg . "#283228")
    (:tool-error-bg . "#3c2828")
    (:tool-title . "#d4d4d4")
    (:tool-output . "#808080")
    (:md-heading . "#f0c674")
    (:md-link . "#81a2be")
    (:md-link-url . "#666666")
    (:md-code . "#8abeb7")
    (:md-code-block . "#b5bd68")
    (:md-code-block-border . "#808080")
    (:md-quote . "#808080")
    (:md-quote-border . "#808080")
    (:md-hr . "#808080")
    (:md-list-bullet . "#8abeb7")
    (:tool-diff-added . "#b5bd68")
    (:tool-diff-removed . "#cc6666")
    (:tool-diff-context . "#808080")
    (:syntax-comment . "#6A9955")
    (:syntax-keyword . "#569CD6")
    (:syntax-function . "#DCDCAA")
    (:syntax-variable . "#9CDCFE")
    (:syntax-string . "#CE9178")
    (:syntax-number . "#B5CEA8")
    (:syntax-type . "#4EC9B0")
    (:syntax-operator . "#D4D4D4")
    (:syntax-punctuation . "#D4D4D4")
    (:thinking-off . "#505050")
    (:thinking-minimal . "#6e6e6e")
    (:thinking-low . "#5f87af")
    (:thinking-medium . "#81a2be")
    (:thinking-high . "#b294bb")
    (:thinking-xhigh . "#d183e8")
    (:thinking-max . "#ff5fff")
    (:bash-mode . "#b5bd68")
    (:page-bg . "#18181e")
    (:card-bg . "#1e1e24")
    (:info-bg . "#3c3728")))

(defparameter +light-theme-colors+
  '((:accent . "#5a8080")
    (:border . "#547da7")
    (:border-accent . "#5a8080")
    (:border-muted . "#b0b0b0")
    (:success . "#588458")
    (:error . "#aa5555")
    (:warning . "#9a7326")
    (:muted . "#6c6c6c")
    (:dim . "#767676")
    (:text . "#1f2328")
    (:thinking-text . "#6c6c6c")
    (:selected-bg . "#d0d0e0")
    (:user-message-bg . "#e8e8e8")
    (:user-message-text . "#1f2328")
    (:custom-message-bg . "#ede7f6")
    (:custom-message-text . "#1f2328")
    (:custom-message-label . "#7e57c2")
    (:tool-pending-bg . "#e8e8f0")
    (:tool-success-bg . "#e8f0e8")
    (:tool-error-bg . "#f0e8e8")
    (:tool-title . "#1f2328")
    (:tool-output . "#6c6c6c")
    (:md-heading . "#9a7326")
    (:md-link . "#547da7")
    (:md-link-url . "#767676")
    (:md-code . "#5a8080")
    (:md-code-block . "#588458")
    (:md-code-block-border . "#6c6c6c")
    (:md-quote . "#6c6c6c")
    (:md-quote-border . "#6c6c6c")
    (:md-hr . "#6c6c6c")
    (:md-list-bullet . "#588458")
    (:tool-diff-added . "#588458")
    (:tool-diff-removed . "#aa5555")
    (:tool-diff-context . "#6c6c6c")
    (:syntax-comment . "#008000")
    (:syntax-keyword . "#0000FF")
    (:syntax-function . "#795E26")
    (:syntax-variable . "#001080")
    (:syntax-string . "#A31515")
    (:syntax-number . "#098658")
    (:syntax-type . "#267F99")
    (:syntax-operator . "#000000")
    (:syntax-punctuation . "#000000")
    (:thinking-off . "#b0b0b0")
    (:thinking-minimal . "#767676")
    (:thinking-low . "#547da7")
    (:thinking-medium . "#5a8080")
    (:thinking-high . "#875f87")
    (:thinking-xhigh . "#8b008b")
    (:thinking-max . "#af005f")
    (:bash-mode . "#588458")
    (:page-bg . "#f8f8f8")
    (:card-bg . "#ffffff")
    (:info-bg . "#fffae6")))

(defun assert-theme-colors (name expected)
  (let ((theme
          (cadr-tui:make-terminal-theme
           name
           :capabilities
           (cadr-tui:make-terminal-capabilities
            :true-color-p t))))
    (is (= (length expected)
           (length (cadr-tui:terminal-theme-color-keys
                    theme))))
    (dolist (entry expected)
      (is (string=
           (cdr entry)
           (cadr-tui:theme-color-value
            (car entry) :theme theme))))))

(test builtin-themes-match-audit-baseline
  (assert-theme-colors :dark +dark-theme-colors+)
  (assert-theme-colors :light +light-theme-colors+))

(test theme-hex-parser-and-256-conversion-are-exact
  (let ((color (cadr-tui:parse-theme-hex-color "#00AaFf")))
    (is (= 0 (cadr-tui:rgb-color-red color)))
    (is (= 170 (cadr-tui:rgb-color-green color)))
    (is (= 255 (cadr-tui:rgb-color-blue color))))
  (dolist (invalid '("00aaff" "#abc" "#abcdzz" "#00112233" ""))
    (signals error
      (cadr-tui:parse-theme-hex-color invalid)))
  (is (= 109
         (cadr-tui:rgb-to-ansi-256 138 190 183)))
  (is (= 244
         (cadr-tui:rgb-to-ansi-256 128 128 128)))
  (is (= 241
         (cadr-tui:rgb-to-ansi-256 102 102 102)))
  (is (= 188
         (cadr-tui:rgb-to-ansi-256 212 212 212)))
  (is (= 59
         (cadr-tui:rgb-to-ansi-256 58 58 74)))
  ;; Noticeable saturation must retain cube hue even when gray is nearby.
  (is (= 102
         (cadr-tui:rgb-to-ansi-256 135 128 118))))

(test theme-ansi-honors-capabilities-and-local-resets
  (let* ((true-color
           (cadr-tui:make-terminal-capabilities
            :true-color-p t))
         (ansi-256
           (cadr-tui:make-terminal-capabilities
            :true-color-p nil))
         (true-theme
           (cadr-tui:make-terminal-theme
            :dark :capabilities true-color))
         (indexed-theme
           (cadr-tui:make-terminal-theme
            :dark :capabilities ansi-256)))
    (is (string=
         (csi "38;2;138;190;183m")
         (cadr-tui:theme-foreground-ansi
          :accent :theme true-theme)))
    (is (string=
         (csi "38;5;109m")
         (cadr-tui:theme-foreground-ansi
          :accent :theme indexed-theme)))
    (is (string=
         (concatenate
          'string (csi "38;2;138;190;183m")
          "x" (csi "39m"))
         (cadr-tui:theme-foreground
          :accent "x" :theme true-theme)))
    (is (string=
         (concatenate
          'string (csi "48;2;52;53;65m")
          "x" (csi "49m"))
         (cadr-tui:theme-background
          :user-message-bg "x" :theme true-theme)))
    (is (string=
         (concatenate
          'string (csi "48;5;59m")
          "x" (csi "49m"))
         (cadr-tui:theme-background
          :user-message-bg "x" :theme indexed-theme)))
    (signals error
      (cadr-tui:theme-background
       :accent "x" :theme true-theme))
    (signals error
      (cadr-tui:theme-foreground
       :user-message-bg "x" :theme true-theme))))

(test theme-overrides-current-theme-and-disabled-output
  (let* ((capabilities
           (cadr-tui:make-terminal-capabilities
            :true-color-p t))
         (theme
           (cadr-tui:make-terminal-theme
            :light
            :capabilities capabilities
            :overrides
            '(("borderAccent" . "#010203")
              (:accent . 196)))))
    (is (string=
         "#010203"
         (cadr-tui:theme-color-value
          :border-accent :theme theme)))
    (is (= 196
           (cadr-tui:theme-color-value
            :accent :theme theme)))
    (is (string=
         (csi "38;5;196m")
         (cadr-tui:theme-foreground-ansi
          :accent :theme theme)))
    (is (string= "plain"
                 (cadr-tui:theme-foreground
                  :accent "plain" :theme theme
                  :enabled-p nil)))
    (is (string= "plain"
                 (cadr-tui:theme-background
                  :selected-bg "plain" :theme theme
                  :enabled-p nil)))
    (is (string= "plain"
                 (cadr-tui:theme-bold
                  "plain" :enabled-p nil)))
    (let ((disabled-theme
            (cadr-tui:make-terminal-theme
             :dark :enabled-p nil)))
      (is (string= "plain"
                   (cadr-tui:theme-foreground
                    :accent "plain"
                    :theme disabled-theme)))
      (is (string= ""
                   (cadr-tui:theme-foreground-ansi
                    :accent :theme disabled-theme))))
    (signals error
      (cadr-tui:make-terminal-theme
       :dark :overrides '((:not-a-token . "#000000"))))
    (signals error
      (cadr-tui:make-terminal-theme
       :dark :overrides '((:accent . "red")))))
  (unwind-protect
       (progn
         (cadr-tui:set-current-theme
          :light
          :capabilities
          (cadr-tui:make-terminal-capabilities
           :true-color-p nil))
         (is (eq :light
                 (cadr-tui:terminal-theme-name
                  (cadr-tui:current-theme))))
         (is (string= "#875f87"
                      (cadr-tui:theme-color-value
                       :thinking-high)))
         (is (search (csi "38;5;")
                     (cadr-tui:theme-thinking-foreground
                      :high "─")))
         (is (search "─" (cadr-tui:theme-thinking-foreground
                          :unknown "─")))
         (is (search "bash"
                     (cadr-tui:theme-bash-mode-foreground
                      "bash"))))
    (cadr-tui:reset-current-theme))
  (is (eq :dark
          (cadr-tui:terminal-theme-name
           (cadr-tui:current-theme)))))

(test theme-style-wrappers-reset-only-their-own-attribute
  (is (string=
       (concatenate 'string (csi "1m") "x" (csi "22m"))
       (cadr-tui:theme-bold "x")))
  (is (string=
       (concatenate 'string (csi "3m") "x" (csi "23m"))
       (cadr-tui:theme-italic "x")))
  (is (string=
       (concatenate 'string (csi "4m") "x" (csi "24m"))
       (cadr-tui:theme-underline "x")))
  (is (string=
       (concatenate 'string (csi "7m") "x" (csi "27m"))
       (cadr-tui:theme-inverse "x"))))
