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
           (cadr-tui:terminal-capabilities-hyperlinks-p screen))))))

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
           (fallback
             (cadr-tui:image-fallback
              "image/png" :width 640 :height 480
              :filename "/root/pictures/a.png"
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
