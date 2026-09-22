(in-package #:cadr-tui)

(defvar *kitty-protocol-active-p* nil)

(defun set-kitty-protocol-active (active-p)
  (setf *kitty-protocol-active-p*
        (not (null active-p))))

(defun kitty-protocol-active-p ()
  *kitty-protocol-active-p*)

(defparameter +key-modifier-shift+ 1)
(defparameter +key-modifier-alt+ 2)
(defparameter +key-modifier-control+ 4)
(defparameter +key-modifier-super+ 8)
(defparameter +key-lock-mask+ (+ 64 128))

(defparameter +symbol-key-characters+
  "`-=[]\\;',./!@#$%^&*()_+|~{}:<>?")

(defparameter +kitty-keypad-map+
  '((57399 . 48) (57400 . 49) (57401 . 50)
    (57402 . 51) (57403 . 52) (57404 . 53)
    (57405 . 54) (57406 . 55) (57407 . 56)
    (57408 . 57) (57409 . 46) (57410 . 47)
    (57411 . 42) (57412 . 45) (57413 . 43)
    (57415 . 61) (57416 . 44)
    (57417 . :left) (57418 . :right)
    (57419 . :up) (57420 . :down)
    (57421 . :page-up) (57422 . :page-down)
    (57423 . :home) (57424 . :end)
    (57425 . :insert) (57426 . :delete)))

