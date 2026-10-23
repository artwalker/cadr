(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(defparameter +v140-builtin-theme-rgb+
  '(
    (:dark
     (:accent 167 152 215)
     (:border 95 168 204)
     (:border-accent 160 142 213)
     (:border-muted 118 129 134)
     (:success 104 183 141)
     (:error 234 127 129)
     (:warning 205 154 34)
     (:muted 157 165 169)
     (:dim 126 136 142)
     (:text 222 224 225)
     (:thinking-text 150 160 164)
     (:selected-bg 33 59 73)
     (:scrollbar-track 72 78 82)
     (:scrollbar-thumb 151 160 165)
     (:search-match-bg 78 47 27)
     (:search-match-text 157 165 169)
     (:user-message-bg 33 59 73)
     (:user-message-text 222 224 225)
     (:custom-message-bg 58 48 85)
     (:custom-message-text 157 165 169)
     (:custom-message-label 167 152 215)
     (:tool-pending-bg 52 56 58)
     (:tool-success-bg 37 65 49)
     (:tool-error-bg 91 40 42)
     (:tool-title 222 224 225)
     (:tool-output 157 165 169)
     (:md-heading 205 154 34)
     (:md-link 105 173 208)
     (:md-link-url 157 165 169)
     (:md-code 167 152 215)
     (:md-code-block 104 183 141)
     (:md-code-block-border 157 165 169)
     (:md-quote 157 165 169)
     (:md-quote-border 157 165 169)
     (:md-hr 157 165 169)
     (:md-list-bullet 167 152 215)
     (:tool-diff-added 104 183 141)
     (:tool-diff-removed 234 127 129)
     (:tool-diff-context 157 165 169)
     (:syntax-comment 157 165 169)
     (:syntax-keyword 105 173 208)
     (:syntax-function 205 154 34)
     (:syntax-variable 93 179 186)
     (:syntax-string 222 141 90)
     (:syntax-number 104 183 141)
     (:syntax-type 167 152 215)
     (:syntax-operator 157 165 169)
     (:syntax-punctuation 157 165 169)
     (:thinking-off 108 118 123)
     (:thinking-minimal 104 128 141)
     (:thinking-low 84 137 164)
     (:thinking-medium 97 133 204)
     (:thinking-high 151 118 229)
     (:thinking-xhigh 222 84 193)
     (:thinking-max 254 84 98)
     (:bash-mode 94 178 134)
     (:page-bg 33 37 44)
     (:card-bg 40 44 52)
     (:info-bg 78 47 27))
    (:light
     (:accent 116 89 180)
     (:border 61 142 179)
     (:border-accent 138 114 203)
     (:border-muted 154 162 167)
     (:success 51 126 88)
     (:error 200 37 61)
     (:warning 143 104 2)
     (:muted 103 113 118)
     (:dim 135 144 149)
     (:text 59 63 65)
     (:thinking-text 124 134 140)
     (:selected-bg 223 231 236)
     (:scrollbar-track 225 227 228)
     (:scrollbar-thumb 150 160 164)
     (:search-match-bg 237 227 221)
     (:search-match-text 103 113 118)
     (:user-message-bg 223 231 236)
     (:user-message-text 59 63 65)
     (:custom-message-bg 230 228 238)
     (:custom-message-text 103 113 118)
     (:custom-message-label 116 89 180)
     (:tool-pending-bg 228 229 230)
     (:tool-success-bg 222 233 225)
     (:tool-error-bg 238 226 225)
     (:tool-title 59 63 65)
     (:tool-output 103 113 118)
     (:md-heading 143 104 2)
     (:md-link 47 120 153)
     (:md-link-url 103 113 118)
     (:md-code 116 89 180)
     (:md-code-block 51 126 88)
     (:md-code-block-border 103 113 118)
     (:md-quote 103 113 118)
     (:md-quote-border 103 113 118)
     (:md-hr 103 113 118)
     (:md-list-bullet 116 89 180)
     (:tool-diff-added 51 126 88)
     (:tool-diff-removed 200 37 61)
     (:tool-diff-context 103 113 118)
     (:syntax-comment 103 113 118)
     (:syntax-keyword 47 120 153)
     (:syntax-function 143 104 2)
     (:syntax-variable 40 122 129)
     (:syntax-string 164 84 23)
     (:syntax-number 51 126 88)
     (:syntax-type 116 89 180)
     (:syntax-operator 103 113 118)
     (:syntax-punctuation 103 113 118)
     (:thinking-off 194 200 202)
     (:thinking-minimal 181 196 203)
     (:thinking-low 159 194 213)
     (:thinking-medium 162 183 224)
     (:thinking-high 181 165 232)
     (:thinking-xhigh 229 133 205)
     (:thinking-max 254 116 121)
     (:bash-mode 64 151 108)
     (:page-bg 239 238 238)
     (:card-bg 247 246 246)
     (:info-bg 237 227 221))))

(defun theme-test-rgb (value)
  (let ((color (cadr-tui:parse-theme-hex-color value)))
    (list (cadr-tui:rgb-color-red color)
          (cadr-tui:rgb-color-green color)
          (cadr-tui:rgb-color-blue color))))

