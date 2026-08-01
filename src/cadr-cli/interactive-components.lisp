(in-package #:cadr-cli)

(defun format-key-part (part capitalize-p)
  (let ((display
          (if (and (uiop:os-macosx-p)
                   (string-equal part "alt"))
              "option"
              part)))
    (if (and capitalize-p (plusp (length display)))
        (concatenate
         'string
         (string-upcase (subseq display 0 1))
         (subseq display 1))
        display)))

(defun format-key-text (key &key capitalize-p)
  (format
   nil "~{~A~^/~}"
   (mapcar
    (lambda (alternative)
      (format
       nil "~{~A~^+~}"
       (mapcar
        (lambda (part)
          (format-key-part part capitalize-p))
        (uiop:split-string alternative :separator '(#\+)))))
    (uiop:split-string key :separator '(#\/)))))

(defun key-text (keybinding)
  (format-key-text
   (format
    nil "~{~A~^/~}"
    (cadr-tui:keybinding-keys
     (cadr-tui:get-keybindings) keybinding))))

(defun key-display-text (keybinding)
  (format-key-text
   (format
    nil "~{~A~^/~}"
    (cadr-tui:keybinding-keys
     (cadr-tui:get-keybindings) keybinding))
   :capitalize-p t))

(defun raw-key-hint (key description)
  (concatenate
   'string
   (cadr-tui:theme-foreground :dim (format-key-text key))
   (cadr-tui:theme-foreground
    :muted (concatenate 'string " " description))))

(defun key-hint (keybinding description)
  (raw-key-hint (key-text keybinding) description))

(defclass dynamic-border-component (cadr-tui:component)
  ((color-function
    :initarg :color-function
    :accessor dynamic-border-color-function)))

(defun make-dynamic-border-component
    (&key
       (color-function
         (lambda (text)
           (cadr-tui:theme-foreground :border text))))
  (make-instance
   'dynamic-border-component
   :color-function color-function))

(defmethod cadr-tui:component-render
    ((component dynamic-border-component)
     width &key focused-p)
  (declare (ignore focused-p))
  (list
   (funcall
    (dynamic-border-color-function component)
    (make-string (max 1 width) :initial-element #\─))))

(defclass bordered-loader-component
    (cadr-tui:component-container)
  ((loader
    :initarg :loader
    :reader bordered-loader-loader)
   (cancellable-p
    :initarg :cancellable-p
    :reader bordered-loader-cancellable-p)
   (signal
    :initarg :signal
    :reader bordered-loader-signal)))

(defun make-bordered-loader-component
    (ui message &key (cancellable-p t) (start-p t))
  (let* ((accent
           (lambda (text)
             (cadr-tui:theme-foreground :accent text)))
         (muted
           (lambda (text)
             (cadr-tui:theme-foreground :muted text)))
         (loader
           (if cancellable-p
               (cadr-tui:make-cancellable-loader-component
                ui accent muted :message message
                :start-p start-p)
               (cadr-tui:make-loader-component
                ui accent muted :message message
                :start-p start-p)))
         (signal
           (if cancellable-p
               (cadr-tui:cancellable-loader-token loader)
               (make-instance 'cadr-tui:cancellation-token)))
         (component
           (make-instance
            'bordered-loader-component
            :loader loader :cancellable-p cancellable-p
            :signal signal)))
    (cadr-tui:component-add-child
     component
     (make-dynamic-border-component))
    (cadr-tui:component-add-child component loader)
    (when cancellable-p
      (cadr-tui:component-add-child
       component (cadr-tui:make-spacer-component :lines 1))
      (cadr-tui:component-add-child
       component
       (cadr-tui:make-text-component
        (key-hint "tui.select.cancel" "cancel")
        :padding-x 1 :padding-y 0)))
    (cadr-tui:component-add-child
     component (cadr-tui:make-spacer-component :lines 1))
    (cadr-tui:component-add-child
     component
     (make-dynamic-border-component))
    component))

(defun bordered-loader-set-on-abort (component function)
  (when (bordered-loader-cancellable-p component)
    (cadr-tui:cancellable-loader-set-on-abort
     (bordered-loader-loader component) function))
  component)

(defmethod cadr-tui:component-handle-event
    ((component bordered-loader-component) event)
  (if (bordered-loader-cancellable-p component)
      (cadr-tui:component-handle-event
       (bordered-loader-loader component) event)
      (values nil nil)))

(defmethod cadr-tui:component-dispose
    ((component bordered-loader-component))
  (cadr-tui:component-dispose
   (bordered-loader-loader component))
  component)

(defclass countdown-timer (cadr-tui:component)
  ((remaining-seconds
    :initarg :remaining-seconds
    :accessor countdown-timer-remaining-seconds)
   (ui
    :initarg :ui
    :reader countdown-timer-ui)
   (on-tick
    :initarg :on-tick
    :reader countdown-timer-on-tick)
   (on-expire
    :initarg :on-expire
    :reader countdown-timer-on-expire)
   (thread
    :initform nil
    :accessor countdown-timer-thread)
   (stop-p
    :initform nil
    :accessor countdown-timer-stop-p)
   (expired-p
    :initform nil
    :accessor countdown-timer-expired-p)))

(defun countdown-request-render (timer)
  (let ((ui (countdown-timer-ui timer)))
    (cond
      ((typep ui 'cadr-tui:tui-root)
       (cadr-tui:tui-request-render ui))
      ((functionp ui)
       (funcall ui)))))

(defun countdown-timer-tick (timer)
  (unless (or (countdown-timer-stop-p timer)
              (countdown-timer-expired-p timer))
    (decf (countdown-timer-remaining-seconds timer))
    (funcall
     (countdown-timer-on-tick timer)
     (countdown-timer-remaining-seconds timer))
    (countdown-request-render timer)
    (when (<= (countdown-timer-remaining-seconds timer) 0)
      (setf
       (countdown-timer-expired-p timer) t
       (countdown-timer-stop-p timer) t)
      (funcall (countdown-timer-on-expire timer))))
  timer)

(defun countdown-timer-run (timer)
  (loop
    (sleep 1)
    (when (countdown-timer-stop-p timer)
      (return))
    (countdown-timer-tick timer)))

(defun countdown-timer-start (timer)
  (setf (countdown-timer-stop-p timer) nil)
  (unless (countdown-timer-thread timer)
    (setf
     (countdown-timer-thread timer)
     (sb-thread:make-thread
      (lambda () (countdown-timer-run timer))
      :name "cadr countdown timer")))
  timer)

(defun make-countdown-timer
    (timeout-milliseconds ui on-tick on-expire
     &key (start-p t))
  (let* ((seconds
           (ceiling (max 0 timeout-milliseconds) 1000))
         (timer
           (make-instance
            'countdown-timer
            :remaining-seconds seconds
            :ui ui :on-tick on-tick
            :on-expire on-expire)))
    (funcall on-tick seconds)
    (when start-p (countdown-timer-start timer))
    timer))

(defmethod cadr-tui:component-dispose
    ((timer countdown-timer))
  (setf (countdown-timer-stop-p timer) t)
  (let ((thread (countdown-timer-thread timer)))
    (when (and thread
               (not (eq thread sb-thread:*current-thread*))
               (sb-thread:thread-alive-p thread))
      (sb-thread:join-thread thread))
    (setf (countdown-timer-thread timer) nil))
  timer)

(defparameter +armin-width+ 31)
(defparameter +armin-height+ 36)

(defparameter +armin-bits+
  #(#xff #xff #xff #x7f #xff #xf0 #xff #x7f #xff #xed #xff #x7f
    #xff #xdb #xff #x7f #xff #xb7 #xff #x7f #xff #x77 #xfe #x7f
    #x3f #xf8 #xfe #x7f #xdf #xff #xfe #x7f #xdf #x3f #xfc #x7f
    #x9f #xc3 #xfb #x7f #x6f #xfc #xf4 #x7f #xf7 #x0f #xf7 #x7f
    #xf7 #xff #xf7 #x7f #xf7 #xff #xe3 #x7f #xf7 #x07 #xe8 #x7f
    #xef #xf8 #x67 #x70 #x0f #xff #xbb #x6f #xf1 #x00 #xd0 #x5b
    #xfd #x3f #xec #x53 #xc1 #xff #xef #x57 #x9f #xfd #xee #x5f
    #x9f #xfc #xae #x5f #x1f #x78 #xac #x5f #x3f #x00 #x50 #x6c
    #x7f #x00 #xdc #x77 #xff #xc0 #x3f #x78 #xff #x01 #xf8 #x7f
    #xff #x03 #x9c #x78 #xff #x07 #x8c #x7c #xff #x0f #xce #x78
    #xff #xff #xcf #x7f #xff #xff #xcf #x78 #xff #xff #xdf #x78
    #xff #xff #xdf #x7d #xff #xff #x3f #x7e #xff #xff #xff #x7f))

(defun armin-pixel-p (x y)
  (when (< y +armin-height+)
    (let* ((bytes-per-row (ceiling +armin-width+ 8))
           (byte
             (aref +armin-bits+
                   (+ (* y bytes-per-row) (floor x 8)))))
      (zerop (logand byte (ash 1 (mod x 8)))))))

(defun armin-cell (x row)
  (let ((upper (armin-pixel-p x (* row 2)))
        (lower (armin-pixel-p x (1+ (* row 2)))))
    (cond
      ((and upper lower) #\█)
      (upper #\▀)
      (lower #\▄)
      (t #\Space))))

(defun make-armin-grid (&optional final-p)
  (loop for row below (ceiling +armin-height+ 2)
        collect
        (loop for x below +armin-width+
              collect
              (if final-p (armin-cell x row) #\Space))))

(defclass armin-component (cadr-tui:component)
  ((ui :initarg :ui :reader armin-component-ui)
   (effect :initarg :effect :reader armin-component-effect)
   (final-grid
    :initform (make-armin-grid t)
    :reader armin-component-final-grid)
   (current-grid
    :initform (make-armin-grid nil)
    :accessor armin-component-current-grid)
   (position :initform 0 :accessor armin-component-position)
   (thread :initform nil :accessor armin-component-thread)
   (stop-p :initform nil :accessor armin-component-stop-p)
   (version :initform 0 :accessor armin-component-version)
   (cached-key :initform nil :accessor armin-component-cached-key)
   (cached-lines :initform nil :accessor armin-component-cached-lines)))

(defparameter +armin-effects+
  '(:typewriter :scanline :rain :fade :crt :glitch :dissolve))

(defun make-armin-component
    (ui &key effect (start-p t))
  (let ((component
          (make-instance
           'armin-component :ui ui
           :effect
           (or effect
               (nth (random (length +armin-effects+))
                    +armin-effects+)))))
    (when (eq (armin-component-effect component) :dissolve)
      (setf
       (armin-component-current-grid component)
       (loop repeat (ceiling +armin-height+ 2)
             collect
             (loop repeat +armin-width+
                   collect
                   (aref " ░▒▓█▀▄" (random 7))))))
    (when start-p (armin-component-start component))
    component))

(defun armin-copy-cell (component position)
  (let ((row (floor position +armin-width+))
        (column (mod position +armin-width+)))
    (when (< row (length (armin-component-final-grid component)))
      (setf
       (nth column
            (nth row
                 (armin-component-current-grid component)))
       (nth column
            (nth row
                 (armin-component-final-grid component))))
      t)))

(defun armin-component-tick (component)
  (let* ((height (length (armin-component-final-grid component)))
         (effect (armin-component-effect component))
         (position (armin-component-position component))
         (done-p nil))
    (case effect
      (:typewriter
       (loop repeat 3
             do
         (unless (armin-copy-cell component position)
           (setf done-p t)
           (return))
         (incf position)))
      (:scanline
       (if (>= position height)
           (setf done-p t)
           (progn
             (setf
              (nth position
                   (armin-component-current-grid component))
              (copy-list
               (nth position
                    (armin-component-final-grid component))))
             (incf position))))
      (:fade
       (loop repeat 15
             do
         (unless (armin-copy-cell component position)
           (setf done-p t)
           (return))
         (incf position)))
      (:dissolve
       (loop repeat 20
             do
         (unless (armin-copy-cell component position)
           (setf done-p t)
           (return))
         (incf position)))
      (:crt
       (let* ((middle (floor height 2))
              (top (max 0 (- middle position)))
              (bottom (min (1- height) (+ middle position))))
         (setf (armin-component-current-grid component)
               (make-armin-grid nil))
         (loop for row from top to bottom
               do
               (setf
                (nth row
                     (armin-component-current-grid component))
                (copy-list
                 (nth row
                      (armin-component-final-grid component)))))
         (incf position)
         (setf done-p (> position height))))
      (:glitch
       (if (>= position 8)
           (progn
             (setf
              (armin-component-current-grid component)
              (mapcar #'copy-list
                      (armin-component-final-grid component))
              done-p t))
           (progn
             (setf
              (armin-component-current-grid component)
              (mapcar
               (lambda (row)
                 (let ((offset (- (random 7) 3)))
                   (if (< (random 10) 3)
                       (append
                        (subseq row (mod offset +armin-width+))
                        (subseq row 0 (mod offset +armin-width+)))
                       (copy-list row))))
               (armin-component-final-grid component)))
             (incf position))))
      (:rain
       (dotimes (column +armin-width+)
         (let ((row (mod (+ position column) height)))
           (setf
            (nth column
                 (nth row
                      (armin-component-current-grid component)))
            (nth column
                 (nth row
                      (armin-component-final-grid component))))))
       (incf position)
       (when (>= position (* height 2))
         (setf
          (armin-component-current-grid component)
          (mapcar #'copy-list
                  (armin-component-final-grid component))
          done-p t))))
    (setf
     (armin-component-position component) position
     (armin-component-cached-key component) nil)
    (incf (armin-component-version component))
    (cadr-tui:tui-request-render
     (armin-component-ui component))
    (when done-p
      (setf (armin-component-stop-p component) t))
    done-p))

(defun armin-component-run (component)
  (loop
    (sleep
     (if (eq (armin-component-effect component) :glitch)
         (/ 1d0 60d0)
         (/ 1d0 30d0)))
    (when (armin-component-stop-p component)
      (return))
    (when (armin-component-tick component)
      (return))))

(defun armin-component-start (component)
  (setf (armin-component-stop-p component) nil)
  (unless (armin-component-thread component)
    (setf
     (armin-component-thread component)
     (sb-thread:make-thread
      (lambda () (armin-component-run component))
      :name "cadr Armin animation")))
  component)

(defmethod cadr-tui:component-render
    ((component armin-component) width &key focused-p)
  (declare (ignore focused-p))
  (let ((key (list width (armin-component-version component))))
    (when (equal key (armin-component-cached-key component))
      (return-from cadr-tui:component-render
        (armin-component-cached-lines component)))
    (let* ((available (max 0 (1- width)))
           (lines
             (append
              (mapcar
               (lambda (row)
                 (let* ((raw (coerce row 'string))
                        (clipped
                          (subseq raw 0 (min available
                                             (length raw)))))
                   (concatenate
                    'string " "
                    (cadr-tui:theme-foreground :accent clipped)
                    (make-string
                     (max 0 (- available (length clipped)))
                     :initial-element #\Space))))
               (armin-component-current-grid component))
              (list
               (concatenate
                'string " "
                (cadr-tui:theme-foreground
                 :accent "ARMIN SAYS HI")
                (make-string
                 (max 0 (- available 13))
                 :initial-element #\Space))))))
      (setf
       (armin-component-cached-key component) key
       (armin-component-cached-lines component) lines)
      lines)))

(defmethod cadr-tui:component-invalidate
    ((component armin-component))
  (setf (armin-component-cached-key component) nil)
  component)

(defmethod cadr-tui:component-dispose
    ((component armin-component))
  (setf (armin-component-stop-p component) t)
  (let ((thread (armin-component-thread component)))
    (when (and thread
               (not (eq thread sb-thread:*current-thread*))
               (sb-thread:thread-alive-p thread))
      (sb-thread:join-thread thread))
    (setf (armin-component-thread component) nil))
  component)

(defclass daxnuts-component (cadr-tui:component)
  ((ui :initarg :ui :reader daxnuts-component-ui)
   (tick :initform 0 :accessor daxnuts-component-tick-value)
   (thread :initform nil :accessor daxnuts-component-thread)
   (stop-p :initform nil :accessor daxnuts-component-stop-p)
   (cached-key :initform nil :accessor daxnuts-component-cached-key)
   (cached-lines :initform nil :accessor daxnuts-component-cached-lines)))

(defparameter +daxnuts-width+ 32)
(defparameter +daxnuts-max-ticks+ 25)

(defparameter +daxnuts-hex+
  "bbbab8b9b9b6b9b8b5bcbbb8b8b7b4b7b5b2b6b5b2b8b7b4b7b6b3b6b4b1bdbcb8bab8b6bbb8b5b8b5b1bbb8b4c2bebbc1bebac0bdbabfbcb9c1bebabfbebbc0bfbcc0bdbabbb8b5c1bfbcbfbcb8bbb9b6bfbcb8c2bfbcc1bfbcbfbbb8bdb9b6b8b7b5b9b8b5b8b8b5b5b5b2b6b5b2b8b7b4b9b8b5b9b8b5b6b5b3bab8b5bcbab7bbb9b6bbb8b5bfb9b5bdb2abbcb0a8beb2aabeb5afbfbab6bebab7c0bfbcbebdbabebbb8c0bdbabfbebbc2bebbbdbab7c3c0bdc3c0bdc1bebbc2bebabfbcb8bab9b6b7b6b3b2b1aeb6b5b2b5b4b1b5b4b2b6b5b2b7b6b4b9b8b6b7b6b3bbbab7b2afaba5988fb49e90b09481b79a88b39683b09583b7a395bfb6b0c0bdbabdbbb8bebcb9c1bfbcc0bebbbdbab7bebbb8c2bfbcc0bdbac0bcb9bdb9b6c0bcb8b5b4b2b4b3b0bab9b6b9b9b6b5b4b1b5b4b1b6b5b3b9b8b5b9b8b6b9b8b6b2aeaa968174a6836eaa856eab846eaf8973ac8973b08f79b18f7ab39786b7a89dbbb3aebfbab6c2c0bdbebcb9bfbdbac3c1bdc2bebbc0bcb9bdb9b6c1bdbabfbbb8b4b3b0b9b8b5b8b7b5b4b3b1b5b4b1b8b7b4b8b7b5bab9b6bbbab7b1afad8c7a719d735ca47860a87d65a98069ae8972ae8c75af8d77aa826ba98067aa8974b39e90b6a79dbbb2adc0bdbac1bfbdbfbbb8c1bdb9bebab6c0bdb9bfbbb8c1bdbab4b2b0b7b6b4b7b6b3b4b2b0bab9b7b6b5b2b6b5b2bab9b6bab9b6958c87977663aa836bac8772b08f7aad8c77b2917db0917db0907cac8971a77d64a87f67ac8972b29887b8a89dbfbab5bfbdbac1bebac0bcb9c0bcb9c0bcb9c1bebabebab7b8b7b4b7b6b4b5b4b1b5b4b2b7b6b3b5b4b2bab9b7bab9b6b4b1ada88f7fad8973ae8d78b19684b19685b29786b69a89b29582b1917daa856ea87e66a97e66ad866ea9826baf9280b8ada6bdbbb8bebab7bfbbb8c1bdbabfbbb8bcb8b4bcb8b5b6b4b2b7b5b3b6b5b2b8b7b4b3b2afb8b7b4b6b5b2b3b2b0b3a59aab856fad8d78b0917eb19886b49b8bb49a89b39785b0917eaf8f7cab866fa77d65a77a61a87d64a9816ab08f79b5a296c1bcb8c3bfbcc2bebbbebab7bfbbb7bdbab6c2bebab8b7b4b7b6b4b6b5b3b7b6b3b6b5b2b9b8b6b4b3b1b6b1acac8f7ca9826bae8f7aaf9583b49c8cb49c8bb79d8cb59987b19380ad8e79ae8c77af8e78ac8771a3775faa826bae8972b39888bbb6b2bebbb8bfbbb8bfbbb8c0bdb9bebbb7c0bdb9b6b5b2b9b8b5b4b3b1b8b7b5b4b3b0b7b6b4b6b5b3b1a7a0aa8772a77d65a88570b49887b19b8d9c887c907a6d987f71aa907faf917daf8e7aad8c78ac8b77a8836ca9836cac8770b49b8abdb6b2c0bcb9c0bdb9bfbbb8bebab7bfbcb9bebab7b9b8b6b5b4b2b9b8b5b8b7b5b8b7b4b7b6b4b5b4b2b3a9a2ad8973a1755da9856fb398858c776a65544b776358725d526e594d9c7f6eb1907ba68672ad8e7aab8771ac856db18f79b3a092beb9b5c1bdbabdb9b5bebab7bfbbb7bebab7bcb9b6b7b6b4b6b6b3b8b7b4b5b4b2b8b6b4b7b6b3b4b3b0b4aba4a6826ba3775fb08e79b19584a88e7daa8e7db29481ad8f7c997e6da38674ac8d79ac8e7aae917f9a7c6a896a599a7c6ab3a398c1bdbabdb9b6bcb8b5bebab6bebab7bdb9b5bdb9b6b5b4b1b7b5b3b5b4b2b7b6b3b7b6b4b3b3b0b3b2b0b4aca5a7846fa97f68ae8f7bae9383b59c8bb2937fae8e79ac8b76af927eaf927eb29683b39885b2988891786a72594c6e594d978d86bdbab7bab7b3c0bcb9c0bcb9bebab7bebbb7bdb9b6b3b2b0b4b3b0b5b4b2b4b4b1b4b3b1b4b3b1b4b3b0b6ada5aa8670a57a62ad8e7ab29b8cb69d8dab856fa9826aa88069ab8771af907db49987b19684b29886b59987b39480b09787b5a9a1bcb8b5bebab7bdb9b5bebab7bfbbb8bfbbb7bbb7b4b3b2afb8b7b5b8b7b5b3b2b0b5b4b2b6b5b3b6b4b1afa299a98975a9826baf907cb39988b49a89af8e7aac8973aa856eaf8c74b1917dae907dac907db39988b29785b49785b7a090b9aca3bfbab7bcb8b5bdb9b6bcb8b4bcb8b5bdb9b5bcb8b4b5b4b2b6b5b3b4b3b0b4b3b0b9b8b5b8b6b4908b88887467aa8f7ea78976ad8973b08b74b59885b69e8eb29888b1917cb1917db1937fae907cb19686b39a8ab29886b59b8ab8a192b6aaa3b7b2afbcb8b4bcb8b5bbb7b4c0bcb9bebab7c0bcb9b6b5b2b6b5b3b4b3b0bab9b7b7b6b4b1b0ae7b716ba083709b806f716158967764b08870b29481b69b8ab69f8fb39a89b69f90b49d8db39a89b29988b49c8cb6a090b8a496baa49593867f8f8986bfbbb7bdb9b5bcb7b4bab6b3b9b5b2bab6b2b4b3b1b3b3b0b6b5b3b8b7b5b4b2b0a7a5a38f837dae917ea084725a504c63544da28370b39784b59e8db2a093a698909b918b998e8790857e95877dad998bb39c8cb5a091b9a2938d827c95908dbebab6bbb7b3bdbab7bbb7b4bdb9b6bbb7b4b4b3b0b5b4b1b8b7b5b6b5b3b8b8b5b4b2af968f8ab29a8bab9485544b483a323073655d96887f70655f61595547403e453e3c453f3d57504f655e5b90847db39c8db7a090b6a09189807aaba6a3bdb9b6c0bcb9bebab7bcb7b4bebab7bbb7b4b3b2b0b6b5b3b2b1afb7b6b4b8b7b4b5b4b1aeaba8b5a89fac998d4d44412d25244d46444e4744322b293a3230423937433a37352d2a59504c534b48524a48988a81b59f8fb19c8d827974b2afacbdb9b5bcb8b4bdb9b5bcb8b5bdb9b6bab6b2b8b7b5b5b4b2b6b6b3b9b8b5b7b6b3b6b5b2b8b6b3b9b4b1b2a9a26c64612d25242d2625312a28352d2c453d3a78675c8d7a6ea09792aea6a0615854332b29524a479f8e82b09d90a49b96c1bdb9bebab7bfbbb8bbb8b4b9b5b1b8b4b0b9b4b0b7b6b4b8b7b5b8b7b4b6b5b3b8b6b3bab9b6b9b8b5b4b3b0b7b5b2a5a29f453d3b261e1d261f1e2e2625413936857268977865b19482b5a69caca5a07c7572453d3b746963a0948cc5bfbbc0bbb8beb9b6bbb7b3bbb6b3b7b3afb8b4b0b9b5b1b7b6b3b6b5b3b5b4b2b5b4b2b7b6b3b7b6b3b8b6b3b4b2afb7b6b3b3b1ae6d6765251f1e1e18172a22212d2523443b3971625ab19888b09482a89182877e792c25243e3634766d6abeb9b5bfbbb7bebab6bcb7b3bbb6b3b9b5b1b7b3afb8b4b0b4b3b0b5b4b1b5b4b1b4b3b1b5b4b2b8b6b4b5b3b0b9b6b4b5b4b1b6b4b27f79762a2322221c1b2d2524221b1a443e3c47413f6f676281766f867971675e5a3e37352a222166605dbab7b3bdb9b5beb9b5bcb7b3bcb7b3b9b4b0bab6b2bab6b2b5b3b0b6b4b2b3b2afb7b6b3b4b4b1b4b3b0b6b4b1b5b4b1b4b3b0b9b6b29a8c8252474230292828201f181212322c2c231e1d1c16162c26252923222d26252d2523332b2a8e8885bcb8b5bcb7b3bbb6b2bcb7b3b9b4b1b9b5b1b7b2afb7b2ae7a838e9b9b9caeadacb3b2b0b3b2afb7b7b4b6b5b3b6b6b3b7b6b3b9ada4a991808e7b6f50453f2b24231a14142923221f19181d17161f18182620201d17162a22215d5654b7b3b0bbb7b3bbb6b2b8b4b0bab5b1bbb6b2bab5b1b8b4b0bab6b22c496b4c5d735f68766e727a828285929090adaba8b7b2aeb6a59ab39682a28470a387748e76674e403a1a14141d1716181211221c1c1f1918221c1b2f2827342d2c8d8884bab6b3b9b5b2bab5b1bab5b1b9b4b0bab6b2b8b4b0b9b4b0b7b2ae325e8b365f8a3a5d833f5b7a545f70646469706b6aa08f84b08e78b18e769f7e689e7f6b9e816d907766584940362d2a1c1615201b1a1a1413201a1a251e1d393331a39e9bbab5b1bcb7b3bab6b2b8b3afb8b4b0b9b4b0b9b4b1bab5b2b5b0ac3d6c9843729d44719c426e98415f805a64716f6a699d8677b1927eb3947faa89749d7a649f7f6ba487749e837186716454463f2c25231e181837302e3a33317a7471beb9b6bcb8b4bbb6b2b6b2aebab5b1b9b5b1b8b3afbab6b2b6b1adb5aeaa4877a14c7aa44e7ba345719a3a5d80586b7f767475927b6eb1927faf8e79b08e78a78169a07861a17f6aa58570a688749b83738270666f66618a8480a49e99b7b2aebab6b2bcb8b4b9b5b1b7b2aebab5b1b9b4b0b6b1aeb6b1adb2aca8b2aca84876a04a78a2517fa74771973a5d80405c7a6161677c695fac8a75b08d77b4917aaf8971ad876fa5816aa6846ea78670a98a76ac9484ab9f96b2aca8bdb8b4bcb7b3bcb8b4bcb8b4b8b3afb7b2aeb9b4b0b8b3afb8b2aeb6afabb3aeaab2aeaa4878a14b7aa34c7ba44a759b3d63873b5f825b67766f5f569c7e6caf8c77b18f79b28f78b5927caf8e78a98872aa8a76a98a76ac917fada199b7b0acb9b3afbfb9b5c1bab6bdb6b2b8b3afbab5b1b9b4b0b6afabb7b1adb3ada9b3aeaab0aba8")

(defun daxnuts-rgb-at (row column)
  (let ((offset (* (+ (* row +daxnuts-width+) column) 6)))
    (list
     (parse-integer +daxnuts-hex+
                    :start offset :end (+ offset 2)
                    :radix 16)
     (parse-integer +daxnuts-hex+
                    :start (+ offset 2) :end (+ offset 4)
                    :radix 16)
     (parse-integer +daxnuts-hex+
                    :start (+ offset 4) :end (+ offset 6)
                    :radix 16))))

(defun daxnuts-image-line (row)
  (with-output-to-string (output)
    (dotimes (column +daxnuts-width+)
      (destructuring-bind (top-red top-green top-blue)
          (daxnuts-rgb-at (* row 2) column)
        (destructuring-bind
            (bottom-red bottom-green bottom-blue)
            (daxnuts-rgb-at (1+ (* row 2)) column)
          (format
           output
           "~C[38;2;~D;~D;~Dm~C[48;2;~D;~D;~Dm▄"
           #\Escape
           bottom-red bottom-green bottom-blue
           #\Escape top-red top-green top-blue))))
    (format output "~C[0m" #\Escape)))

(defun center-component-line (line width)
  (concatenate
   'string
   (make-string
    (max 0 (floor (- width (cadr-tui:visible-width line)) 2))
    :initial-element #\Space)
   line))

(defun make-daxnuts-component (ui &key (start-p t))
  (let ((component
          (make-instance 'daxnuts-component :ui ui)))
    (when start-p (daxnuts-component-start component))
    component))

(defun daxnuts-component-tick (component)
  (when (< (daxnuts-component-tick-value component)
           +daxnuts-max-ticks+)
    (incf (daxnuts-component-tick-value component))
    (setf (daxnuts-component-cached-key component) nil)
    (when (>= (daxnuts-component-tick-value component)
              +daxnuts-max-ticks+)
      (setf (daxnuts-component-stop-p component) t))
    (cadr-tui:tui-request-render
     (daxnuts-component-ui component)))
  component)

(defun daxnuts-component-run (component)
  (loop
    (sleep 0.08d0)
    (when (daxnuts-component-stop-p component)
      (return))
    (daxnuts-component-tick component)))

(defun daxnuts-component-start (component)
  (setf (daxnuts-component-stop-p component) nil)
  (unless (daxnuts-component-thread component)
    (setf
     (daxnuts-component-thread component)
     (sb-thread:make-thread
      (lambda () (daxnuts-component-run component))
      :name "cadr Daxnuts animation")))
  component)

(defmethod cadr-tui:component-render
    ((component daxnuts-component) width &key focused-p)
  (declare (ignore focused-p))
  (let ((key (list width (daxnuts-component-tick-value component))))
    (when (equal key (daxnuts-component-cached-key component))
      (return-from cadr-tui:component-render
        (daxnuts-component-cached-lines component)))
    (let* ((tick (daxnuts-component-tick-value component))
           (revealed
             (min 16
                  (floor
                   (* tick 19)
                   +daxnuts-max-ticks+)))
           (lines (list "")))
      (dotimes (row 16)
        (push
         (center-component-line
          (cond
            ((< row revealed)
             (daxnuts-image-line row))
            ((= row revealed)
             (cadr-tui:theme-foreground
              :accent
              (make-string +daxnuts-width+
                           :initial-element #\▓)))
            (t (make-string +daxnuts-width+
                            :initial-element #\Space)))
          width)
         lines))
      (setf lines (nreverse lines))
      (setf lines
            (append
             lines
             (if (> tick 15)
                 (list
                  ""
                  (center-component-line
                   (cadr-tui:theme-foreground
                    :accent "Free Kimi K2.5 via OpenCode")
                   width)
                  (center-component-line
                   (cadr-tui:theme-foreground
                    :success "\"Powered by daxnuts\"")
                   width)
                  (center-component-line
                   (cadr-tui:theme-foreground :muted "— @thdxr")
                   width))
                 '("" "" "" ""))
             (if (> tick 17)
                 (list
                  (center-component-line
                   (cadr-tui:theme-foreground :dim "Try OpenCode")
                   width)
                  (center-component-line
                   (cadr-tui:theme-foreground
                    :md-link
                    "https://mistral.ai/news/mistral-vibe-2-0")
                   width)
                  "")
                 '("" "" ""))))
      (setf
       (daxnuts-component-cached-key component) key
       (daxnuts-component-cached-lines component) lines)
      lines)))

(defmethod cadr-tui:component-invalidate
    ((component daxnuts-component))
  (setf (daxnuts-component-cached-key component) nil)
  component)

(defmethod cadr-tui:component-dispose
    ((component daxnuts-component))
  (setf (daxnuts-component-stop-p component) t)
  (let ((thread (daxnuts-component-thread component)))
    (when (and thread
               (not (eq thread sb-thread:*current-thread*))
               (sb-thread:thread-alive-p thread))
      (sb-thread:join-thread thread))
    (setf (daxnuts-component-thread component) nil))
  component)

(defparameter +earendil-blog-url+
  "https://mariozechner.at/posts/2026-04-08-ive-sold-out/")

(defun make-earendil-announcement-component ()
  (let ((component (cadr-tui:make-component-container)))
    (cadr-tui:component-add-child
     component
     (make-dynamic-border-component
      :color-function
      (lambda (text)
        (cadr-tui:theme-foreground :accent text))))
    (cadr-tui:component-add-child
     component
     (cadr-tui:make-text-component
      (cadr-tui:theme-bold
       (cadr-tui:theme-foreground
        :accent "pi has joined Earendil"))
      :padding-x 1 :padding-y 0))
    (cadr-tui:component-add-child
     component (cadr-tui:make-spacer-component :lines 1))
    (cadr-tui:component-add-child
     component
     (cadr-tui:make-text-component
      (cadr-tui:theme-foreground :muted "Read the blog post:")
      :padding-x 1 :padding-y 0))
    (cadr-tui:component-add-child
     component
     (cadr-tui:make-text-component
      (cadr-tui:theme-foreground :md-link +earendil-blog-url+)
      :padding-x 1 :padding-y 0))
    (cadr-tui:component-add-child
     component (cadr-tui:make-spacer-component :lines 1))
    (cadr-tui:component-add-child
     component
     (make-dynamic-border-component
      :color-function
      (lambda (text)
        (cadr-tui:theme-foreground :accent text))))
    component))
