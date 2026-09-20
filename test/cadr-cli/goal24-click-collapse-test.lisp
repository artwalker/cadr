(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal24-plain-entry-text (entry width)
  (format
   nil "~{~A~^~%~}"
   (mapcar
    #'cadr-tui:strip-terminal-sequences
    (cadr-cli::render-tui-entry entry width))))

(defun goal24-make-skill-entry ()
  (cadr-cli::make-tui-entry
   :type :skill-invocation
   :label "example-skill"
   :text "skill details"))

(defun goal24-make-branch-entry ()
  (cadr-cli::make-tui-entry
   :type :branch-summary
   :text "branch details"))

(defun goal24-make-compaction-entry ()
  (cadr-cli::make-tui-entry
   :type :compaction-summary
   :text "compaction details"
   :tokens-before 1234))

(test goal24-click-toggles-compaction-summary
  (let ((entry (goal24-make-compaction-entry)))
    (is (not (search "compaction details"
                     (goal24-plain-entry-text entry 80))))
    (is (eq t (cadr-cli::toggle-tui-collapsible-summary-entry entry)))
    (is (search "compaction details"
                (goal24-plain-entry-text entry 80)))
    (is (null (cadr-cli::toggle-tui-collapsible-summary-entry entry)))
    (is (not (search "compaction details"
                     (goal24-plain-entry-text entry 80))))))

(test goal24-click-toggles-branch-summary
  (let ((entry (goal24-make-branch-entry)))
    (is (not (search "branch details"
                     (goal24-plain-entry-text entry 80))))
    (is (eq t (cadr-cli::toggle-tui-collapsible-summary-entry entry)))
    (is (search "branch details"
                (goal24-plain-entry-text entry 80)))
    (is (null (cadr-cli::toggle-tui-collapsible-summary-entry entry)))
    (is (not (search "branch details"
                     (goal24-plain-entry-text entry 80))))))

(test goal24-click-toggles-skill-invocation
  (let ((entry (goal24-make-skill-entry)))
    (is (not (search "skill details"
                     (goal24-plain-entry-text entry 80))))
    (is (eq t (cadr-cli::toggle-tui-collapsible-summary-entry entry)))
    (is (search "skill details"
                (goal24-plain-entry-text entry 80)))
    (is (null (cadr-cli::toggle-tui-collapsible-summary-entry entry)))
    (is (not (search "skill details"
                     (goal24-plain-entry-text entry 80))))))

(test goal24-summary-hints-use-expand-keybinding-text
  (let* ((expand-key (cadr-cli::key-text "app.tools.expand"))
         (skill (goal24-plain-entry-text (goal24-make-skill-entry) 80))
         (branch (goal24-plain-entry-text (goal24-make-branch-entry) 80))
         (compaction
           (goal24-plain-entry-text (goal24-make-compaction-entry) 80)))
    (is (search
         (format nil "[skill] example-skill (~A to expand)" expand-key)
         skill))
    (is (search
         (format nil "Branch summary (~A to expand)" expand-key)
         branch))
    (is (search
         (format nil "Compacted from 1,234 tokens (~A to expand)" expand-key)
         compaction))))

(test goal24-message-list-click-routes-to-one-entry
  (let* ((skill (goal24-make-skill-entry))
         (branch (goal24-make-branch-entry))
         (compaction (goal24-make-compaction-entry))
         (entries (list skill branch compaction)))
    (multiple-value-bind (lines ranges)
        (cadr-cli::render-tui-entries entries 80)
      (declare (ignore lines))
      (is (= 3 (length ranges)))
      (destructuring-bind (start end hit) (first ranges)
        (declare (ignore end))
        (is (eq skill hit))
        (is (eq t
                (cadr-cli::handle-collapsible-summary-click
                 ranges start)))
        (is (cadr-cli::tui-entry-expanded-p skill))
        (is (not (cadr-cli::tui-entry-expanded-p branch)))
        (is (not (cadr-cli::tui-entry-expanded-p compaction)))
        (is (eq t
                (cadr-cli::handle-collapsible-summary-click
                 ranges start)))
        (is (not (cadr-cli::tui-entry-expanded-p skill))))
      (destructuring-bind (start end hit) (second ranges)
        (declare (ignore end))
        (is (eq branch hit))
        (is (eq t
                (cadr-cli::handle-collapsible-summary-click
                 ranges start)))
        (is (cadr-cli::tui-entry-expanded-p branch))
        (is (not (cadr-cli::tui-entry-expanded-p skill))))
      (is (null
           (cadr-cli::handle-collapsible-summary-click
            ranges 0
            :button :right)))
      (is (null
           (cadr-cli::find-collapsible-summary-entry-at-y
            ranges -1))))))
