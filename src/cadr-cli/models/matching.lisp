(in-package #:cadr-cli)

(defun canonical-model-id (model)
  (format nil "~A/~A"
          (provider-key
           (cadr-ai:model-provider model))
          (cadr-ai:model-id model)))

(defun exact-model-reference-match
    (reference models)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           reference)))
    (when (zerop (length trimmed))
      (return-from exact-model-reference-match nil))
    (flet ((unique-match (predicate)
             (let ((found nil)
                   (count 0))
               (dolist (model models)
                 (when (funcall predicate model)
                   (incf count)
                   (when (> count 1)
                     (return-from unique-match nil))
                   (setf found model)))
               found)))
      (or
       (unique-match
        (lambda (model)
          (string-equal
           trimmed
           (canonical-model-id model))))
       (unique-match
        (lambda (model)
          (string-equal
           trimmed
           (cadr-ai:model-id model))))))))

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
  (let ((best nil)
        (best-alias-p nil)
        (best-id nil))
    (dolist (model models)
      (when (model-text-contains-p model pattern)
        (let* ((id (cadr-ai:model-id model))
               (alias-p (alias-model-id-p id)))
          (when (or (null best)
                    (and alias-p (not best-alias-p))
                    (and (eq alias-p best-alias-p)
                         (string> id best-id)))
            (setf best model
                  best-alias-p alias-p
                  best-id id)))))
    best))

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
                   (resolve-model-reference
                    glob models
                    :thinking-suffix :none
                    :fuzzy nil
                    :usable (constantly t)))
                 (matches
                   (cond
                     ((eq :resolved (getf exact :status))
                      (list (getf exact :model)))
                     ((eq :ambiguous (getf exact :status))
                      (push
                       (model-scope-ambiguous-diagnostic
                        pattern (getf exact :candidates))
                       diagnostics)
                      (getf exact :candidates))
                     (t
                      (remove-if-not
                       (lambda (model)
                         (model-glob-matches-p model glob))
                       models)))))
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
          (let ((result
                  (resolve-model-reference
                   pattern models
                   :thinking-suffix :lenient
                   :fuzzy t
                   :usable (constantly t))))
            (when (getf result :warning)
              (push
               (model-scope-diagnostic
                :invalid-thinking-level
                pattern
                (getf result :warning))
               diagnostics))
            (case (getf result :status)
              (:resolved
               (unless
                   (model-entry-present-p
                    (getf result :model) scoped)
                 (push
                  (list :model (getf result :model)
                        :thinking (getf result :thinking))
                  scoped)))
              (:ambiguous
               (push
                (model-scope-ambiguous-diagnostic
                 pattern (getf result :candidates))
                diagnostics)
               (dolist (model (getf result :candidates))
                 (unless (model-entry-present-p model scoped)
                   (push
                    (list :model model
                          :thinking (getf result :thinking))
                    scoped))))
              (otherwise
               (push
                (model-scope-diagnostic
                 :no-match pattern
                 (format nil
                         "No models match pattern ~S"
                         pattern))
                diagnostics))))))
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

(defun model-provider-name (model)
  (provider-key (cadr-ai:model-provider model)))

(defun model-reference-result
    (status &key model candidates usable-count thinking warning target)
  (list :status status
        :model model
        :candidates candidates
        :usable-count (or usable-count 0)
        :thinking thinking
        :warning warning
        :target target))

