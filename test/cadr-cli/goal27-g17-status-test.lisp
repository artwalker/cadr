(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal50-root ()
  (asdf:system-source-directory "cadr-cli"))

(defun goal50-text (relative)
  (uiop:read-file-string
   (merge-pathnames relative (goal50-root))))

(defun goal50-collapse (text)
  (with-output-to-string (out)
    (let ((space nil))
      (loop for char across text
            do (if (member char '(#\Space #\Newline #\Tab #\Return))
                   (unless space
                     (write-char #\Space out)
                     (setf space t))
                   (progn
                     (write-char char out)
                     (setf space nil)))))))

(defun goal50-git-status (arguments)
  (nth-value
   2
   (uiop:run-program
    (cons "git" arguments)
    :directory (namestring (goal50-root))
    :output '(:string :stripped t)
    :error-output '(:string :stripped t)
    :ignore-error-status t)))

(test goal50-g17-status-matches-the-part-g-booking
  (let ((part-g (goal50-collapse
                 (goal50-text "docs/acceptance/goal-v20-part-g.md")))
        (booking (goal50-collapse
                  (goal50-text "docs/benchmarks/goal20-paired-over-1x.md")))
        (ruling (goal50-collapse
                 (goal50-text "docs/adjudications.md"))))
    (is (search "| 17 Part P CL ceiling | met |" part-g))
    (is (search "594d066a4" part-g))
    (is (search "remesure25 0.98×, 0.97×, 0.66×, 0.86×" part-g))
    (is (search "remesure26 0.65×, 0.87×, 0.73×, 0.76×" part-g))
    (is (search "session_load | 1439.2 | 1465.4 | **0.98× (met)**" booking))
    (is (search "journal_read | 1275.9 | 1321.6 | **0.97× (met)**" booking))
    (is (search "pi_messages | 595.0 | 907.3 | **0.66× (met)**" booking))
    (is (search "mistral | 1488.8 | 1740.3 | **0.86× (met)**" booking))
    (is (search "session_load | 1374.7 | 2103.5 | **0.65× (met)**" booking))
    (is (search "journal_read | 1208.0 | 1393.6 | **0.87× (met)**" booking))
    (is (search "pi_messages | 579.4 | 790.8 | **0.73× (met)**" booking))
    (is (search "mistral | 1410.1 | 1847.5 | **0.76× (met)**" booking))
    (is (search "session_load 0.98×, journal_read 0.97×, pi_messages 0.66×, mistral 0.86×"
                ruling))
    (is (search "session_load 0.65×, journal_read 0.87×, pi_messages 0.73×, mistral 0.76×"
                ruling))
    (is (zerop (goal50-git-status
                '("merge-base" "--is-ancestor" "594d066a4" "HEAD"))))
    (dolist (relative
             '("docs/acceptance/goal23-pi-0851-alignment.md"
               "docs/acceptance/goal24-pi-0860-alignment.md"
               "docs/acceptance/goal25-pi-0861-alignment.md"
               "docs/acceptance/goal26-pi-0870-alignment.md"
               "docs/acceptance/goal26-pi-130-alignment.md"
               "docs/acceptance/goal26-pi-140-alignment.md"
               "docs/acceptance/goal27-pi-parity.md"
               "docs/acceptance/team-dev-platform.md"))
      (let ((text (goal50-text relative)))
        (is (null (search "G.17 保持 `missing`" text)) relative)
        (is (null (search "G.17 stays `missing`" text)) relative)
        (is (null (search "G.17 仍 `missing`" text)) relative)))))

(test goal50-deleted-v140-paths-are-not-pending-adjudication
  (let* ((ledger (goal50-text "docs/source-parity.md"))
         (paths nil))
    (is (null (search "PENDING ADJUDICATION" ledger)))
    (is (search "| `SP-F11` | 37 | 5.4% |" ledger))
    (with-input-from-string (stream ledger)
      (loop for line = (read-line stream nil nil)
            while line
            when (search "[class SP-F11]" line)
              do (let* ((start (search "`packages/" line))
                        (end (and start (position #\` line :start (1+ start)))))
                   (is (and start end))
                   (push (subseq line (1+ start) end) paths))))
    (is (= 37 (length paths)))
    (dolist (path paths)
      (is (not (zerop
                (goal50-git-status
                 (list "cat-file" "-e" (concatenate 'string "v1.4.0:" path)))))
          path))
    (is (zerop
         (goal50-git-status
          '("cat-file" "-e"
            "v1.4.0:packages/coding-agent/src/utils/management-http.ts"))))
    (is (search "defaults to 2 extra attempts" ledger))
    (is (search "each send one request and do not retry those statuses" ledger))))

(test goal50-v130-open-file-summary-is-retired
  (let ((summary (goal50-text "docs/acceptance/goal26-pi-130-alignment.md"))
        (tsv (goal50-text "docs/acceptance/goal26-evidence-v130/source-dispositions.tsv"))
        (retired 0))
    (is (null (search "open；对齐前必须 port" summary)))
    (is (null (search "open；对齐时 drop" summary)))
    (is (null (search "open；改映射" summary)))
    (is (search "75/75 仍在 v1.4.0" summary))
    (is (search "73/73 都不在 v1.4.0" summary))
    (is (search "packages/ai/src/utils/oauth-page.ts" summary))
    (is (null (search "open on pin" tsv)))
    (is (null (search "upstream deleted; drop or rewrite" tsv)))
    (with-input-from-string (stream tsv)
      (loop for line = (read-line stream nil nil)
            while line
            when (search "retired 2026-10-23 GAP-50" line)
              do (incf retired)))
    (is (= 149 retired))))