(defparameter +legacy-key-sequences+
  `((,(format nil "~C[A" #\Escape) . "up")
    (,(format nil "~C[B" #\Escape) . "down")
    (,(format nil "~C[C" #\Escape) . "right")
    (,(format nil "~C[D" #\Escape) . "left")
    (,(format nil "~COA" #\Escape) . "up")
    (,(format nil "~COB" #\Escape) . "down")
    (,(format nil "~COC" #\Escape) . "right")
    (,(format nil "~COD" #\Escape) . "left")
    (,(format nil "~C[H" #\Escape) . "home")
    (,(format nil "~COH" #\Escape) . "home")
    (,(format nil "~C[1~~" #\Escape) . "home")
    (,(format nil "~C[7~~" #\Escape) . "home")
    (,(format nil "~C[F" #\Escape) . "end")
    (,(format nil "~COF" #\Escape) . "end")
    (,(format nil "~C[4~~" #\Escape) . "end")
    (,(format nil "~C[8~~" #\Escape) . "end")
    (,(format nil "~C[2~~" #\Escape) . "insert")
    (,(format nil "~C[3~~" #\Escape) . "delete")
    (,(format nil "~C[5~~" #\Escape) . "pageUp")
    (,(format nil "~C[[5~~" #\Escape) . "pageUp")
    (,(format nil "~C[6~~" #\Escape) . "pageDown")
    (,(format nil "~C[[6~~" #\Escape) . "pageDown")
    (,(format nil "~C[E" #\Escape) . "clear")
    (,(format nil "~COE" #\Escape) . "clear")
    (,(format nil "~C[a" #\Escape) . "shift+up")
    (,(format nil "~C[b" #\Escape) . "shift+down")
    (,(format nil "~C[c" #\Escape) . "shift+right")
    (,(format nil "~C[d" #\Escape) . "shift+left")
    (,(format nil "~COa" #\Escape) . "ctrl+up")
    (,(format nil "~COb" #\Escape) . "ctrl+down")
    (,(format nil "~COc" #\Escape) . "ctrl+right")
    (,(format nil "~COd" #\Escape) . "ctrl+left")
    ;; pi@16787ad5b tui/keybindings.ts:170-175 — the prompt-jump
    ;; defaults use the legacy 1;6 modifier encoding.
    (,(format nil "~C[1;6A" #\Escape) . "ctrl+shift+up")
    (,(format nil "~C[1;6B" #\Escape) . "ctrl+shift+down")
    (,(format nil "~C[2$" #\Escape) . "shift+insert")
    (,(format nil "~C[2^" #\Escape) . "ctrl+insert")
    (,(format nil "~C[3$" #\Escape) . "shift+delete")
    (,(format nil "~C[3^" #\Escape) . "ctrl+delete")
    (,(format nil "~C[5$" #\Escape) . "shift+pageUp")
    (,(format nil "~C[5^" #\Escape) . "ctrl+pageUp")
    (,(format nil "~C[6$" #\Escape) . "shift+pageDown")
    (,(format nil "~C[6^" #\Escape) . "ctrl+pageDown")
    (,(format nil "~C[7$" #\Escape) . "shift+home")
    (,(format nil "~C[7^" #\Escape) . "ctrl+home")
    (,(format nil "~C[8$" #\Escape) . "shift+end")
    (,(format nil "~C[8^" #\Escape) . "ctrl+end")
    (,(format nil "~C[1;5H" #\Escape) . "ctrl+home")
    (,(format nil "~C[1;5F" #\Escape) . "ctrl+end")
    (,(format nil "~COP" #\Escape) . "f1")
    (,(format nil "~COQ" #\Escape) . "f2")
    (,(format nil "~COR" #\Escape) . "f3")
    (,(format nil "~COS" #\Escape) . "f4")
    (,(format nil "~C[11~~" #\Escape) . "f1")
    (,(format nil "~C[12~~" #\Escape) . "f2")
    (,(format nil "~C[13~~" #\Escape) . "f3")
    (,(format nil "~C[14~~" #\Escape) . "f4")
    (,(format nil "~C[15~~" #\Escape) . "f5")
    (,(format nil "~C[17~~" #\Escape) . "f6")
    (,(format nil "~C[18~~" #\Escape) . "f7")
    (,(format nil "~C[19~~" #\Escape) . "f8")
    (,(format nil "~C[20~~" #\Escape) . "f9")
    (,(format nil "~C[21~~" #\Escape) . "f10")
    (,(format nil "~C[23~~" #\Escape) . "f11")
    (,(format nil "~C[24~~" #\Escape) . "f12")
    (,(format nil "~C[[A" #\Escape) . "f1")
    (,(format nil "~C[[B" #\Escape) . "f2")
    (,(format nil "~C[[C" #\Escape) . "f3")
    (,(format nil "~C[[D" #\Escape) . "f4")
    (,(format nil "~C[[E" #\Escape) . "f5")
    (,(format nil "~Cb" #\Escape) . "alt+left")
    (,(format nil "~Cf" #\Escape) . "alt+right")
    (,(format nil "~Cp" #\Escape) . "alt+up")
    (,(format nil "~Cn" #\Escape) . "alt+down")))

(defparameter +kitty-pattern+
  (format nil
          "^~C\\[(\\d+)(?::(\\d*))?(?::(\\d+))?(?:;(\\d+))?(?::(\\d+))?u$"
          #\Escape))

(defparameter +modify-other-keys-pattern+
  (format nil "^~C\\[27;(\\d+);(\\d+)~~$"
          #\Escape))

(defparameter +modified-arrow-pattern+
  (format nil
          "^~C\\[1;(\\d+)(?::(\\d+))?([ABCD])$"
          #\Escape))

(defparameter +modified-function-pattern+
  (format nil
          "^~C\\[(\\d+)(?:;(\\d+))?(?::(\\d+))?~~$"
          #\Escape))

(defparameter +modified-home-end-pattern+
  (format nil
          "^~C\\[1;(\\d+)(?::(\\d+))?([HF])$"
          #\Escape))

(defparameter +kitty-scanner+
  (cl-ppcre:create-scanner +kitty-pattern+))
(defparameter +modify-other-keys-scanner+
  (cl-ppcre:create-scanner +modify-other-keys-pattern+))
(defparameter +modified-arrow-scanner+
  (cl-ppcre:create-scanner +modified-arrow-pattern+))
(defparameter +modified-function-scanner+
  (cl-ppcre:create-scanner +modified-function-pattern+))
(defparameter +modified-home-end-scanner+
  (cl-ppcre:create-scanner +modified-home-end-pattern+))

(defun regex-capture
    (text starts ends index)
  (let ((start (aref starts index))
        (end (aref ends index)))
    (when (and start end (>= start 0))
      (subseq text start end))))

(defun parse-kitty-key-data (data)
  (multiple-value-bind
        (start end starts ends)
      (cl-ppcre:scan +kitty-scanner+ data)
    (declare (ignore end))
    (when start
      (let* ((codepoint
               (parse-integer
                (regex-capture data starts ends 0)))
             (shifted-text
               (regex-capture data starts ends 1))
             (base-text
               (regex-capture data starts ends 2))
             (modifier-text
               (regex-capture data starts ends 3))
             (event-text
               (regex-capture data starts ends 4)))
        (list
         :codepoint codepoint
         :shifted
         (and shifted-text
              (plusp (length shifted-text))
              (parse-integer shifted-text))
         :base
         (and base-text
              (parse-integer base-text))
         :modifier
         (1-
          (if modifier-text
              (parse-integer modifier-text)
              1))
         :event
         (if event-text
             (parse-integer event-text)
             1))))))

(defun parse-modify-other-keys-data (data)
  (multiple-value-bind
        (start end starts ends)
      (cl-ppcre:scan +modify-other-keys-scanner+ data)
    (declare (ignore end))
    (when start
      (list
       :modifier
       (1-
        (parse-integer
         (regex-capture data starts ends 0)))
       :codepoint
       (parse-integer
        (regex-capture data starts ends 1))))))

(defun parse-modified-functional-key-data (data)
  (flet ((event-value (text)
           (if text (parse-integer text) 1)))
    (multiple-value-bind
          (start end starts ends)
        (cl-ppcre:scan +modified-arrow-scanner+ data)
      (declare (ignore end))
      (when start
        (let ((key
                (case
                    (char
                     (regex-capture data starts ends 2)
                     0)
                  (#\A :up)
                  (#\B :down)
                  (#\C :right)
                  (#\D :left))))
          (return-from parse-modified-functional-key-data
            (list
             :codepoint key
             :modifier
             (1-
              (parse-integer
               (regex-capture data starts ends 0)))
             :event
             (event-value
              (regex-capture data starts ends 1)))))))
    (multiple-value-bind
          (start end starts ends)
        (cl-ppcre:scan +modified-home-end-scanner+ data)
      (declare (ignore end))
      (when start
        (return-from parse-modified-functional-key-data
          (list
           :codepoint
           (if
               (char=
                #\H
                (char
                 (regex-capture data starts ends 2)
                 0))
               :home
               :end)
           :modifier
           (1-
            (parse-integer
             (regex-capture data starts ends 0)))
           :event
           (event-value
            (regex-capture data starts ends 1))))))
    (multiple-value-bind
          (start end starts ends)
        (cl-ppcre:scan +modified-function-scanner+ data)
      (declare (ignore end))
      (when start
        (let* ((number
                 (parse-integer
                  (regex-capture data starts ends 0)))
               (key
                 (cdr
                  (assoc number
                         '((2 . :insert)
                           (3 . :delete)
                           (5 . :page-up)
                           (6 . :page-down)
                           (7 . :home)
                           (8 . :end))))))
          (when key
            (return-from parse-modified-functional-key-data
              (list
               :codepoint key
               :modifier
               (let ((text
                       (regex-capture data starts ends 1)))
                 (1-
                  (if text
                      (parse-integer text)
                      1)))
               :event
               (event-value
                (regex-capture data starts ends 2))))))))))

(defun normalized-kitty-codepoint (value modifier)
  (let ((mapped (cdr (assoc value +kitty-keypad-map+))))
    (setf value (or mapped value))
    (if (and (integerp value)
             (not (zerop
                   (logand modifier
                           +key-modifier-shift+)))
             (between-p value 65 90))
        (+ value 32)
        value)))

(defun key-name-for-codepoint
    (codepoint modifier &optional base)
  (let* ((normalized
           (normalized-kitty-codepoint
            codepoint modifier))
         (authoritative-p
           (and
            (integerp normalized)
            (or (between-p normalized 48 57)
                (between-p normalized 97 122)
                (find (code-char normalized)
                      +symbol-key-characters+
                      :test #'char=))))
         (effective
           (if authoritative-p
               normalized
               (or base normalized)))
         (name
           (cond
             ((eq effective :left) "left")
             ((eq effective :right) "right")
             ((eq effective :up) "up")
             ((eq effective :down) "down")
             ((eq effective :page-up) "pageUp")
             ((eq effective :page-down) "pageDown")
             ((eq effective :home) "home")
             ((eq effective :end) "end")
             ((eq effective :insert) "insert")
             ((eq effective :delete) "delete")
             ((= effective 27) "escape")
             ((= effective 9) "tab")
             ((or (= effective 13)
                  (= effective 57414))
              "enter")
             ((= effective 32) "space")
             ((= effective 127) "backspace")
             ((and (integerp effective)
                   (or (between-p effective 48 57)
                       (between-p effective 97 122)
                       (find (code-char effective)
                             +symbol-key-characters+
                             :test #'char=)))
              (string (code-char effective)))
             (t nil))))
    (when name
      (let* ((mask
               (logand modifier
                       (lognot +key-lock-mask+)))
             (supported
               (logior
                +key-modifier-shift+
                +key-modifier-alt+
                +key-modifier-control+
                +key-modifier-super+)))
        (unless (zerop (logand mask (lognot supported)))
          (return-from key-name-for-codepoint nil))
        (format nil "~{~A~^+~}"
                (append
                 (when (logtest
                        +key-modifier-shift+ mask)
                   '("shift"))
                 (when (logtest
                        +key-modifier-control+ mask)
                   '("ctrl"))
                 (when (logtest
                        +key-modifier-alt+ mask)
                   '("alt"))
                 (when (logtest
                        +key-modifier-super+ mask)
                   '("super"))
                 (list name)))))))

(defun local-windows-terminal-p ()
  (and (uiop:getenv "WT_SESSION")
       (not (uiop:getenv "SSH_CONNECTION"))
       (not (uiop:getenv "SSH_CLIENT"))
       (not (uiop:getenv "SSH_TTY"))))

(defun parse-key (data)
  (let ((kitty (parse-kitty-key-data data)))
    (when kitty
      (return-from parse-key
        (key-name-for-codepoint
         (getf kitty :codepoint)
         (getf kitty :modifier)
         (getf kitty :base)))))
  (let ((modified-functional
          (parse-modified-functional-key-data data)))
    (when modified-functional
      (return-from parse-key
        (key-name-for-codepoint
         (getf modified-functional :codepoint)
         (getf modified-functional :modifier)))))
  (let ((modified
          (parse-modify-other-keys-data data)))
    (when modified
      (return-from parse-key
        (key-name-for-codepoint
         (getf modified :codepoint)
         (getf modified :modifier)))))
  (when *kitty-protocol-active-p*
    (when (or
           (string= data
                    (format nil "~C~C"
                            #\Escape #\Return))
           (string= data (string #\Newline)))
      (return-from parse-key "shift+enter")))
  (when
      (and
       (not *kitty-protocol-active-p*)
       (string=
        data
        (format nil "~C~C" #\Escape #\Return)))
    (return-from parse-key "alt+enter"))
  (let ((legacy
          (assoc data +legacy-key-sequences+
                 :test #'string=)))
    (when legacy
      (return-from parse-key (cdr legacy))))
  (cond
    ((string= data (string #\Escape)) "escape")
    ((string= data (string (code-char 28))) "ctrl+\\")
    ((string= data (string (code-char 29))) "ctrl+]")
    ((string= data (string (code-char 31))) "ctrl+-")
    ((string= data
              (format nil "~C~C"
                      #\Escape #\Escape))
     "ctrl+alt+[")
    ((string= data
              (format nil "~C~C"
                      #\Escape (code-char 28)))
     "ctrl+alt+\\")
    ((string= data
              (format nil "~C~C"
                      #\Escape (code-char 29)))
     "ctrl+alt+]")
    ((string= data
              (format nil "~C~C"
                      #\Escape (code-char 31)))
     "ctrl+alt+-")
    ((string= data (string #\Tab)) "tab")
    ((or (string= data (string #\Return))
         (and (not *kitty-protocol-active-p*)
              (string= data (string #\Newline))))
     "enter")
    ((string= data (string (code-char 0))) "ctrl+space")
    ((string= data " ") "space")
    ((string= data (string (code-char 127))) "backspace")
    ((string= data (string (code-char 8)))
     (if (local-windows-terminal-p)
         "ctrl+backspace"
         "backspace"))
    ((and (not *kitty-protocol-active-p*)
          (= (length data) 2)
          (char= (char data 0) #\Escape))
     (let* ((character (char data 1))
            (value (codepoint character)))
       (cond
         ((between-p value 1 26)
          (format nil "ctrl+alt+~C"
                  (code-char (+ value 96))))
         ((or (between-p value 48 57)
              (between-p value 97 122)
              (find character
                    +symbol-key-characters+
                    :test #'char=))
          (format nil "alt+~C" character))
         (t nil))))
    ((= (length data) 1)
     (let ((value (codepoint (char data 0))))
       (cond
         ((between-p value 1 26)
          (format nil "ctrl+~C"
                  (code-char (+ value 96))))
         ((between-p value 65 90)
          (format nil "shift+~C"
                  (code-char (+ value 32))))
         ((between-p value 32 126) data)
         (t nil))))
    (t nil)))

(defun split-key-id (key-id)
  (let* ((parts
           (uiop:split-string
            (string-downcase key-id)
            :separator '(#\+)))
         (key (car (last parts)))
         (modifiers (butlast parts)))
    (values
     (cond
       ((string= key "esc") "escape")
       ((string= key "return") "enter")
       (t key))
     (reduce
      #'logior modifiers
      :initial-value 0
      :key
      (lambda (modifier)
        (cond
          ((string= modifier "shift")
           +key-modifier-shift+)
          ((string= modifier "alt")
           +key-modifier-alt+)
          ((string= modifier "ctrl")
           +key-modifier-control+)
          ((string= modifier "super")
           +key-modifier-super+)
          (t 0)))))))

(defun canonical-key-id (key-id)
  (multiple-value-bind (key mask)
      (split-key-id key-id)
    (format nil "~D:~A" mask key)))

(defun raw-control-codepoint-for-key (key)
  (when (= (length key) 1)
    (let* ((character
             (char-downcase (char key 0)))
           (value (codepoint character)))
      (cond
        ((or (between-p value 97 122)
             (find character "[\\]_"
                   :test #'char=))
         (logand value #x1f))
        ((char= character #\-)
         31)
        (t nil)))))

(defun matches-key (data key-id)
  (multiple-value-bind (key mask)
      (split-key-id key-id)
    (when (and (= (length data) 1)
               (string= key "h")
               (= mask +key-modifier-control+)
               (= (codepoint (char data 0)) 8))
      (return-from matches-key t))
    (let ((control
            (and
             (= mask +key-modifier-control+)
             (raw-control-codepoint-for-key key))))
      (when (and control
                 (= (length data) 1)
                 (= (codepoint (char data 0))
                    control))
        (return-from matches-key t))))
  (let ((parsed (parse-key data)))
    (and parsed
         (string=
          (canonical-key-id parsed)
          (canonical-key-id key-id)))))

(defun decode-kitty-printable (data)
  (let ((kitty (parse-kitty-key-data data)))
    (when kitty
      (let* ((modifier
               (logand (getf kitty :modifier)
                       (lognot +key-lock-mask+)))
             (allowed +key-modifier-shift+))
        (when (zerop (logand modifier
                            (lognot allowed)))
          (let* ((raw
                   (if (and
                        (logtest
                         +key-modifier-shift+ modifier)
                        (getf kitty :shifted))
                       (getf kitty :shifted)
                       (getf kitty :codepoint)))
                 (value
                   (normalized-kitty-codepoint
                    raw modifier)))
            (when (and (integerp value)
                       (>= value 32)
                       (code-char value))
              (string (code-char value)))))))))

(defun decode-printable-key (data)
  (or
   (decode-kitty-printable data)
   (let ((modified
           (parse-modify-other-keys-data data)))
     (when modified
       (let ((modifier
               (logand (getf modified :modifier)
                       (lognot +key-lock-mask+)))
             (value (getf modified :codepoint)))
         (when (and
                (zerop
                 (logand modifier
                         (lognot +key-modifier-shift+)))
                (>= value 32)
                (code-char value))
           (string (code-char value))))))))

(defun key-release-p (data)
  (and (not (search
             (format nil "~C[200~~" #\Escape)
             data))
       (some
        (lambda (suffix) (search suffix data))
        '(":3u" ":3~" ":3A" ":3B" ":3C"
          ":3D" ":3H" ":3F"))))

(defun key-repeat-p (data)
  (and (not (search
             (format nil "~C[200~~" #\Escape)
             data))
       (some
        (lambda (suffix) (search suffix data))
        '(":2u" ":2~" ":2A" ":2B" ":2C"
          ":2D" ":2H" ":2F"))))