(defun thinking-suffix-parts (text)
  (let ((colon (position #\: text :from-end t)))
    (when colon
      (let* ((suffix (subseq text (1+ colon)))
             (name
               (find suffix +thinking-level-names+
                     :test #'string-equal)))
        (when name
          (values
           (subseq text 0 colon)
           (intern (string-upcase name) :keyword)))))))

(defun provider-prefix-parts (text models)
  (let ((slash (position #\/ text)))
    (when slash
      (let ((prefix
              (string-trim
               '(#\Space #\Tab)
               (subseq text 0 slash)))
            (model-text
              (string-trim
               '(#\Space #\Tab)
               (subseq text (1+ slash)))))
        (when (and (plusp (length prefix))
                   (plusp (length model-text)))
          (let ((match
                  (find prefix models
                        :key #'model-provider-name
                        :test #'string-equal)))
            (when match
              (values (model-provider-name match)
                      model-text))))))))

(defun same-model-provider-p (models)
  (let ((name (model-provider-name (first models))))
    (every
     (lambda (model)
       (string-equal name (model-provider-name model)))
     (rest models))))

(defun select-model-reference (text models fuzzy usable)
  (let ((raw
          (remove-if-not
           (lambda (model)
             (string-equal (cadr-ai:model-id model) text))
           models))
        (named nil))
    (multiple-value-bind (provider model-text)
        (provider-prefix-parts text models)
      (when provider
        (let ((provider-models
                (remove-if-not
                 (lambda (model)
                   (string-equal
                    (model-provider-name model) provider))
                 models)))
          (setf named
                (or
                 (find model-text provider-models
                       :key #'cadr-ai:model-id
                       :test #'string-equal)
                 (find provider raw
                       :key #'model-provider-name
                       :test #'string-equal)
                 (and fuzzy
                      (best-partial-model-match
                       model-text provider-models)))))))
    (let* ((others (remove named raw :test #'eq))
           (candidates
             (if named (cons named others) others)))
      (cond
        ((null candidates) nil)
        ((same-model-provider-p candidates)
         (model-reference-result :resolved
                                 :model (first candidates)))
        ((and named
              (funcall usable (model-provider-name named)))
         (model-reference-result :resolved :model named))
        (t
         (let ((usable-others
                 (remove-if-not
                  (lambda (model)
                    (funcall usable
                             (model-provider-name model)))
                  others)))
           (cond
             ((= 1 (length usable-others))
              (model-reference-result
               :resolved :model (first usable-others)))
             ((and (null usable-others) named)
              (model-reference-result :resolved :model named))
             (t
              (model-reference-result
               :ambiguous
               :candidates candidates
               :usable-count (length usable-others))))))))))

(defun select-fuzzy-model (text matches usable)
  (when matches
    (let* ((providers
             (remove-duplicates
              (mapcar #'model-provider-name matches)
              :test #'string-equal))
           (usable-matches
             (when (> (length providers) 1)
               (remove-if-not
                (lambda (model)
                  (funcall usable (model-provider-name model)))
                matches)))
           (pool (or usable-matches matches))
           (best (best-partial-model-match text pool)))
      (when best
        (let ((tied
                (remove-if-not
                 (lambda (model)
                   (string=
                    (cadr-ai:model-id model)
                    (cadr-ai:model-id best)))
                 pool)))
          (if (same-model-provider-p tied)
              (model-reference-result :resolved :model best)
              (model-reference-result
               :ambiguous
               :candidates tied
               :usable-count
               (if usable-matches (length tied) 0))))))))

(defun resolve-model-text
    (text models thinking-suffix fuzzy usable)
  (or (select-model-reference text models fuzzy usable)
      (and fuzzy
           (select-fuzzy-model
            text
            (remove-if-not
             (lambda (model)
               (model-text-contains-p model text))
             models)
            usable))
      (cond
        ((eq thinking-suffix :none) nil)
        (t
         (multiple-value-bind (base thinking)
             (thinking-suffix-parts text)
           (cond
             (thinking
              (let ((inner
                      (resolve-model-text
                       base models thinking-suffix fuzzy usable)))
                (when inner
                  (unless (getf inner :warning)
                    (setf (getf inner :thinking) thinking))
                  inner)))
             ((eq thinking-suffix :strict) nil)
             (t
              (let ((colon (position #\: text :from-end t)))
                (when colon
                  (let ((inner
                          (resolve-model-text
                           (subseq text 0 colon)
                           models thinking-suffix fuzzy usable)))
                    (when inner
                      (setf (getf inner :thinking) nil
                            (getf inner :warning)
                            (format nil
                                    "Invalid thinking level \"~A\" in pattern \"~A\". Using default instead."
                                    (subseq text (1+ colon))
                                    text))
                      inner)))))))))))

(defun resolve-model-reference
    (text models &key provider (thinking-suffix :strict)
                      (fuzzy t) (usable (constantly t)))
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or text ""))))
    (when (zerop (length trimmed))
      (return-from resolve-model-reference
        (model-reference-result :not-found)))
    (let* ((pool
             (if provider
                 (remove-if-not
                  (lambda (model)
                    (string-equal
                     (model-provider-name model) provider))
                  models)
                 models))
           (result
             (resolve-model-text
              trimmed pool thinking-suffix fuzzy usable)))
      (or result
          (multiple-value-bind (split-provider model-text)
              (provider-prefix-parts trimmed pool)
            (let ((anchor
                    (if provider
                        (first pool)
                        (and split-provider
                             (find split-provider pool
                                   :key #'model-provider-name
                                   :test #'string-equal)))))
              (if (null anchor)
                  (model-reference-result :not-found)
                  (let* ((model-text (or model-text trimmed))
                         (base nil)
                         (level nil))
                    (unless (eq thinking-suffix :none)
                      (multiple-value-setq (base level)
                        (thinking-suffix-parts model-text)))
                    (model-reference-result
                     :not-found
                     :target
                     (list
                      :provider (model-provider-name anchor)
                      :models
                      (cons anchor
                            (remove anchor pool :test #'eq))
                      :model-text model-text
                      :model-id (or base model-text)
                      :thinking level))))))))))

(defun model-scope-ambiguous-diagnostic (pattern candidates)
  (model-scope-diagnostic
   :ambiguous pattern
   (format nil
           "Pattern \"~A\" matches several providers: ~{~A~^, ~}. Use provider/id to choose one."
           pattern
           (sort
            (remove-duplicates
             (mapcar #'model-provider-name candidates)
             :test #'string-equal)
            #'string<))))

(defun resolve-model
    (registry spec &key provider (usable (constantly t)))
  (let ((result
          (resolve-model-reference
           spec
           (model-registry-models registry)
           :provider provider
           :thinking-suffix :strict
           :fuzzy t
           :usable usable)))
    (case (getf result :status)
      (:resolved
       (values (getf result :model)
               nil
               (getf result :thinking)))
      (:ambiguous
       (values
        nil
        (format nil
                "Model \"~A\" is ambiguous across providers: ~{~A~^, ~}."
                spec
                (sort
                 (mapcar #'canonical-model-id
                         (getf result :candidates))
                 #'string<))
        (getf result :thinking)))
      (otherwise
       (values nil
               (format nil "Model not found: ~A" spec)
               nil)))))

(defun provider-has-configured-auth-p (registry provider-name)
  (let ((model
          (find provider-name
                (model-registry-models registry)
                :key #'model-provider-name
                :test #'string-equal)))
    (and model
         (handler-case
             (not
              (eq :none
                  (provider-config-auth-source
                   (provider-config-for-model
                    registry model
                    :allow-missing-auth-p t))))
           (condition () nil)))))

(defun custom-provider-model (provider-models model-id reasoning-p)
  (let* ((provider (model-provider-name (first provider-models)))
         (definition
           (cadr-ai:find-provider-definition
            (provider-symbol-from-key provider)))
         (default-id
           (and definition
                (cadr-ai:provider-definition-default-model
                 definition)))
         (base
           (or (and default-id
                    (find default-id provider-models
                          :key #'cadr-ai:model-id
                          :test #'string=))
               (first provider-models)))
         (copy (cadr-ai::copy-model base)))
    (setf (cadr-ai:model-id copy) model-id
          (cadr-ai::model-name copy) model-id)
    (when reasoning-p
      (setf (cadr-ai:model-reasoning-p copy) t))
    copy))

(defun resolve-cli-model
    (registry model-text &key provider inline-api-key-p explicit-thinking)
  (let ((models (model-registry-models registry)))
    (when (null models)
      (return-from resolve-cli-model
        (values nil
                "No models available. Check your installation or add models to models.json."
                nil nil)))
    (let ((provider-name
            (and provider
                 (let ((match
                         (find provider models
                               :key #'model-provider-name
                               :test #'string-equal)))
                   (and match (model-provider-name match))))))
      (when (and provider (null provider-name))
        (return-from resolve-cli-model
          (values nil
                  (format nil
                          "Unknown provider \"~A\". Use --list-models to see available providers/models."
                          provider)
                  nil nil)))
      (let ((result
              (resolve-model-reference
               model-text models
               :provider provider-name
               :thinking-suffix :strict
               :fuzzy t
               :usable
               (if inline-api-key-p
                   (constantly nil)
                   (lambda (name)
                     (provider-has-configured-auth-p
                      registry name))))))
        (case (getf result :status)
          (:resolved
           (values (getf result :model)
                   nil
                   (getf result :thinking)
                   (getf result :warning)))
          (:ambiguous
           (values
            nil
            (format nil
                    "Model \"~A\" is ambiguous across providers: ~{~A~^, ~}. ~A Use --provider or provider/model."
                    model-text
                    (sort
                     (mapcar #'canonical-model-id
                             (getf result :candidates))
                     #'string<)
                    (cond
                      (inline-api-key-p
                       "--api-key does not choose a provider.")
                      ((zerop (getf result :usable-count))
                       "No matching provider is authenticated.")
                      (t
                       "More than one matching provider is authenticated.")))
            nil nil))
          (otherwise
           (let ((target (getf result :target)))
             (if (null target)
                 (values nil
                         (format nil
                                 "Model \"~A\" not found. Use --list-models to see available models."
                                 model-text)
                         nil nil)
                 (let* ((model-id
                          (if explicit-thinking
                              (getf target :model-text)
                              (getf target :model-id)))
                        (thinking
                          (unless explicit-thinking
                            (getf target :thinking)))
                        (requested
                          (or explicit-thinking thinking)))
                   (values
                    (custom-provider-model
                     (getf target :models)
                     model-id
                     (and requested
                          (not (eq requested :off))))
                    nil
                    thinking
                    (format nil
                            "Model \"~A\" not found for provider \"~A\". Using custom model id."
                            model-id
                            (getf target :provider))))))))))))
