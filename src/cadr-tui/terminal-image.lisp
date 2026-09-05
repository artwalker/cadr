(in-package #:cadr-tui)

(defstruct terminal-capabilities
  images
  (true-color-p nil :type boolean)
  (hyperlinks-p nil :type boolean))

(defstruct image-render-result
  (sequence "" :type string)
  (rows 1 :type (integer 1 *))
  (columns 1 :type (integer 1 *))
  image-id)

(defparameter *terminal-capabilities* nil)
(defparameter *capability-overrides* nil)
(defparameter *kitty-image-metadata*
  (make-hash-table))
(defparameter *kitty-image-metadata-order* nil)
(defparameter +kitty-image-metadata-limit+ 1000)
(defparameter +kitty-control-prefix+
  (format nil "~C_G" #\Escape))

(defun register-kitty-image-metadata
    (&key image-id columns rows width-px height-px)
  (when image-id
    (setf
     (gethash image-id *kitty-image-metadata*)
     (list
      :image-id image-id
      :columns columns
      :rows rows
      :width-px width-px
      :height-px height-px)
     *kitty-image-metadata-order*
     (nconc
      (remove image-id
              *kitty-image-metadata-order*
              :test #'=)
      (list image-id)))
    (loop while
          (> (length *kitty-image-metadata-order*)
             +kitty-image-metadata-limit+)
          for oldest =
          (pop *kitty-image-metadata-order*)
          do (remhash
              oldest
              *kitty-image-metadata*)))
  image-id)

(defun kitty-line-parameter-integer
    (line parameter)
  (let ((position (search parameter line)))
    (when position
      (parse-integer
       line
       :start (+ position
                 (length parameter))
       :junk-allowed t))))

(defun kitty-control-header-bounds (line)
  (let* ((prefix +kitty-control-prefix+)
         (sequence-start
           (search prefix line))
         (controls-start
           (and sequence-start
                (+ sequence-start
                   (length prefix))))
         (controls-end
           (and controls-start
                (position #\; line
                          :start controls-start))))
    (values sequence-start
            controls-start
            controls-end)))

(defun kitty-crop-control-p (control)
  (and
   (>= (length control) 2)
   (member (char control 0)
           '(#\y #\h #\r))
   (char= (char control 1) #\=)))

(defun get-kitty-image-metadata (line)
  (let ((id
          (and
           (search
            +kitty-control-prefix+
            line)
           (kitty-line-parameter-integer
            line "i="))))
    (and id
         (copy-list
          (gethash id
                   *kitty-image-metadata*)))))

(defun crop-kitty-image-line
    (line hidden-rows visible-rows)
  (let* ((metadata
           (get-kitty-image-metadata line))
         (rows (getf metadata :rows))
         (height (getf metadata :height-px))
         (width (getf metadata :width-px))
         (columns (getf metadata :columns)))
    (unless
        (and
         metadata rows height width columns
         (> rows 0)
         (> hidden-rows 0)
         (> visible-rows 0))
      (return-from crop-kitty-image-line
        line))
    (multiple-value-bind
          (sequence-start controls-start
           controls-end)
        (kitty-control-header-bounds line)
      (unless controls-end
        (return-from crop-kitty-image-line
          line))
      (let* ((start
               (floor
                (* height hidden-rows)
                rows))
             (end
               (min
                height
                (ceiling
                 (* height
                    (+ hidden-rows
                       visible-rows))
                 rows)))
             (controls
               (append
                (remove-if
                 #'kitty-crop-control-p
                 (uiop:split-string
                  (subseq line
                          controls-start
                          controls-end)
                  :separator '(#\,)))
                (list
                 (format nil "y=~D" start)
                 (format nil "h=~D"
                         (max 1 (- end start)))
                 (format nil "r=~D"
                         visible-rows)))))
        (format
         nil "~A~C_G~{~A~^,~};~A"
         (subseq line 0 sequence-start)
         #\Escape controls
         (subseq line (1+ controls-end)))))))

(defun environment-value (name environment)
  (let ((prefix (concatenate 'string name "=")))
    (loop for entry in environment
          when (string-prefix-p prefix entry)
            do (return
                 (subseq entry (length prefix))))))

(defun truthy-environment-p (name environment)
  (let ((value (environment-value name environment)))
    (and value (plusp (length value)))))

(defun parse-boolean-capability-override (value)
  ;; pi@d981de122 terminal-image.ts:139-141 — only "1" and "0" override;
  ;; "auto" and anything else leave detection in place.
  (cond
    ((not (stringp value)) :unset)
    ((string= value "1") t)
    ((string= value "0") nil)
    (t :unset)))

(defun parse-image-protocol-override (value)
  (let ((normalized
          (string-downcase (or value ""))))
    (cond
      ((or (string= normalized "kitty")
           (string= normalized "iterm2"))
       (intern (string-upcase normalized) :keyword))
      ((or (string= normalized "none")
           (string= normalized "0"))
       nil)
      (t :unset))))

(defun apply-capability-overrides (capabilities overrides)
  (when overrides
    (let ((images (getf overrides :images :unset))
          (true-color (getf overrides :true-color-p :unset))
          (hyperlinks (getf overrides :hyperlinks-p :unset)))
      (unless (eq images :unset)
        (setf (terminal-capabilities-images capabilities) images))
      (unless (eq true-color :unset)
        (setf (terminal-capabilities-true-color-p capabilities)
              (not (null true-color))))
      (unless (eq hyperlinks :unset)
        (setf (terminal-capabilities-hyperlinks-p capabilities)
              (not (null hyperlinks))))))
  capabilities)

(defun detect-terminal-capabilities
    (&key
       (environment
         #+sbcl
         (sb-ext:posix-environ)
         #-sbcl nil)
       tmux-hyperlinks-p)
  (let* ((term-program
           (string-downcase
            (or (environment-value "TERM_PROGRAM"
                                   environment)
                "")))
         (terminal-emulator
           (string-downcase
            (or
             (environment-value "TERMINAL_EMULATOR"
                                environment)
             "")))
         (term
           (string-downcase
            (or (environment-value "TERM" environment)
                "")))
         (color-term
           (string-downcase
            (or (environment-value "COLORTERM"
                                   environment)
                "")))
         (true-color-hint-p
           (member color-term '("truecolor" "24bit")
                   :test #'string=))
         (hyperlinks-override
           (parse-boolean-capability-override
            (environment-value "CADR_HYPERLINKS"
                               environment)))
         (image-override
           (parse-image-protocol-override
            (environment-value "CADR_IMAGE_PROTOCOL"
                               environment)))
         (true-color-override
           (parse-boolean-capability-override
            (environment-value "CADR_TRUE_COLOR"
                               environment)))
         (tmux-hyperlinks
           (if (eq hyperlinks-override :unset)
               tmux-hyperlinks-p
               hyperlinks-override))
         (detected
           (cond
             ((or (truthy-environment-p "TMUX" environment)
                  (string-prefix-p "tmux" term))
              (make-terminal-capabilities
               :images nil
               :true-color-p (not (null true-color-hint-p))
               :hyperlinks-p (not (null tmux-hyperlinks))))
             ((string-prefix-p "screen" term)
              (make-terminal-capabilities
               :images nil
               :true-color-p (not (null true-color-hint-p))
               :hyperlinks-p nil))
             ((or (truthy-environment-p "KITTY_WINDOW_ID"
                                        environment)
                  (string= term-program "kitty")
                  (string= term-program "ghostty")
                  (search "ghostty" term)
                  (truthy-environment-p "GHOSTTY_RESOURCES_DIR"
                                        environment)
                  (truthy-environment-p "WEZTERM_PANE"
                                        environment)
                  (string= term-program "wezterm")
                  (string= term-program "warpterminal")
                  (truthy-environment-p "WARP_SESSION_ID"
                                        environment)
                  (truthy-environment-p
                   "WARP_TERMINAL_SESSION_UUID" environment))
              (make-terminal-capabilities
               :images :kitty :true-color-p t
               :hyperlinks-p t))
             ((or (truthy-environment-p "ITERM_SESSION_ID"
                                        environment)
                  (string= term-program "iterm.app"))
              (make-terminal-capabilities
               :images :iterm2 :true-color-p t
               :hyperlinks-p t))
             ((or (truthy-environment-p "WT_SESSION" environment)
                  (string= term-program "vscode")
                  (string= term-program "alacritty"))
              (make-terminal-capabilities
               :images nil :true-color-p t
               :hyperlinks-p t))
             ((string= terminal-emulator
                       "jetbrains-jediterm")
              (make-terminal-capabilities
               :images nil :true-color-p t
               :hyperlinks-p nil))
             (t
              (make-terminal-capabilities
               :images nil
               :true-color-p (not (null true-color-hint-p))
               :hyperlinks-p nil)))))
    (apply-capability-overrides
     detected
     (list :images image-override
           :true-color-p true-color-override
           :hyperlinks-p hyperlinks-override))))

(defun get-terminal-capabilities ()
  (or *terminal-capabilities*
      (setf *terminal-capabilities*
            (apply-capability-overrides
             (detect-terminal-capabilities)
             *capability-overrides*))))

(defun set-terminal-capabilities (capabilities)
  (setf *terminal-capabilities* capabilities))

(defun reset-terminal-capabilities ()
  (setf *terminal-capabilities* nil))

(defun set-capability-overrides (overrides)
  ;; pi@d981de122 terminal-image.ts:179-189 — skip work when the three
  ;; override fields are unchanged; otherwise drop the cached detection.
  (unless (equal overrides *capability-overrides*)
    (setf *capability-overrides* (copy-list overrides)
          *terminal-capabilities* nil))
  *capability-overrides*)

(defun reset-capability-overrides ()
  (setf *capability-overrides* nil
        *terminal-capabilities* nil))

(declaim (inline image-prefix-at-p))

(defun image-prefix-at-p (line position)
  (let ((remaining (- (length line) position)))
    (and
     (plusp remaining)
     (char= (char line position) #\Escape)
     (or
      (and
       (>= remaining 3)
       (char= (char line (1+ position)) #\_)
       (char= (char line (+ position 2)) #\G))
      (and
       (>= remaining 12)
       (char= (char line (1+ position)) #\])
       (string=
        "1337;File=" line
        :start2 (+ position 2)
        :end2 (+ position 12)))))))

(defun image-line-p (line)
  (loop with start = 0
        for position =
        (position #\Escape line :start start)
        while position
        when (image-prefix-at-p line position)
          do (return t)
        do (setf start (1+ position))
        finally (return nil)))

(defun allocate-image-id ()
  (1+ (random #xfffffffe)))

(defun encode-kitty-image
    (base64-data &key columns rows image-id
                         (move-cursor-p t))
  (let ((parameters
          (append
           '("a=T" "f=100" "q=2")
           (unless move-cursor-p '("C=1"))
           (when columns
             (list (format nil "c=~D" columns)))
           (when rows
             (list (format nil "r=~D" rows)))
           (when image-id
             (list (format nil "i=~D" image-id))))))
    (labels ((command (params chunk)
               (format nil "~C_G~{~A~^,~};~A~C\\"
                       #\Escape params chunk #\Escape)))
      (if (<= (length base64-data) 4096)
          (command parameters base64-data)
          (with-output-to-string (output)
            (loop with position = 0
                  with first-p = t
                  while (< position (length base64-data))
                  for end =
                  (min (length base64-data)
                       (+ position 4096))
                  for last-p = (= end (length base64-data))
                  for params =
                  (if first-p
                      (append parameters '("m=1"))
                      (list (if last-p "m=0" "m=1")))
                  do
                  (write-string
                   (command
                    params
                    (subseq base64-data position end))
                   output)
                  (setf position end
                        first-p nil)))))))

(defun delete-kitty-image (image-id)
  (format nil "~C_Ga=d,d=I,i=~D,q=2~C\\"
          #\Escape image-id #\Escape))

(defun delete-all-kitty-images ()
  (format nil "~C_Ga=d,d=A,q=2~C\\"
          #\Escape #\Escape))

(defparameter +base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defparameter +base64-decode-table+
  (let ((table (make-array 256 :initial-element nil)))
    (loop for index from 0
          for character across +base64-alphabet+
          do (setf (aref table (char-code character)) index))
    table))

(defun encode-base64-ascii (text)
  (let ((bytes
          (map 'vector #'codepoint text)))
    (with-output-to-string (output)
      (loop for position from 0 below (length bytes) by 3
            for remaining = (- (length bytes) position)
            for first = (aref bytes position)
            for second =
            (if (> remaining 1)
                (aref bytes (1+ position)) 0)
            for third =
            (if (> remaining 2)
                (aref bytes (+ position 2)) 0)
            for value =
            (logior (ash first 16)
                    (ash second 8)
                    third)
            do
            (write-char
             (char +base64-alphabet+
                   (ldb (byte 6 18) value))
             output)
            (write-char
             (char +base64-alphabet+
                   (ldb (byte 6 12) value))
             output)
            (write-char
             (if (> remaining 1)
                 (char +base64-alphabet+
                       (ldb (byte 6 6) value))
                 #\=)
             output)
            (write-char
             (if (> remaining 2)
                 (char +base64-alphabet+
                       (ldb (byte 6 0) value))
                 #\=)
             output)))))

(defun encode-iterm2-image
    (base64-data &key width height name
                         (preserve-aspect-ratio-p t)
                         (inline-p t))
  (let ((parameters
          (append
           (list (format nil "inline=~D"
                         (if inline-p 1 0)))
           (when width
             (list (format nil "width=~A" width)))
           (when height
             (list (format nil "height=~A" height)))
           (when name
             (list
              (format nil "name=~A"
                      (encode-base64-ascii name))))
           (unless preserve-aspect-ratio-p
             '("preserveAspectRatio=0")))))
    (format nil "~C]1337;File=~{~A~^;~}:~A~C"
            #\Escape parameters base64-data
            (code-char 7))))

(defun calculate-image-cell-size
    (image-width image-height max-width-cells
     &key max-height-cells
       (cell-width 9) (cell-height 18))
  (let* ((maximum-width
           (max 1 (floor max-width-cells)))
         (maximum-height
           (and max-height-cells
                (max 1 (floor max-height-cells))))
         (width (max 1 image-width))
         (height (max 1 image-height))
         (width-scale
           (/ (* maximum-width cell-width)
              width))
         (height-scale
           (if maximum-height
               (/ (* maximum-height cell-height)
                  height)
               width-scale))
         (scale (min width-scale height-scale))
         (columns
           (ceiling (/ (* width scale) cell-width)))
         (rows
           (ceiling (/ (* height scale) cell-height))))
    (values
     (max 1 (min maximum-width columns))
     (max 1 (if maximum-height
                (min maximum-height rows)
                rows)))))

(defun base64-value (character)
  (let ((code (char-code character)))
    (and (< code 256)
         (aref +base64-decode-table+ code))))

(defun decode-base64 (text &optional max-bytes)
  "Decode TEXT into an octet vector. When MAX-BYTES is set, stop once
that many output bytes are produced (PNG/GIF/WEBP headers only need
a few dozen). Returns NIL on malformed input."
  (let ((length (length text)))
    (labels
        ((emit (bytes out packed padding limit)
           (setf (aref bytes out) (ldb (byte 8 16) packed))
           (incf out)
           (when (and (< padding 2) (< out limit))
             (setf (aref bytes out) (ldb (byte 8 8) packed))
             (incf out))
           (when (and (zerop padding) (< out limit))
             (setf (aref bytes out) (ldb (byte 8 0) packed))
             (incf out))
           out)
         (decode-clean (clean)
           (let* ((clean-length (length clean))
                  (limit
                    (or max-bytes
                        (* (floor clean-length 4) 3)))
                  (bytes
                    (make-array
                     (min limit (* (floor clean-length 4) 3))
                     :element-type '(unsigned-byte 8)))
                  (out 0))
             (when (or (zerop clean-length)
                       (not (zerop (mod clean-length 4))))
               (return-from decode-base64 nil))
             (handler-case
                 (loop for position from 0 below clean-length by 4
                       while (< out limit)
                       do
                       (let* ((c0 (char clean position))
                              (c1 (char clean (1+ position)))
                              (c2 (char clean (+ position 2)))
                              (c3 (char clean (+ position 3)))
                              (padding
                                (+ (if (char= c2 #\=) 1 0)
                                   (if (char= c3 #\=) 1 0)))
                              (v0
                                (if (char= c0 #\=)
                                    0
                                    (or (base64-value c0)
                                        (error "bad"))))
                              (v1
                                (if (char= c1 #\=)
                                    0
                                    (or (base64-value c1)
                                        (error "bad"))))
                              (v2
                                (if (char= c2 #\=)
                                    0
                                    (or (base64-value c2)
                                        (error "bad"))))
                              (v3
                                (if (char= c3 #\=)
                                    0
                                    (or (base64-value c3)
                                        (error "bad"))))
                              (packed
                                (logior (ash v0 18)
                                        (ash v1 12)
                                        (ash v2 6)
                                        v3)))
                         (setf out
                               (emit bytes out packed padding
                                     limit))))
               (condition ()
                 (return-from decode-base64 nil)))
             (if (= out (length bytes))
                 bytes
                 (subseq bytes 0 out)))))
      (if (loop for i below length
                for c = (char text i)
                never (find c '(#\Space #\Tab #\Newline #\Return)))
          (decode-clean text)
          (decode-clean
           (remove-if
            (lambda (character)
              (find character
                    '(#\Space #\Tab #\Newline #\Return)))
            text))))))

(defun bytes-u16-be (bytes position)
  (logior (ash (aref bytes position) 8)
          (aref bytes (1+ position))))

(defun bytes-u16-le (bytes position)
  (logior (aref bytes position)
          (ash (aref bytes (1+ position)) 8)))

(defun bytes-u24-le (bytes position)
  (logior (aref bytes position)
          (ash (aref bytes (1+ position)) 8)
          (ash (aref bytes (+ position 2)) 16)))

(defun bytes-u32-be (bytes position)
  (logior
   (ash (aref bytes position) 24)
   (ash (aref bytes (1+ position)) 16)
   (ash (aref bytes (+ position 2)) 8)
   (aref bytes (+ position 3))))

(defun bytes-ascii= (bytes position text)
  (and (<= (+ position (length text))
           (length bytes))
       (loop for character across text
             for index from position
             always (= (aref bytes index)
                       (codepoint character)))))

(defun image-dimensions (base64-data mime-type)
  (let* ((header-bytes
           (cond
             ((string= mime-type "image/png") 24)
             ((string= mime-type "image/gif") 10)
             ((string= mime-type "image/webp") 30)
             ((string= mime-type "image/jpeg") 65536)
             (t nil)))
         (bytes
           (if header-bytes
               (decode-base64 base64-data header-bytes)
               (decode-base64 base64-data))))
    (unless bytes
      (return-from image-dimensions
        (values nil nil)))
    (cond
      ((and (string= mime-type "image/png")
            (>= (length bytes) 24)
            (= (aref bytes 0) #x89)
            (bytes-ascii= bytes 1 "PNG"))
       (values (bytes-u32-be bytes 16)
               (bytes-u32-be bytes 20)))
      ((and (string= mime-type "image/gif")
            (>= (length bytes) 10)
            (or (bytes-ascii= bytes 0 "GIF87a")
                (bytes-ascii= bytes 0 "GIF89a")))
       (values (bytes-u16-le bytes 6)
               (bytes-u16-le bytes 8)))
      ((and (string= mime-type "image/jpeg")
            (>= (length bytes) 2)
            (= (aref bytes 0) #xff)
            (= (aref bytes 1) #xd8))
       (loop with position = 2
             while (< position (- (length bytes) 9))
             do
             (if (/= (aref bytes position) #xff)
                 (incf position)
                 (let ((marker
                         (aref bytes (1+ position))))
                   (if (between-p marker #xc0 #xc2)
                       (return
                         (values
                          (bytes-u16-be bytes
                                        (+ position 7))
                          (bytes-u16-be bytes
                                        (+ position 5))))
                       (let ((size
                               (bytes-u16-be
                                bytes (+ position 2))))
                         (when (< size 2)
                           (return (values nil nil)))
                         (incf position (+ 2 size))))))
             finally (return (values nil nil))))
      ((and (string= mime-type "image/webp")
            (>= (length bytes) 30)
            (bytes-ascii= bytes 0 "RIFF")
            (bytes-ascii= bytes 8 "WEBP"))
       (cond
         ((bytes-ascii= bytes 12 "VP8X")
          (values
           (1+ (bytes-u24-le bytes 24))
           (1+ (bytes-u24-le bytes 27))))
         ((bytes-ascii= bytes 12 "VP8 ")
          (values
           (logand #x3fff
                   (bytes-u16-le bytes 26))
           (logand #x3fff
                   (bytes-u16-le bytes 28))))
         (t (values nil nil))))
      (t (values nil nil)))))

(defun render-terminal-image
    (base64-data image-width image-height
     &key (capabilities
            (get-terminal-capabilities))
       (max-width-cells 80)
       max-height-cells image-id
       (move-cursor-p t))
  (unless (terminal-capabilities-images capabilities)
    (return-from render-terminal-image nil))
  (multiple-value-bind (cell-width cell-height)
      (get-cell-dimensions)
    (multiple-value-bind (columns rows)
        (calculate-image-cell-size
         image-width image-height max-width-cells
         :max-height-cells max-height-cells
         :cell-width cell-width
         :cell-height cell-height)
      (let ((result
              (make-image-render-result
               :sequence
               (ecase
                   (terminal-capabilities-images
                    capabilities)
                 (:kitty
                  (encode-kitty-image
                   base64-data
                   :columns columns :rows rows
                   :image-id image-id
                   :move-cursor-p move-cursor-p))
                 (:iterm2
                  (encode-iterm2-image
                   base64-data
                   :width columns
                   :height "auto")))
               :rows rows
               :columns columns
               :image-id
               (and
                (eq :kitty
                    (terminal-capabilities-images
                     capabilities))
                image-id))))
        (when
            (and
             image-id
             (eq :kitty
                 (terminal-capabilities-images
                  capabilities)))
          (register-kitty-image-metadata
           :image-id image-id
           :columns columns
           :rows rows
           :width-px image-width
           :height-px image-height))
        result))))

(defun terminal-hyperlink (text url)
  (format nil "~C]8;;~A~C\\~A~C]8;;~C\\"
          #\Escape url #\Escape text
          #\Escape #\Escape))

(defun absolute-path-p (path)
  (and (plusp (length path))
       (char= (char path 0) #\/)))

(defun shortened-home-path (path)
  (let* ((home-path (namestring
                     (user-homedir-pathname)))
         (home
           (string-right-trim "/" home-path)))
    (if (or (string= path home)
            (string-prefix-p
             (concatenate 'string home "/")
             path))
        (concatenate
         'string "~" (subseq path (length home)))
        path)))

(defun shortened-home-prefix-path (path)
  (let* ((home-path
           (namestring (user-homedir-pathname)))
         (home (string-right-trim "/" home-path)))
    (if (string-prefix-p home path)
        (concatenate
         'string "~" (subseq path (length home)))
        path)))

(defun image-fallback
    (mime-type &key width height filename
       (capabilities (get-terminal-capabilities)))
  (let ((parts nil))
    (when filename
      (let ((display (shortened-home-path filename)))
        (push
         (if (and
              (terminal-capabilities-hyperlinks-p
               capabilities)
              (absolute-path-p filename))
             (terminal-hyperlink
              display
              (concatenate 'string "file://" filename))
             display)
         parts)))
    (push (format nil "[~A]" mime-type) parts)
    (when (and width height)
      (push (format nil "~Dx~D" width height)
            parts))
    (format nil "[Image: ~{~A~^ ~}]"
            (nreverse parts))))
