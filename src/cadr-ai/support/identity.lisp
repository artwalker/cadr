(in-package #:cadr-ai)

;;; pi@4a080252f packages/ai/src/utils/identity.ts
;;; Product strings stay cadr's: slug "cadr", referer the canonical
;;; repository, runtime "sbcl/<implementation>". The header map, merge,
;;; and precedence match the upstream functions.

(defvar *build-request-identity* nil)

(defvar *identity-deleted-header-names* nil)

(defun identity-field (identity key)
  (loop for (field value) on identity by #'cddr
        when (eq field key)
          return (values value t)
        finally (return (values nil nil))))

(defun client-attribution (name url &optional categories)
  (list :name name :url url :categories categories))

(defparameter +cadr-attribution+
  (client-attribution
   (cadr-product-slug)
   (cadr-canonical-repository-url)
   '("cli-agent")))

(defun client-identity
    (&key (user-agent nil user-agent-p)
       (attribution nil attribution-p)
       (version nil version-p))
  (let ((identity nil))
    (when user-agent-p
      (setf (getf identity :user-agent) user-agent))
    (when attribution-p
      (setf (getf identity :attribution)
            (if attribution attribution :off)))
    (when version-p
      (setf (getf identity :version) version))
    identity))

(defun merge-client-identity (&rest sources)
  (let ((merged nil)
        (saw-p nil))
    (dolist (source sources)
      (when source
        (setf saw-p t)
        (multiple-value-bind (value present-p)
            (identity-field source :user-agent)
          (when present-p
            (setf (getf merged :user-agent) value)))
        (multiple-value-bind (value present-p)
            (identity-field source :attribution)
          (when present-p
            (setf (getf merged :attribution) value)))
        (multiple-value-bind (value present-p)
            (identity-field source :version)
          (when present-p
            (setf (getf merged :version) value)))))
    (when saw-p merged)))

(defun client-version (identity)
  (multiple-value-bind (value present-p)
      (identity-field identity :version)
    (if present-p value (cadr-version))))

(defun user-agent-mode (identity)
  (multiple-value-bind (mode present-p)
      (identity-field identity :user-agent)
    (cond
      ((not present-p) :detailed)
      ((or (eq mode :short) (equal mode "short")) :short)
      ((or (eq mode :detailed) (equal mode "detailed")) :detailed)
      ((and (listp mode) (identity-field mode :custom))
       (identity-field mode :custom))
      ((stringp mode) mode)
      (t :detailed))))

(defun format-user-agent (&optional identity)
  (let ((mode (user-agent-mode identity)))
    (cond
      ((eq mode :short) (cadr-product-slug))
      ((stringp mode) mode)
      (t
       (format nil "~A/~A (~(~A~); sbcl/~A; ~(~A~))"
               (cadr-product-slug)
               (client-version identity)
               (software-type)
               (lisp-implementation-version)
               (machine-type))))))

(defun identity-provider-id (provider)
  (string-downcase
   (cond
     ((stringp provider) provider)
     ((symbolp provider) (symbol-name provider))
     (t ""))))

(defun identity-url-host (base-url)
  (when (stringp base-url)
    (handler-case
        (string-downcase
         (parsed-url-host (parse-http-url base-url)))
      (error () nil))))

(defun openrouter-target-p (provider base-url)
  (or (string= (identity-provider-id provider) "openrouter")
      (and (stringp base-url)
           (search "openrouter.ai" base-url))))

(defun nvidia-nim-target-p (provider base-url)
  (or (string= (identity-provider-id provider) "nvidia")
      (string= (identity-url-host base-url)
               "integrate.api.nvidia.com")))

(defun opencode-target-p (provider base-url)
  (or (member (identity-provider-id provider)
              '("opencode" "opencode-go")
              :test #'string=)
      (string= (identity-url-host base-url) "opencode.ai")))

(defun identity-attribution (identity)
  (multiple-value-bind (value present-p)
      (identity-field identity :attribution)
    (when (and present-p value (not (eq value :off)))
      value)))

(defun capitalize-invoke-origin (name)
  (if (or (not (stringp name)) (zerop (length name)))
      ""
      (concatenate 'string
                   (string (char-upcase (char name 0)))
                   (subseq name 1))))

(defun attribution-headers (provider base-url &optional identity)
  (let ((attribution (identity-attribution identity)))
    (unless attribution
      (return-from attribution-headers nil))
    (let ((name (or (getf attribution :name) ""))
          (url (or (getf attribution :url) ""))
          (categories (getf attribution :categories)))
      (cond
        ((openrouter-target-p provider base-url)
         (append
          `(("HTTP-Referer" . ,url)
            ("X-OpenRouter-Title" . ,name))
          (when categories
            (list
             (cons "X-OpenRouter-Categories"
                   (format nil "~{~A~^,~}" categories))))))
        ((nvidia-nim-target-p provider base-url)
         (list
          (cons "X-BILLING-INVOKE-ORIGIN"
                (capitalize-invoke-origin name))))
        ((opencode-target-p provider base-url)
         (list (cons "x-opencode-client" name)))
        (t nil)))))

(defun identity-header-list (provider base-url &optional identity)
  (acons "User-Agent"
         (format-user-agent identity)
         (attribution-headers provider base-url identity)))

(defun opencode-session-headers (provider base-url session-id)
  (when (and (non-empty-string-p session-id)
             (opencode-target-p provider base-url))
    (list (cons "x-opencode-session" session-id))))

(defun header-removal-p (value)
  (or (null value)
      (eq value :null)
      (json-null-p value)))

(defun delete-named-header (headers name)
  (remove name headers :key #'car :test #'string-equal))

(defun put-named-header (headers name value)
  (acons name value (delete-named-header headers name)))

(defun note-deleted-header (name)
  (when (consp *identity-deleted-header-names*)
    (pushnew name
             (car *identity-deleted-header-names*)
             :test #'string-equal)))

(defun apply-client-identity-headers
    (headers provider base-url identity &key caller-headers
                                          (overlay-caller-p t))
  ;; Identity is the lowest layer. Built headers already won over it.
  ;; A null caller value removes the name. Non-null caller values are
  ;; overlaid only when the provider did not already apply them; Codex
  ;; writes authorization and the account id last, so a second overlay
  ;; would unlock those credentials.
  (let ((merged
          (copy-tree
           (identity-header-list provider base-url identity))))
    (dolist (pair headers)
      (setf merged
            (put-named-header merged (car pair) (cdr pair))))
    (dolist (pair caller-headers)
      (let ((name (car pair))
            (value (cdr pair)))
        (cond
          ((header-removal-p value)
           (note-deleted-header name)
           (setf merged (delete-named-header merged name)))
          (overlay-caller-p
           (setf merged
                 (put-named-header merged name value))))))
    merged))

(defun strip-default-attribution (headers provider base-url identity)
  (let ((generated
          (attribution-headers provider base-url identity)))
    (remove-if
     (lambda (pair)
       (let ((generated-pair
               (assoc (car pair) generated :test #'string-equal)))
         (and generated-pair
              (equal (cdr generated-pair) (cdr pair)))))
     headers)))

(defun deleted-identity-header-p (name)
  (and (consp *identity-deleted-header-names*)
       (member name
               (car *identity-deleted-header-names*)
               :test #'string-equal)))

(defun restore-attribution-headers
    (headers provider base-url identity)
  (let ((clean nil))
    (dolist (pair headers)
      (if (header-removal-p (cdr pair))
          (note-deleted-header (car pair))
          (push pair clean)))
    (setf clean (nreverse clean))
    (dolist (pair (attribution-headers provider base-url identity))
      (unless (or (assoc (car pair) clean :test #'string-equal)
                  (deleted-identity-header-p (car pair)))
        (setf clean (acons (car pair) (cdr pair) clean))))
    clean))

(defun bedrock-identity-user-agent
    (&optional (identity *build-request-identity*))
  (let ((mode (user-agent-mode identity)))
    (cond
      ((eq mode :short) (cadr-product-slug))
      ((stringp mode) mode)
      (t
       (format nil "~A/~A"
               (cadr-product-slug)
               (client-version identity))))))
