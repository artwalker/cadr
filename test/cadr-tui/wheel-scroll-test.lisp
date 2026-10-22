(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defun wheel-scroll-at (accelerator times
                        &optional (direction 1))
  (mapcar
   (lambda (time)
     (cadr-tui:wheel-scroll-accelerator-next
      accelerator direction time))
   times))

;; #9758
(test wheel-scroll-fixed-line-counts
  (let ((accelerator
          (cadr-tui:make-wheel-scroll-accelerator 3 t)))
    (is
     (equal
      '(3 3 3 3)
      (wheel-scroll-at accelerator '(0 10 20 1000))))
    (cadr-tui:wheel-scroll-accelerator-set-lines
     accelerator 0.5)
    (is
     (= 1
        (cadr-tui:wheel-scroll-accelerator-next
         accelerator 1 2000)))))

(test wheel-scroll-ssh-hides-macos-acceleration
  ;; pi@4a080252f wheel-scroll.ts terminalAcceleratesWheel. A present
  ;; SSH_CONNECTION, SSH_CLIENT, or SSH_TTY disables OS acceleration
  ;; even when the value is empty. The accelerator then scales fast spins.
  (is (cadr-tui:terminal-accelerates-wheel-p
       :darwin-p t :environment nil))
  (is (not (cadr-tui:terminal-accelerates-wheel-p
            :darwin-p nil :environment nil)))
  (dolist (pairs '((("SSH_CONNECTION" . "1 2 3 4"))
                   (("SSH_CLIENT" . ""))
                   (("SSH_TTY" . "/dev/pts/1"))))
    (is (not (cadr-tui:terminal-accelerates-wheel-p
              :darwin-p t :environment pairs))
        pairs))
  (let ((local
          (cadr-tui:make-wheel-scroll-accelerator
           :auto
           (not (cadr-tui:terminal-accelerates-wheel-p
                 :darwin-p t :environment nil))))
        (remote
          (cadr-tui:make-wheel-scroll-accelerator
           :auto
           (not (cadr-tui:terminal-accelerates-wheel-p
                 :darwin-p t
                 :environment '(("SSH_TTY" . "/dev/pts/1")))))))
    (is (equal '(1 1 1) (wheel-scroll-at local '(0 20 40))))
    (is (equal '(1 5 5) (wheel-scroll-at remote '(0 20 40))))))

(test wheel-scroll-auto-without-acceleration
  (let ((accelerator
          (cadr-tui:make-wheel-scroll-accelerator
           :auto nil)))
    (is
     (equal
      '(1 1 1 1)
      (wheel-scroll-at
       accelerator '(0 10 20 30))))))

(test wheel-scroll-auto-scales-with-velocity
  (let ((accelerator
          (cadr-tui:make-wheel-scroll-accelerator
           :auto t)))
    (is
     (equal
      '(1 1 1 1)
      (wheel-scroll-at
       accelerator '(0 150 300 450))))
    (is
     (equal
      '(1 2 2 2)
      (wheel-scroll-at
       accelerator '(1000 1050 1100 1150))))
    (is
     (equal
      '(1 5 5 5)
      (wheel-scroll-at
       accelerator '(2000 2020 2040 2060))))
    (is
     (equal
      '(1 6 6 6)
      (wheel-scroll-at
       accelerator '(3000 3010 3020 3030))))))

(test wheel-scroll-auto-ignores-burst-gaps
  (let ((accelerator
          (cadr-tui:make-wheel-scroll-accelerator
           :auto t)))
    (is
     (equal
      '(1 1 1 1)
      (wheel-scroll-at
       accelerator '(0 3 6 9))))))

(test wheel-scroll-auto-resets-on-direction-and-pause
  (let ((accelerator
          (cadr-tui:make-wheel-scroll-accelerator
           :auto t)))
    (is
     (equal
      '(1 5 5)
      (wheel-scroll-at accelerator '(0 20 40))))
    (is
     (= 1
        (cadr-tui:wheel-scroll-accelerator-next
         accelerator -1 60)))
    (is
     (equal
      '(1 5)
      (wheel-scroll-at accelerator '(500 520))))))

(test wheel-scroll-auto-carries-fractional-lines
  (let ((accelerator
          (cadr-tui:make-wheel-scroll-accelerator
           :auto t)))
    (is
     (equal
      '(1 2 3 2 3)
      (wheel-scroll-at
       accelerator '(0 40 80 120 160))))))
