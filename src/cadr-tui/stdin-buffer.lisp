(in-package #:cadr-tui)

(defstruct (stdin-buffer
            (:constructor make-stdin-buffer
                (&key (timeout-milliseconds 50)
                      (escape-timeout-milliseconds 10))))
  (buffer "" :type string)
  (paste-p nil :type boolean)
  (paste-buffer "" :type string)
  pending-kitty-codepoint
  (timeout-milliseconds 50 :type (integer 0 *))
  (escape-timeout-milliseconds 10 :type (integer 0 *)))

(defun string-suffix-p (suffix string)
  (and (<= (length suffix) (length string))
       (string= suffix string
                :start2 (- (length string)
                           (length suffix)))))

(defun kitty-unmodified-printable-codepoint (sequence)
  (when (and (> (length sequence) 3)
             (char= (char sequence 0) #\Escape)
             (char= (char sequence 1) #\[)
             (char= (char sequence
                          (1- (length sequence)))
                    #\u))
    (let ((body (subseq sequence 2
                        (1- (length sequence)))))
      (when (and (not (find #\; body))
                 (every
                  (lambda (character)
                    (or (digit-char-p character)
                        (char= character #\:)))
                  body))
        (let* ((colon (position #\: body))
               (value
                 (parse-integer
                  body :end colon :junk-allowed t)))
          (and value (>= value 32) value))))))

(defun stdin-buffer-emit-sequence (buffer sequence output)
  (let ((raw-codepoint
          (and (= (length sequence) 1)
               (codepoint (char sequence 0)))))
    (if (and raw-codepoint
             (eql raw-codepoint
                  (stdin-buffer-pending-kitty-codepoint buffer)))
        (progn
          (setf
           (stdin-buffer-pending-kitty-codepoint buffer)
           nil)
          output)
        (progn
          (setf
           (stdin-buffer-pending-kitty-codepoint buffer)
           (kitty-unmodified-printable-codepoint sequence))
          (cons sequence output)))))

(defun control-string-introducer-p (text)
  (and (>= (length text) 2)
       (char= (char text 0) #\Escape)
       (member (char text 1) '(#\] #\P #\_))))

(defun osc-palette-reply-header-p (text)
  ;; ESC ] 4 ; <1-3 digits> ;
  (unless (and (>= (length text) 6)
               (char= (char text 2) #\4)
               (char= (char text 3) #\;))
    (return-from osc-palette-reply-header-p nil))
  (let ((index 4)
        (digits 0))
    (loop while (and (< digits 3)
                     (< index (length text))
                     (digit-char-p (char text index)))
          do (incf digits)
             (incf index))
    (and (plusp digits)
         (< index (length text))
         (char= (char text index) #\;))))

(defun kitty-graphics-reply-header-p (text)
  ;; ESC _ G (letter = digits ,)* letter = digits ;
  (let ((index 2))
    (unless (and (< index (length text))
                 (char= (char text index) #\G))
      (return-from kitty-graphics-reply-header-p nil))
    (incf index)
    (loop
      (unless (and (< index (length text))
                   (lower-case-p (char text index)))
        (return-from kitty-graphics-reply-header-p nil))
      (incf index)
      (unless (and (< index (length text))
                   (char= (char text index) #\=))
        (return-from kitty-graphics-reply-header-p nil))
      (incf index)
      (let ((digits 0))
        (loop while (and (< index (length text))
                         (digit-char-p (char text index)))
              do (incf digits)
                 (incf index))
        (unless (plusp digits)
          (return-from kitty-graphics-reply-header-p nil)))
      (cond
        ((and (< index (length text))
              (char= (char text index) #\,))
         (incf index))
        ((and (< index (length text))
              (char= (char text index) #\;))
         (return-from kitty-graphics-reply-header-p t))
        (t
         (return-from kitty-graphics-reply-header-p nil))))))

(defun terminal-reply-header-p (text)
  ;; pi@71023aec1 stdin-buffer.ts. OSC 10/11, palette 4, program
  ;; status 7501, XTVERSION, and Kitty graphics replies. A shorter
  ;; prefix can still be a batched legacy Alt key.
  (unless (control-string-introducer-p text)
    (return-from terminal-reply-header-p nil))
  (case (char text 1)
    (#\]
     (or (and (>= (length text) 5)
              (char= (char text 2) #\1)
              (member (char text 3) '(#\0 #\1))
              (char= (char text 4) #\;))
         (and (>= (length text) 8)
              (string= text "7501;?" :start1 2 :end1 8))
         (osc-palette-reply-header-p text)))
    (#\P
     (and (>= (length text) 4)
          (char= (char text 2) #\>)
          (char= (char text 3) #\|)))
    (#\_
     (kitty-graphics-reply-header-p text))))

(defun consume-terminal-reply (remaining)
  ;; Returns status, advance, and the sequence when one was completed.
  ;; CAN and SUB drop the reply. A later escape that is not ST drops
  ;; the reply and leaves that escape to be parsed.
  (loop for seq-end from 1 to (length remaining)
        do
        (when (> seq-end 2)
          (let ((char (char remaining (1- seq-end))))
            (cond
              ((or (= (char-code char) #x18)
                   (= (char-code char) #x1a))
               (return-from consume-terminal-reply
                 (values :discard seq-end nil)))
              ((and (char= char #\Escape)
                    (< seq-end (length remaining))
                    (char/= (char remaining seq-end) #\\))
               (return-from consume-terminal-reply
                 (values :discard (1- seq-end) nil))))))
        (let* ((candidate (subseq remaining 0 seq-end))
               (length (complete-terminal-sequence-length candidate)))
          (when length
            (return-from consume-terminal-reply
              (values :sequence length
                      (subseq remaining 0 length))))))
  (values :incomplete 0 nil))

(defun stdin-buffer-extract (buffer text)
  (let ((sequences nil)
        (position 0)
        (length (length text)))
    (loop while (< position length)
          do
          (if (char= (char text position) #\Escape)
              (let ((remaining (subseq text position)))
                (if (terminal-reply-header-p remaining)
                    (multiple-value-bind (status advance sequence)
                        (consume-terminal-reply remaining)
                      (ecase status
                        (:incomplete (return))
                        (:discard (incf position advance))
                        (:sequence
                         (setf sequences
                               (stdin-buffer-emit-sequence
                                buffer sequence sequences))
                         (incf position advance))))
                    (let ((sequence-length
                            (complete-terminal-sequence-length
                             remaining)))
                      (unless sequence-length
                        (return))
                      (when (and (= sequence-length 2)
                                 (>= (length remaining) 3)
                                 (char= (char remaining 1) #\Escape)
                                 (member (char remaining 2)
                                         '(#\[ #\] #\O #\P #\_)))
                        (setf sequence-length 1))
                      (setf
                       sequences
                       (stdin-buffer-emit-sequence
                        buffer
                        (subseq remaining 0 sequence-length)
                        sequences))
                      (incf position sequence-length))))
              (progn
                (setf
                 sequences
                 (stdin-buffer-emit-sequence
                  buffer
                  (subseq text position (1+ position))
                  sequences))
                (incf position))))
    (values (nreverse sequences)
            (subseq text position))))

(defun stdin-input-string (data)
  (etypecase data
    (string data)
    ((vector (unsigned-byte 8))
     (if (and (= (length data) 1)
              (> (aref data 0) 127))
         (format nil "~C~C"
                 #\Escape
                 (code-char (- (aref data 0) 128)))
         (map 'string #'code-char data)))))

(defun stdin-buffer-process (buffer data)
  (let ((text (stdin-input-string data))
        (sequences nil)
        (pastes nil)
        (events nil))
    (when (and (zerop (length text))
               (zerop (length (stdin-buffer-buffer buffer))))
      (return-from stdin-buffer-process
        (values (list "") nil
                (list (list :data "")))))
    (if (stdin-buffer-paste-p buffer)
        (setf
         (stdin-buffer-paste-buffer buffer)
         (concatenate
          'string
          (stdin-buffer-paste-buffer buffer)
          (stdin-buffer-buffer buffer)
          text)
         (stdin-buffer-buffer buffer) "")
        (setf
         (stdin-buffer-buffer buffer)
         (concatenate 'string
                      (stdin-buffer-buffer buffer)
                      text)))
    (labels
        ((record-data (items)
           (setf
            sequences (nconc sequences items)
            events
            (nconc
             events
             (mapcar
              (lambda (item)
                (list :data item))
              items))))
         (record-paste (text)
           (setf
            pastes (nconc pastes (list text))
            events
            (nconc events
                   (list (list :paste text)))))
         (process-buffer ()
           (if (stdin-buffer-paste-p buffer)
               (finish-paste)
               (let ((start
                       (search +paste-start+
                               (stdin-buffer-buffer buffer))))
                 (if start
                     (multiple-value-bind (before remainder)
                         (stdin-buffer-extract
                          buffer
                          (subseq
                           (stdin-buffer-buffer buffer)
                           0 start))
                       (record-data before)
                       (setf
                        (stdin-buffer-pending-kitty-codepoint
                         buffer)
                        nil
                        (stdin-buffer-paste-p buffer) t
                        (stdin-buffer-paste-buffer buffer)
                        (concatenate
                         'string
                         remainder
                         (subseq
                          (stdin-buffer-buffer buffer)
                          (+ start
                             (length +paste-start+))))
                        (stdin-buffer-buffer buffer) "")
                       (finish-paste))
                     (multiple-value-bind (items remainder)
                         (stdin-buffer-extract
                          buffer
                          (stdin-buffer-buffer buffer))
                       (record-data items)
                       (setf
                        (stdin-buffer-buffer buffer)
                        remainder))))))
         (finish-paste ()
           (let ((end
                   (search +paste-end+
                           (stdin-buffer-paste-buffer buffer))))
             (when end
               (let ((content
                       (subseq
                        (stdin-buffer-paste-buffer buffer)
                        0 end))
                     (remaining
                       (subseq
                        (stdin-buffer-paste-buffer buffer)
                        (+ end (length +paste-end+)))))
                 (record-paste content)
                 (setf
                  (stdin-buffer-paste-p buffer) nil
                  (stdin-buffer-paste-buffer buffer) ""
                  (stdin-buffer-pending-kitty-codepoint buffer)
                  nil
                  (stdin-buffer-buffer buffer)
                  remaining)
                 (process-buffer))))))
      (process-buffer))
    (values sequences pastes events)))

(defun stdin-buffer-flush (buffer)
  ;; pi@71023aec1 #10256. A recognized reply waits for its terminator.
  ;; A longer control string that never became one is a legacy Alt key
  ;; plus the keys that were batched behind it.
  (let ((text (stdin-buffer-buffer buffer)))
    (cond
      ((zerop (length text)) nil)
      ((terminal-reply-header-p text) nil)
      ((and (> (length text) 2)
            (control-string-introducer-p text))
       (let ((introducer (subseq text 0 2))
             (tail (subseq text 2)))
         (setf (stdin-buffer-buffer buffer) ""
               (stdin-buffer-pending-kitty-codepoint buffer) nil)
         (multiple-value-bind (sequences pastes events)
             (stdin-buffer-process buffer tail)
           (declare (ignore pastes events))
           (cons introducer sequences))))
      (t
       (prog1 (list text)
         (setf (stdin-buffer-buffer buffer) ""
               (stdin-buffer-pending-kitty-codepoint buffer)
               nil))))))

(defun stdin-buffer-clear (buffer)
  (setf
   (stdin-buffer-buffer buffer) ""
   (stdin-buffer-paste-p buffer) nil
   (stdin-buffer-paste-buffer buffer) ""
   (stdin-buffer-pending-kitty-codepoint buffer) nil)
  buffer)

(defun stdin-buffer-destroy (buffer)
  (stdin-buffer-clear buffer))

(defun stdin-buffer-contents (buffer)
  (stdin-buffer-buffer buffer))
