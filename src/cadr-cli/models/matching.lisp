(in-package #:cadr-cli)

(defun canonical-model-id (model)
  (format nil "~A/~A"
          (provider-key
           (cadr-ai:model-provider model))
          (cadr-ai:model-id model)))

(defun exact-model-reference-match
    (reference models)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            reference))
         (canonical
           (remove-if-not
            (lambda (model)
              (string-equal
               trimmed
               (canonical-model-id model)))
            models)))
    (cond
      ((zerop (length trimmed)) nil)
      ((= 1 (length canonical))
       (first canonical))
      ((plusp (length canonical)) nil)
      (t
       (let ((by-id
               (remove-if-not
                (lambda (model)
                  (string-equal
                   trimmed
                   (cadr-ai:model-id model)))
                models)))
         (and (= 1 (length by-id))
              (first by-id)))))))

(defun alias-model-id-p (id)
  (or
   (uiop:string-suffix-p id "-latest")
   (not
    (cl-ppcre:scan "-[0-9]{8}$" id))))

(defun model-text-contains-p (model pattern)
  (or
   (search pattern
           (cadr-ai:model-id model)
           :test #'char-equal)
   (let ((name (cadr-ai::model-name model)))
     (and name
          (search pattern name
                  :test #'char-equal)))))

(defun best-partial-model-match
    (pattern models)
  (let* ((matches
           (remove-if-not
            (lambda (model)
              (model-text-contains-p
               model pattern))
            models))
         (aliases
           (remove-if-not
            (lambda (model)
              (alias-model-id-p
               (cadr-ai:model-id model)))
            matches))
         (candidates
           (or aliases matches)))
    (first
     (sort (copy-list candidates)
           #'string>
           :key #'cadr-ai:model-id))))

(defun match-single-model-pattern
    (pattern models)
  (or
   (exact-model-reference-match pattern models)
   (best-partial-model-match pattern models)))

(defun parse-scoped-model-pattern
    (pattern models)
  (let ((full
          (match-single-model-pattern
           pattern models)))
    (when full
      (return-from parse-scoped-model-pattern
        (values full nil nil)))
    (let ((colon
            (position #\: pattern :from-end t)))
      (unless colon
        (return-from parse-scoped-model-pattern
          (values nil nil nil)))
      (let* ((prefix (subseq pattern 0 colon))
             (suffix (subseq pattern (1+ colon)))
             (thinking
               (find suffix
                     +thinking-level-names+
                     :test #'string-equal)))
        (multiple-value-bind
              (model inner-thinking warning)
            (parse-scoped-model-pattern
             prefix models)
          (declare (ignore inner-thinking))
          (cond
            ((null model)
             (values nil nil warning))
            (thinking
             (values
              model
              (and (null warning)
                   (intern
                    (string-upcase thinking)
                    :keyword))
              warning))
            (t
             (values
              model nil
              (format nil
                      "Invalid thinking level ~S in pattern ~S. Using default instead."
                      suffix pattern)))))))))

(defun regex-literal-character
    (character output)
  (when
      (find character
            ".+(){}^$|\\")
    (write-char #\\ output))
  (write-char character output))

(defun glob-pattern-regex (pattern)
  (with-output-to-string (output)
    (write-char #\^ output)
    (loop with length = (length pattern)
          with index = 0
          while (< index length)
          for character = (char pattern index)
          do
          (case character
            (#\*
             (if
                 (and (< (1+ index) length)
                      (char= #\*
                             (char pattern
                                   (1+ index))))
                 (progn
                   (write-string ".*" output)
                   (incf index))
                 (write-string "[^/]*" output)))
            (#\?
             (write-string "[^/]" output))
            (#\[
             (let ((close
                     (position #\] pattern
                               :start (+ index 2))))
               (if (null close)
                   (write-string "\\[" output)
                   (let ((content
                           (subseq pattern
                                   (1+ index)
                                   close)))
                     (write-char #\[ output)
                     (when
                         (and (plusp
                               (length content))
                              (char= #\!
                                     (char content 0)))
                       (write-char #\^ output)
                       (setf content
                             (subseq content 1)))
                     (loop for class-character
                             across content
                           do
                           (when
                               (member class-character
                                       '(#\\ #\]))
                             (write-char #\\ output))
                           (write-char
                            class-character output))
                     (write-char #\] output)
                     (setf index close)))))
            (otherwise
             (regex-literal-character
              character output)))
          (incf index))
    (write-char #\$ output)))

(defun model-glob-matches-p
    (model pattern)
  (let ((scanner
          (cl-ppcre:create-scanner
           (glob-pattern-regex pattern)
           :case-insensitive-mode t)))
    (or
     (cl-ppcre:scan
      scanner (canonical-model-id model))
     (cl-ppcre:scan
      scanner (cadr-ai:model-id model)))))

(defun model-entry-present-p
    (model entries)
  (find model entries
        :key
        (lambda (entry)
          (getf entry :model))
        :test #'cadr-ai:models-equal-p))

(defun model-scope-diagnostic
    (code pattern message)
  (list
   :type :warning
   :code code
   :message message
   :pattern pattern))

(defun resolve-scoped-models-with-diagnostics
    (registry patterns)
  (let ((models
          (model-registry-models registry))
        (scoped nil)
        (diagnostics nil))
    (dolist (pattern patterns)
      (if
          (find-if
           (lambda (character)
             (find character "*?["))
           pattern)
          (let* ((colon
                   (position #\: pattern
                             :from-end t))
                 (suffix
                   (and colon
                        (subseq pattern
                                (1+ colon))))
                 (thinking-name
                   (and suffix
                        (find
                         suffix
                         +thinking-level-names+
                         :test #'string-equal)))
                 (thinking
                   (and thinking-name
                        (intern
                         (string-upcase
                          thinking-name)
                         :keyword)))
                 (glob
                   (if thinking
                       (subseq pattern 0 colon)
                       pattern))
                 (exact
                   (exact-model-reference-match
                    glob models))
                 (matches
                   (if exact
                       (list exact)
                       (remove-if-not
                        (lambda (model)
                          (model-glob-matches-p
                           model glob))
                        models))))
            (if matches
                (dolist (model matches)
                  (unless
                      (model-entry-present-p
                       model scoped)
                    (push
                     (list :model model :thinking thinking)
                     scoped)))
                (push
                 (model-scope-diagnostic
                  :no-match pattern
                  (format nil
                          "No models match pattern ~S"
                          pattern))
                 diagnostics)))
          (multiple-value-bind
                (model thinking warning)
              (parse-scoped-model-pattern
               pattern models)
            (when warning
              (push
               (model-scope-diagnostic
                :invalid-thinking-level
                pattern warning)
               diagnostics))
            (if model
                (unless
                    (model-entry-present-p
                     model scoped)
                  (push
                   (list :model model :thinking thinking)
                   scoped))
                (push
                 (model-scope-diagnostic
                  :no-match pattern
                  (format nil
                          "No models match pattern ~S"
                          pattern))
                 diagnostics)))))
    (values (nreverse scoped) (nreverse diagnostics))))

(defun enabled-model-ids-for-patterns
    (scoped diagnostics)
  (let ((ids nil))
    (dolist (entry scoped)
      (pushnew
       (canonical-model-id
        (getf entry :model))
       ids :test #'string=))
    (setf ids (nreverse ids))
    (dolist (diagnostic diagnostics)
      (when (eq :no-match
                (getf diagnostic :code))
        (setf ids
              (append
               ids
               (list
                (getf diagnostic
                      :pattern))))))
    (remove-duplicates ids
                       :test #'string=
                       :from-end t)))

(defun initial-scoped-model-entry
    (scoped default-provider default-model
     &key existing-session-p explicit-model-p)
  (unless
      (or existing-session-p explicit-model-p)
    (or
     (and
      default-provider
      default-model
      (find-if
       (lambda (entry)
         (let ((model (getf entry :model)))
           (and
            (string-equal
             (provider-key
              (cadr-ai:model-provider model))
             (provider-key default-provider))
            (string-equal
             (cadr-ai:model-id model)
             default-model))))
       scoped))
     (first scoped))))

(defun resolve-scoped-models
    (registry patterns)
  (mapcar
   (lambda (entry)
     (getf entry :model))
   (resolve-scoped-models-with-diagnostics
    registry patterns)))

(defun resolve-model
    (registry spec &key provider)
  (let* ((parsed
           (parse-model-spec spec provider))
         (resolved-provider
           (getf parsed :provider))
         (model-id (getf parsed :model))
         (matches
           (remove-if-not
            (lambda (model)
              (and
               (string=
                (cadr-ai:model-id model)
                model-id)
               (or
                (null resolved-provider)
                (string-equal
                 (provider-key
                  (cadr-ai:model-provider model))
                 resolved-provider))))
            (model-registry-models registry))))
    (cond
      ((null matches)
       (values nil
               (format nil
                       "Model not found: ~@[~A/~]~A"
                       resolved-provider model-id)
               (getf parsed :thinking)))
      ((or resolved-provider
           (= 1 (length matches)))
       (values (first matches)
               nil
               (getf parsed :thinking)))
      (t
       (values
        (or
         (find :openai-codex matches
               :key #'cadr-ai:model-provider)
         (find :openai matches
               :key #'cadr-ai:model-provider)
         (first matches))
        nil
        (getf parsed :thinking))))))
