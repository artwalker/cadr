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