(test builtin-themes-match-v140-json
  (let ((root (asdf:system-source-directory "cadr-tui")))
    (dolist (name '("dark.json" "light.json"))
      (is (string=
           (uiop:read-file-string
            (merge-pathnames
             (format nil "test/fixtures/v140-theme/~A" name)
             root))
           (uiop:read-file-string
            (merge-pathnames
             (format nil "src/cadr-tui/theme/~A" name)
             root)
            :external-format :utf-8))
          "~A is the v1.4.0 document" name)))
  (dolist (theme-entry +v140-builtin-theme-rgb+)
    (let ((theme
            (cadr-tui:make-terminal-theme
             (first theme-entry)
             :capabilities
             (cadr-tui:make-terminal-capabilities
              :true-color-p t))))
      (is (= 59
             (length (cadr-tui:terminal-theme-color-keys theme))))
      (dolist (entry (rest theme-entry))
        (is (equal (rest entry)
                   (theme-test-rgb
                    (cadr-tui:theme-color-value
                     (first entry) :theme theme)))
            "~A ~A" (first theme-entry) (first entry))))))

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
         (csi "38;2;167;152;215m")
         (cadr-tui:theme-foreground-ansi
          :accent :theme true-theme)))
    (is (string=
         (csi (format nil "38;5;~Dm"
                      (cadr-tui:rgb-to-ansi-256 167 152 215)))
         (cadr-tui:theme-foreground-ansi
          :accent :theme indexed-theme)))
    (is (string=
         (concatenate
          'string (csi "38;2;167;152;215m")
          "x" (csi "39m"))
         (cadr-tui:theme-foreground
          :accent "x" :theme true-theme)))
    (is (string=
         (concatenate
          'string (csi "48;2;33;59;73m")
          "x" (csi "49m"))
         (cadr-tui:theme-background
          :user-message-bg "x" :theme true-theme)))
    (is (string=
         (concatenate
          'string (csi (format nil "48;5;~Dm"
                               (cadr-tui:rgb-to-ansi-256 33 59 73)))
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
         (is (string= "#b5a5e8"
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

(test theme-keyword-one-owner
  (is (eq :dark (cadr-tui::ensure-theme-keyword "dark")))
  (is (eq :thinking-high
          (cadr-tui::theme-thinking-color-key "high"))))

(test empty-theme-tokens-use-guessed-terminal-defaults
  ;; v1.4.0 theme-style.test.ts: empty tokens render as SGR 39/49.
  ;; theme.colors uses GUESSED_DEFAULT_COLORS until setTerminalColors.
  (let ((capabilities
          (cadr-tui:make-terminal-capabilities
           :true-color-p t)))
    (unwind-protect
         (progn
           (cadr-tui:set-terminal-default-colors)
           (dolist (entry
                    '((:dark "#e5e5e7" "#000000")
                      (:light "#000000" "#ffffff")))
             (let ((theme
                     (cadr-tui:make-terminal-theme
                      (first entry)
                      :capabilities capabilities
                      :overrides
                      '((:text . "")
                        (:user-message-bg . "")
                        (:accent . "#010203")))))
               (is (string= (second entry)
                            (cadr-tui:theme-color-value
                             :text :theme theme)))
               (is (string= (third entry)
                            (cadr-tui:theme-color-value
                             :user-message-bg :theme theme)))
               (is (string= "#010203"
                            (cadr-tui:theme-color-value
                             :accent :theme theme)))
               (is (string= (csi "39m")
                            (cadr-tui:theme-foreground-ansi
                             :text :theme theme)))
               (is (string= (csi "49m")
                            (cadr-tui:theme-background-ansi
                             :user-message-bg :theme theme)))
               (is (string=
                    (concatenate 'string
                                 (csi "39m") "x" (csi "39m"))
                    (cadr-tui:theme-foreground
                     :text "x" :theme theme)))
               (is (string=
                    (concatenate 'string
                                 (csi "49m") "x" (csi "49m"))
                    (cadr-tui:theme-background
                     :user-message-bg "x" :theme theme)))))
           (cadr-tui:set-terminal-default-colors
            :foreground '(200 210 220)
            :background '(10 20 30))
           (dolist (name '(:dark :light))
             (let ((theme
                     (cadr-tui:make-terminal-theme
                      name
                      :capabilities capabilities
                      :overrides
                      '((:text . "")
                        (:user-message-bg . "")))))
               (is (string= "#c8d2dc"
                            (cadr-tui:theme-color-value
                             :text :theme theme)))
               (is (string= "#0a141e"
                            (cadr-tui:theme-color-value
                             :user-message-bg :theme theme)))
               (is (string= (csi "39m")
                            (cadr-tui:theme-foreground-ansi
                             :text :theme theme)))))
           (cadr-tui:set-terminal-default-colors
            :background '(250 250 250))
           (let ((theme
                   (cadr-tui:make-terminal-theme
                    :dark
                    :capabilities capabilities
                    :overrides
                    '((:text . "")
                      (:user-message-bg . "")))))
             (is (string= "#e5e5e7"
                          (cadr-tui:theme-color-value
                           :text :theme theme)))
             (is (string= "#fafafa"
                          (cadr-tui:theme-color-value
                           :user-message-bg :theme theme))))
           (cadr-tui:set-terminal-default-colors
            :foreground '(200 210 220))
           (let ((theme
                   (cadr-tui:make-terminal-theme
                    :light
                    :capabilities capabilities
                    :overrides
                    '((:text . "")
                      (:page-bg . "")))))
             (is (string= "#c8d2dc"
                          (cadr-tui:theme-color-value
                           :text :theme theme)))
             (is (string= "#ffffff"
                          (cadr-tui:theme-color-value
                           :page-bg :theme theme)))))
      (cadr-tui:set-terminal-default-colors))))
