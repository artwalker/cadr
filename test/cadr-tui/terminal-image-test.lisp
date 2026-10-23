(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(test terminal-image-capabilities-match-reference-terminals
  (flet ((detect (&rest environment)
           (cadr-tui:detect-terminal-capabilities
            :environment environment)))
    (let ((unknown (detect "TERM=xterm-256color"))
          (kitty (detect "TERM_PROGRAM=kitty"))
          (iterm (detect "TERM_PROGRAM=iTerm.app"))
          (tmux (cadr-tui:detect-terminal-capabilities
                 :environment
                 '("TMUX=/tmp/tmux" "COLORTERM=truecolor")
                 :tmux-hyperlinks-p t))
          (screen (detect "TERM=screen-256color")))
      (is (null
           (cadr-tui:terminal-capabilities-images unknown)))
      (is (not
           (cadr-tui:terminal-capabilities-hyperlinks-p unknown)))
      (is (eq :kitty
              (cadr-tui:terminal-capabilities-images kitty)))
      (is (cadr-tui:terminal-capabilities-true-color-p kitty))
      (is (eq :iterm2
              (cadr-tui:terminal-capabilities-images iterm)))
      (is (cadr-tui:terminal-capabilities-hyperlinks-p iterm))
      (is (null
           (cadr-tui:terminal-capabilities-images tmux)))
      (is (cadr-tui:terminal-capabilities-true-color-p tmux))
      (is (cadr-tui:terminal-capabilities-hyperlinks-p tmux))
      (is (not
           (cadr-tui:terminal-capabilities-hyperlinks-p screen)))
      (let ((herdr (detect "TERM_PROGRAM=herdr"))
            (herdr-leaked
              (detect "TERM_PROGRAM=herdr" "KITTY_WINDOW_ID=1")))
        (is (eq :kitty
                (cadr-tui:terminal-capabilities-images herdr)))
        (is (cadr-tui:terminal-capabilities-hyperlinks-p herdr))
        (is (not
             (cadr-tui:terminal-capabilities-true-color-p herdr)))
        (is (eq :kitty
                (cadr-tui:terminal-capabilities-images herdr-leaked)))
        (is (not
             (cadr-tui:terminal-capabilities-true-color-p
              herdr-leaked)))))))

(test terminal-image-rex-enables-osc8-truecolor-and-kitty-images
  ;; pi@4a080252f packages/tui/test/terminal-image.test.ts #11131.
  (flet ((detect (&rest environment)
           (cadr-tui:detect-terminal-capabilities
            :environment environment)))
    (let ((rex (detect "TERM_PROGRAM=rex"
                       "TERM=xterm-256color"))
          (rex-leaked
            (detect "TERM_PROGRAM=rex"
                    "TERM=xterm-256color"
                    "KITTY_WINDOW_ID=1"))
          (links-off
            (detect "TERM_PROGRAM=rex"
                    "CADR_HYPERLINKS=0")))
      (dolist (caps (list rex rex-leaked))
        (is (cadr-tui:terminal-capabilities-hyperlinks-p caps))
        (is (eq :kitty
                (cadr-tui:terminal-capabilities-images caps)))
        (is (cadr-tui:terminal-capabilities-true-color-p caps)))
      (is (not
           (cadr-tui:terminal-capabilities-hyperlinks-p
            links-off)))
      (is (eq :kitty
              (cadr-tui:terminal-capabilities-images
               links-off)))
      (is (cadr-tui:terminal-capabilities-true-color-p
           links-off)))))

(test terminal-image-encoding-sizing-and-detection
  (let* ((escape (string #\Escape))
         (kitty
           (cadr-tui:encode-kitty-image
            "YWJj"
            :columns 12 :rows 3 :image-id 42
            :move-cursor-p nil))
         (iterm
           (cadr-tui:encode-iterm2-image
            "YWJj" :width 12 :height "auto"
            :name "a.png"))
         (very-long
           (concatenate
            'string
            (make-string 304000
                         :initial-element #\x)
            kitty)))
    (is (search "a=T,f=100,q=2,C=1,c=12,r=3,i=42;"
                kitty))
    (is (search (concatenate 'string escape "_G")
                kitty))
    (is (search "inline=1;width=12;height=auto;"
                iterm))
    (is (cadr-tui:image-line-p kitty))
    (is (cadr-tui:image-line-p
         (concatenate 'string "prefix" iterm)))
    (is (cadr-tui:image-line-p very-long))
    (is (not (cadr-tui:image-line-p
              "/tmp/kitty/image.png")))
    (is (string=
         (format nil "~C_Ga=d,d=I,i=42,q=2~C\\"
                 #\Escape #\Escape)
         (cadr-tui:delete-kitty-image 42)))
    (multiple-value-bind (columns rows)
        (cadr-tui:calculate-image-cell-size
         800 600 60 :max-height-cells 20
         :cell-width 10
         :cell-height 20)
      (is (= 54 columns))
      (is (= 20 rows)))))

(test terminal-image-dimensions-rendering-and-fallback
  (let ((png
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2n0sAAAAASUVORK5CYII="))
    (multiple-value-bind (width height)
        (cadr-tui:image-dimensions png "image/png")
      (is (= 1 width))
      (is (= 1 height)))
    (let* ((caps
             (cadr-tui:make-terminal-capabilities
              :images :kitty
              :true-color-p t
              :hyperlinks-p t))
           (result
             (cadr-tui:render-terminal-image
              "YWJj" 100 50
              :capabilities caps
              :max-width-cells 20
              :max-height-cells 5
              :image-id 7
              :move-cursor-p nil)))
      (is (not (null result)))
      (is (= 5 (cadr-tui:image-render-result-rows result)))
      (is (= 20
             (cadr-tui:image-render-result-columns
              result)))
      (is (= 7
             (cadr-tui:image-render-result-image-id result)))
      (is (cadr-tui:image-line-p
           (cadr-tui:image-render-result-sequence result))))
    (let* ((caps
             (cadr-tui:make-terminal-capabilities
              :images nil
              :true-color-p nil
              :hyperlinks-p nil))
           (filename
             (namestring
              (merge-pathnames
               "pictures/a.png"
               (user-homedir-pathname))))
           (fallback
             (cadr-tui:image-fallback
              "image/png" :width 640 :height 480
              :filename filename
              :capabilities caps)))
      (is (string=
           "[Image: ~/pictures/a.png [image/png] 640x480]"
           fallback)))
    (let ((link
            (cadr-tui:terminal-hyperlink
             "file" "file:///tmp/a.png")))
      (is (= 4 (cadr-tui:visible-width link)))
      (is (search "file:///tmp/a.png" link)))))

(test kitty-image-metadata-registers-reads-and-crops
  (let ((line
          (cadr-tui:encode-kitty-image
           "AAAA"
           :columns 2 :rows 3
           :image-id 991
           :move-cursor-p nil)))
    (cadr-tui:register-kitty-image-metadata
     :image-id 991
     :columns 2 :rows 3
     :width-px 100 :height-px 100)
    (let ((metadata
            (cadr-tui:get-kitty-image-metadata
             line)))
      (is (= 991 (getf metadata :image-id)))
      (is (= 2 (getf metadata :columns)))
      (is (= 3 (getf metadata :rows)))
      (is (= 100 (getf metadata :width-px)))
      (is (= 100 (getf metadata :height-px))))
    (let ((middle
            (cadr-tui:crop-kitty-image-line
             line 1 1))
          (bottom
            (cadr-tui:crop-kitty-image-line
             line 2 1))
          (middle-to-bottom
            (cadr-tui:crop-kitty-image-line
             line 1 2))
          (tail
            (format nil ";AAAA~C\\"
                    #\Escape)))
      (is
       (string=
        (format
         nil
         "~C_Ga=T,f=100,q=2,C=1,c=2,i=991,y=33,h=34,r=1~A"
         #\Escape tail)
        middle))
      (is
       (string=
        (format
         nil
         "~C_Ga=T,f=100,q=2,C=1,c=2,i=991,y=66,h=34,r=1~A"
         #\Escape tail)
        bottom))
      (is
       (string=
        (format
         nil
         "~C_Ga=T,f=100,q=2,C=1,c=2,i=991,y=33,h=67,r=2~A"
         #\Escape tail)
        middle-to-bottom))
      (is
       (string=
        line
        (cadr-tui:crop-kitty-image-line
         line 0 1))))
    (is (string=
         "plain"
         (cadr-tui:crop-kitty-image-line
          "plain" 1 1)))))

(defun call-with-image-cell-dimensions (width height function)
  (multiple-value-bind (previous-width previous-height)
      (cadr-tui:get-cell-dimensions)
    (unwind-protect
         (progn
           (cadr-tui:set-cell-dimensions width height)
           (funcall function))
      (cadr-tui:set-cell-dimensions
       previous-width previous-height))))

(test kitty-image-cell-size-matches-v140-aspect-optimization
  ;; v1.4.0 packages/tui/test/terminal-image.test.ts
  ;; "image cell sizing" (#8938). Kitty passes optimizeAspectRatio.
  ;; iTerm2 does not, so a height-limited 400x900 stays 14 columns.
  (let ((kitty
          (cadr-tui:make-terminal-capabilities
           :images :kitty :true-color-p t :hyperlinks-p t))
        (iterm
          (cadr-tui:make-terminal-capabilities
           :images :iterm2 :true-color-p t
           :hyperlinks-p t)))
    (call-with-image-cell-dimensions
     9 18
     (lambda ()
       (let ((thin
               (cadr-tui:render-terminal-image
                "AAAA" 1200 12
                :capabilities kitty
                :max-width-cells 60
                :move-cursor-p nil)))
         (is (= 60
                (cadr-tui:image-render-result-columns thin)))
         (is (= 1 (cadr-tui:image-render-result-rows thin)))
         (is (search ",c=60,r=1;"
                     (cadr-tui:image-render-result-sequence
                      thin))))
       (let* ((image
                (cadr-tui:make-image-component
                 "AAAA" "image/png"
                 :dimensions '(615 86)
                 :capabilities kitty
                 :max-width-cells 60
                 :image-id 8938))
              (lines (cadr-tui:component-render image 62)))
         (is (= 4 (length lines)))
         (is (equal '("" "" "") (rest lines)))
         (is (search ",c=60,r=4,i=8938;" (first lines)))
         (let ((narrower
                 (cadr-tui:component-render image 32)))
           (is (= 2 (length narrower)))
           (is (search ",c=30,r=2,i=8938;"
                       (first narrower)))))))
    (call-with-image-cell-dimensions
     15 28
     (lambda ()
       (let ((ceiling
               (cadr-tui:render-terminal-image
                "AAAA" 615 86
                :capabilities kitty
                :max-width-cells 60)))
         (is (= 60
                (cadr-tui:image-render-result-columns
                 ceiling)))
         (is (= 5
                (cadr-tui:image-render-result-rows ceiling)))
         (is (search ",c=60,r=5;"
                     (cadr-tui:image-render-result-sequence
                      ceiling))))))
    (call-with-image-cell-dimensions
     14 28
     (lambda ()
       (let* ((image
                (cadr-tui:make-image-component
                 "AAAA" "image/png"
                 :dimensions '(400 900)
                 :capabilities kitty
                 :max-width-cells 30
                 :image-id 8938))
              (lines (cadr-tui:component-render image 32)))
         (is (= 15 (length lines)))
         (is (search ",c=13,r=15,i=8938;" (first lines)))
         (let ((narrower
                 (cadr-tui:component-render image 22)))
           (is (= 10 (length narrower)))
           (is (search ",c=9,r=10,i=8938;"
                       (first narrower)))))
       (let ((iterm-result
               (cadr-tui:render-terminal-image
                "AAAA" 400 900
                :capabilities iterm
                :max-width-cells 30
                :max-height-cells 15)))
         (is (= 14
                (cadr-tui:image-render-result-columns
                 iterm-result)))
         (is (= 15
                (cadr-tui:image-render-result-rows
                 iterm-result))))))
    (call-with-image-cell-dimensions
     1 1
     (lambda ()
       (loop for (width columns) in '((1 1) (140 1) (149 2))
             do (let ((result
                        (cadr-tui:render-terminal-image
                         "AAAA" width 1000
                         :capabilities kitty
                         :max-width-cells 30
                         :max-height-cells 10)))
                  (is (= columns
                         (cadr-tui:image-render-result-columns
                          result)))
                  (is (= 10
                         (cadr-tui:image-render-result-rows
                          result)))
                  (is (search
                       (format nil ",c=~D,r=10;" columns)
                       (cadr-tui:image-render-result-sequence
                        result)))))))
    (call-with-image-cell-dimensions
     9 18
     (lambda ()
       (let* ((image
                (cadr-tui:make-image-component
                 "AAAA" "image/png"
                 :dimensions '(615 86)
                 :capabilities iterm
                 :max-width-cells 60))
              (lines (cadr-tui:component-render image 62)))
         (is (= 5 (length lines)))
         (is (equal '("" "" "" "") (butlast lines)))
         (is (search "width=60" (car (last lines))))
         (is (search (format nil "~C[4A" #\Escape)
                     (car (last lines)))))))))

(test terminal-capability-overrides-honor-cadr-environment
  (cadr-tui:reset-capability-overrides)
  (unwind-protect
       (let ((forced
               (cadr-tui:detect-terminal-capabilities
                :environment
                '("TERM=xterm-256color"
                  "CADR_HYPERLINKS=1"
                  "CADR_TRUE_COLOR=0"
                  "CADR_IMAGE_PROTOCOL=kitty"))))
         (is (eq :kitty
                 (cadr-tui:terminal-capabilities-images forced)))
         (is (cadr-tui:terminal-capabilities-hyperlinks-p forced))
         (is (not
              (cadr-tui:terminal-capabilities-true-color-p forced))))
    (cadr-tui:reset-capability-overrides)))
