(in-package #:cadr-tui)

(defstruct (stdin-buffer
            (:constructor make-stdin-buffer
                (&key (timeout-milliseconds 10))))
  (buffer "" :type string)
  (paste-p nil :type boolean)
  (paste-buffer "" :type string)
  pending-kitty-codepoint
  (timeout-milliseconds 10 :type (integer 0 *)))

(defun terminal-final-byte-p (character)
  (between-p (codepoint character) #x40 #x7e))

(defun string-suffix-p (suffix string)
  (and (<= (length suffix) (length string))
       (string= suffix string
                :start2 (- (length string)
                           (length suffix)))))

(defun control-string-end (text start &key bell-p)
  (loop for index from start below (length text)
        when (or (and bell-p
                      (= (codepoint (char text index)) 7))
                 (and (char= (char text index) #\Escape)
                      (< (1+ index) (length text))
                      (char= (char text (1+ index)) #\\)))
          do (return
               (if (= (codepoint (char text index)) 7)
                   (1+ index)
                   (+ index 2)))))

(defun complete-terminal-sequence-length (text)
  (unless (and (plusp (length text))
               (char= (char text 0) #\Escape))
    (return-from complete-terminal-sequence-length 1))
  (when (= (length text) 1)
    (return-from complete-terminal-sequence-length nil))
  (case (char text 1)
    (#\[
     (when (and (>= (length text) 3)
                (char= (char text 2) #\M))
       (return-from complete-terminal-sequence-length
         (and (>= (length text) 6) 6)))
     (loop for index from 2 below (length text)
           for character = (char text index)
           when (terminal-final-byte-p character)
             do
             (when (char= (char text 2) #\<)
               (let ((payload (subseq text 3 index)))
                 (unless
                     (and (member character '(#\M #\m))
                          (= 3
                             (length
                              (uiop:split-string
                               payload :separator '(#\;))))
                          (every
                           (lambda (part)
                             (and (plusp (length part))
                                  (every #'digit-char-p part)))
                           (uiop:split-string
                            payload :separator '(#\;))))
                   (return-from complete-terminal-sequence-length nil))))
             (return-from complete-terminal-sequence-length
               (1+ index)))
     nil)
    (#\]
     (control-string-end text 2 :bell-p t))
    ((#\P #\_)
     (control-string-end text 2))
    (#\O
     (and (>= (length text) 3) 3))
    (otherwise 2)))

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

(defun stdin-buffer-extract (buffer text)
  (let ((sequences nil)
        (position 0))
    (loop while (< position (length text))
          for remaining = (subseq text position)
          do
          (if (char= (char remaining 0) #\Escape)
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
                (incf position sequence-length))
              (progn
                (setf
                 sequences
                 (stdin-buffer-emit-sequence
                  buffer
                  (subseq remaining 0 1)
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
  (if (zerop (length (stdin-buffer-buffer buffer)))
      nil
      (prog1
          (list (stdin-buffer-buffer buffer))
        (setf
         (stdin-buffer-buffer buffer) ""
         (stdin-buffer-pending-kitty-codepoint buffer)
         nil))))

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
