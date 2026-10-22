(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(test stdin-buffer-preserves-complete-terminal-sequences
  (let* ((escape (string #\Escape))
         (buffer (cadr-tui:make-stdin-buffer)))
    (multiple-value-bind (data pastes)
        (cadr-tui:stdin-buffer-process
         buffer
         (format nil "a~A[A~AOP~A[<35;20;5m"
                 escape escape escape))
      (is (equal
           (list "a"
                 (format nil "~A[A" escape)
                 (format nil "~AOP" escape)
                 (format nil "~A[<35;20;5m" escape))
           data))
      (is (null pastes)))
    (multiple-value-bind (data pastes)
        (cadr-tui:stdin-buffer-process buffer (format nil "~A[M!" escape))
      (is (null data))
      (is (null pastes)))
    (multiple-value-bind (data pastes)
        (cadr-tui:stdin-buffer-process buffer "\"#")
      (is (equal (list (format nil "~A[M!\"#" escape)) data))
      (is (null pastes)))))

(test stdin-buffer-handles-fragments-paste-and-kitty-deduplication
  (let* ((escape (string #\Escape))
         (buffer (cadr-tui:make-stdin-buffer)))
    (multiple-value-bind (data pastes)
        (cadr-tui:stdin-buffer-process buffer escape)
      (is (null data))
      (is (null pastes)))
    (is (equal
         (list (format nil "~A[A" escape))
         (cadr-tui:stdin-buffer-process buffer "[A")))
    (multiple-value-bind (data pastes)
        (cadr-tui:stdin-buffer-process
         buffer
         (concatenate
          'string "x" escape "[200~hello"
          (string #\Newline)))
      (is (equal '("x") data))
      (is (null pastes)))
    (multiple-value-bind (data pastes)
        (cadr-tui:stdin-buffer-process
         buffer
         (concatenate 'string
                      "世界" escape "[201~z"))
      (is (equal '("z") data))
      (is (equal (list (format nil "hello~%世界")) pastes)))
    (multiple-value-bind (data pastes)
        (cadr-tui:stdin-buffer-process
         buffer
         (format nil "~A[97u" escape))
      (is (equal (list (format nil "~A[97u" escape)) data))
      (is (null pastes)))
    (is (null (cadr-tui:stdin-buffer-process buffer "a")))
    (is (equal '("b")
               (cadr-tui:stdin-buffer-process buffer "b")))))

(test stdin-buffer-preserves-data-and-paste-event-order
  (let ((buffer (cadr-tui:make-stdin-buffer)))
    (multiple-value-bind (data pastes events)
        (cadr-tui:stdin-buffer-process
         buffer
         (concatenate
          'string
          "a"
          (format nil "~C[200~~" #\Escape)
          "中"
          (format nil "~C[201~~" #\Escape)
          "b"))
      (is (equal '("a" "b") data))
      (is (equal '("中") pastes))
      (is (equal '((:data "a")
                   (:paste "中")
                   (:data "b"))
                 events)))))

(test stdin-buffer-flush-clear-and-wezterm-escape
  (let* ((escape (string #\Escape))
         (buffer (cadr-tui:make-stdin-buffer)))
    (is (null (cadr-tui:stdin-buffer-process buffer escape)))
    (is (string= escape
                 (cadr-tui:stdin-buffer-contents buffer)))
    (is (equal (list escape)
               (cadr-tui:stdin-buffer-flush buffer)))
    (is (string= ""
                 (cadr-tui:stdin-buffer-contents buffer)))
    (is (equal
         (list escape (format nil "~A[27;1:3u" escape))
         (cadr-tui:stdin-buffer-process
          buffer
          (format nil "~A~A[27;1:3u" escape escape))))
    (cadr-tui:stdin-buffer-process
     buffer (format nil "~A[" escape))
    (cadr-tui:stdin-buffer-clear buffer)
    (is (string= ""
                 (cadr-tui:stdin-buffer-contents buffer)))
    (is (null (cadr-tui:stdin-buffer-flush buffer)))
    (cadr-tui:stdin-buffer-process
     buffer (concatenate 'string escape "[200~partial"))
    (cadr-tui:stdin-buffer-destroy buffer)
    (multiple-value-bind (data pastes)
        (cadr-tui:stdin-buffer-process buffer "")
      (is (equal '("") data))
      (is (null pastes)))))

(test stdin-buffer-keeps-delayed-terminal-replies-out-of-keyboard-input
  ;; pi@4a080252f #10256. A recognized reply stays buffered across
  ;; flushes until its terminator. CAN/SUB and a later escape drop the
  ;; unfinished reply. A short control prefix is still an Alt key, and
  ;; flushing it reparses the batched tail.
  (let ((replies
          (list
           (list (format nil "~C]4;1;" #\Escape)
                 (format nil "~C]4;1;rgb:eaea/6c6c/6d6d~C"
                         #\Escape (code-char 7)))
           (list (format nil "~C]10;" #\Escape)
                 (format nil "~C]10;rgb:ffff/ffff/ffff~C\\"
                         #\Escape #\Escape))
           (list (format nil "~C]11;" #\Escape)
                 (format nil "~C]11;rgb:0000/0000/0000~C"
                         #\Escape (code-char 7)))
           (list (format nil "~C]7501;?" #\Escape)
                 (format nil "~C]7501;?~C\\" #\Escape #\Escape))
           (list (format nil "~CP>|" #\Escape)
                 (format nil "~CP>|Ghostty 1.3.1~C\\" #\Escape #\Escape))
           (list (format nil "~C_Gi=1;" #\Escape)
                 (format nil "~C_Gi=1;OK~C\\" #\Escape #\Escape)))))
    (dolist (spec replies)
      (destructuring-bind (header reply) spec
        (loop for split from (length header) below (length reply)
              do
              (let ((buffer (cadr-tui:make-stdin-buffer)))
                (is (null
                     (cadr-tui:stdin-buffer-process
                      buffer (subseq reply 0 split))))
                (is (null (cadr-tui:stdin-buffer-flush buffer)))
                (is (equal
                     (list reply "x")
                     (cadr-tui:stdin-buffer-process
                      buffer
                      (concatenate 'string
                                   (subseq reply split) "x")))))))))
  (let ((buffer (cadr-tui:make-stdin-buffer))
        (reply (format nil "~C]4;1;rgb:eaea/6c6c/6d6d~C"
                       #\Escape (code-char 7))))
    (is (null
         (cadr-tui:stdin-buffer-process
          buffer (format nil "~C]4;1;rgb:eaea/6c" #\Escape))))
    (is (null (cadr-tui:stdin-buffer-flush buffer)))
    (is (null
         (cadr-tui:stdin-buffer-process buffer "6c/6d6d")))
    (is (null (cadr-tui:stdin-buffer-flush buffer)))
    (is (equal
         (list reply)
         (cadr-tui:stdin-buffer-process
          buffer (string (code-char 7))))))
  (let ((buffer (cadr-tui:make-stdin-buffer)))
    (dolist (prefix (list (format nil "~C]" #\Escape)
                          (format nil "~CP" #\Escape)
                          (format nil "~C_" #\Escape)))
      (is (null (cadr-tui:stdin-buffer-process buffer prefix)))
      (is (equal (list prefix)
                 (cadr-tui:stdin-buffer-flush buffer)))))
  (dolist (ambiguous
           (list (format nil "~C]a" #\Escape)
                 (format nil "~C]1" #\Escape)
                 (format nil "~C]10" #\Escape)
                 (format nil "~C]4;" #\Escape)
                 (format nil "~C]4;a;" #\Escape)
                 (format nil "~CPa" #\Escape)
                 (format nil "~CP>" #\Escape)
                 (format nil "~C_a" #\Escape)
                 (format nil "~C_G" #\Escape)
                 (format nil "~C_Gi=1" #\Escape)))
    (let ((buffer (cadr-tui:make-stdin-buffer))
          (tail (format nil "x~C~C~C"
                        #\Return (code-char 3) (code-char 4))))
      (is (null (cadr-tui:stdin-buffer-process buffer ambiguous)))
      (is (null (cadr-tui:stdin-buffer-process buffer tail)))
      (is (equal
           (append (list (subseq ambiguous 0 2))
                   (loop for index from 2 below (length ambiguous)
                         collect (string (char ambiguous index)))
                   (loop for index from 0 below (length tail)
                         collect (string (char tail index))))
           (cadr-tui:stdin-buffer-flush buffer)))
      (is (string= "" (cadr-tui:stdin-buffer-contents buffer)))))
  (let ((buffer (cadr-tui:make-stdin-buffer)))
    (is (null
         (cadr-tui:stdin-buffer-process
          buffer (format nil "~C]1" #\Escape))))
    (is (null (cadr-tui:stdin-buffer-process buffer "0;")))
    (is (null (cadr-tui:stdin-buffer-flush buffer)))
    (is (equal
         (list (format nil "~C]10;rgb:ffff/ffff/ffff~C\\"
                       #\Escape #\Escape))
         (cadr-tui:stdin-buffer-process
          buffer (format nil "rgb:ffff/ffff/ffff~C\\" #\Escape)))))
  (let ((buffer (cadr-tui:make-stdin-buffer)))
    (cadr-tui:stdin-buffer-process
     buffer (format nil "~C]4;1;rgb:eaea/6c" #\Escape))
    (is (null
         (cadr-tui:stdin-buffer-process
          buffer (string #\Escape))))
    (is (null (cadr-tui:stdin-buffer-flush buffer)))
    (is (equal
         (list (format nil "~C[A" #\Escape) "h" "e" "l" "l" "o")
         (cadr-tui:stdin-buffer-process buffer "[Ahello"))))
  (dolist (cancel (list (code-char #x18) (code-char #x1a)))
    (let ((buffer (cadr-tui:make-stdin-buffer)))
      (is (equal
           '("x")
           (cadr-tui:stdin-buffer-process
            buffer
            (format nil "~C]11;rgb:0000~Cx" #\Escape cancel)))))))
