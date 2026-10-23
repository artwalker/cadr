(in-package #:cadr-chord)

(defstruct method-spec args result)
(defstruct opaque-spec id)
(defstruct host-named name)
(defstruct host-family prefix key)

(defun host-named (name)
  (make-host-named :name name))

(defun host-family (prefix key)
  (make-host-family :prefix prefix :key key))

(defstruct contract
  name version scope input description fingerprint def)

(defparameter +reserved-members+
  '("variant" "status" "ready" "shape" "error" "onShape" "onStatus" "release" "then" "contract"))

(defun placement-object (placement)
  (etypecase placement
    (host-named (json-object "name" (host-named-name placement)))
    (host-family (json-object "prefix" (host-family-prefix placement)
                              "key" (host-family-key placement)))))

(defun describe-member (name member scope)
  (when (member name +reserved-members+ :test #'string=)
    (error "member name is reserved: ~A" name))
  (cond
    ((method-spec-p member)
     (let ((description (json-object "kind" "method")))
       (when (method-spec-args member)
         (json-put description "args" (method-spec-args member)))
       (when (method-spec-result member)
         (json-put description "result" (method-spec-result member)))
       description))
    ((opaque-spec-p member)
     (when (eq scope :remote)
       (error "remote contracts cannot expose opaque members: ~A" name))
     (json-object "kind" "opaque" "id" (opaque-spec-id member)))
    (t (json-object "kind" "state" "schema" member))))

(defun finish-contract (contract)
  (setf (contract-fingerprint contract)
        (hash64 (canonical-json (contract-description contract))))
  contract)

(defun check-contract-header (name version)
  (when (or (not (stringp name)) (zerop (length name)))
    (error "contract name is empty"))
  (unless (and (integerp version) (>= version 1))
    (error "contract version must be a positive integer")))

(defun remote-contract (name &key version input host variants)
  (check-contract-header name version)
  (unless (or (host-named-p host) (host-family-p host))
    (error "remote contract ~A needs a hostNamed or hostFamily placement" name))
  (when (zerop (hash-table-count variants))
    (error "remote contract ~A has no variants" name))
  (let ((described (json-object)))
    (dolist (kind (json-keys variants))
      (let* ((variant (gethash kind variants))
             (members (json-object)))
        (dolist (entry (gethash "state" variant))
          (json-put members (car entry) (describe-member (car entry) (cdr entry) :remote)))
        (dolist (entry (gethash "methods" variant))
          (when (nth-value 1 (gethash (car entry) members))
            (error "member ~A is both state and method" (car entry)))
          (let ((description (describe-member (car entry) (cdr entry) :remote)))
            (unless (string= (gethash "kind" description) "method")
              (error "methods.~A is not a method" (car entry)))
            (json-put members (car entry) description)))
        (json-put described kind members)))
    (finish-contract
     (make-contract :name name
                    :version version
                    :scope :remote
                    :input input
                    :def (json-object "version" version "input" input "host" host "variants" variants)
                    :description (json-object "name" name
                                              "scope" "remote"
                                              "version" version
                                              "input" input
                                              "host" (placement-object host)
                                              "variants" described)))))

(defun local-contract (name &key version input members)
  (check-contract-header name version)
  (let ((described (json-object)))
    (dolist (entry members)
      (json-put described (car entry) (describe-member (car entry) (cdr entry) :local)))
    (let ((variants (json-object "" described)))
      (finish-contract
       (make-contract :name name
                      :version version
                      :scope :local
                      :input input
                      :def (json-object "version" version "input" input "members" members)
                      :description (json-object "name" name
                                                "scope" "local"
                                                "version" version
                                                "input" input
                                                "variants" variants))))))

(defun contract-variant-members (description kind)
  (gethash kind (gethash "variants" description)))

(defun contract-coverage (provider consumer)
  (cond
    ((or (not (string= (gethash "name" provider) (gethash "name" consumer)))
         (not (string= (gethash "scope" provider) (gethash "scope" consumer))))
     "different type")
    ((not (string= (canonical-json (gethash "host" provider +json-null+))
                   (canonical-json (gethash "host" consumer +json-null+))))
     "host")
    ((not (schema-fits (gethash "input" consumer) (gethash "input" provider)))
     "input")
    (t
     (dolist (kind (json-keys (gethash "variants" consumer)))
       (let ((wanted-members (contract-variant-members consumer kind))
             (offered-members (contract-variant-members provider kind)))
         (unless offered-members
           (return-from contract-coverage (format nil "variant ~A missing" kind)))
         (dolist (name (json-keys wanted-members))
           (let ((wanted (gethash name wanted-members))
                 (offered (gethash name offered-members)))
             (unless (and offered (string= (gethash "kind" offered) (gethash "kind" wanted)))
               (return-from contract-coverage
                 (format nil "~A.~A missing or of another kind" kind name)))
             (cond
               ((string= (gethash "kind" offered) "method")
                (when (not (eq (nth-value 1 (gethash "args" wanted))
                               (nth-value 1 (gethash "args" offered))))
                  (return-from contract-coverage (format nil "~A.~A arguments" kind name)))
                (when (and (gethash "args" wanted)
                           (not (schema-fits (gethash "args" wanted) (gethash "args" offered))))
                  (return-from contract-coverage (format nil "~A.~A arguments" kind name)))
                (when (and (gethash "result" wanted)
                           (or (null (gethash "result" offered))
                               (not (schema-fits (gethash "result" offered) (gethash "result" wanted)))))
                  (return-from contract-coverage (format nil "~A.~A result" kind name))))
               ((string= (gethash "kind" offered) "state")
                (unless (schema-fits (gethash "schema" offered) (gethash "schema" wanted))
                  (return-from contract-coverage (format nil "~A.~A state" kind name))))
               ((and (string= (gethash "kind" offered) "opaque")
                     (not (string= (gethash "id" offered) (gethash "id" wanted))))
                (return-from contract-coverage
                  (format nil "~A.~A opaque ~A != ~A" kind name
                          (gethash "id" offered) (gethash "id" wanted))))))))))))

(defun contract-bind (provider accepts consumer)
  (cond
    ((string= (contract-fingerprint provider) (contract-fingerprint consumer))
     nil)
    ((not (string= (canonical-json (gethash "host" (contract-description provider) +json-null+))
                   (canonical-json (gethash "host" (contract-description consumer) +json-null+))))
     (signal-chord "contract_mismatch"
                   (format nil "~A lives on a different host than the consumer expects"
                           (contract-name provider))))
    ((= (contract-version provider) (contract-version consumer))
     (let ((reason (contract-coverage (contract-description provider)
                                      (contract-description consumer))))
       (if reason
           (signal-chord "contract_mismatch"
                         (format nil "~A@~A does not cover the consumer's description (~A); forgotten version bump?"
                                 (contract-name provider) (contract-version provider) reason))
           nil)))
    (t
     (let ((adapter (and accepts (gethash (contract-version consumer) accepts))))
       (unless adapter
         (signal-chord "contract_mismatch"
                       (format nil "~A: provider version ~A, consumer version ~A, no accepts adapter"
                               (contract-name provider)
                               (contract-version provider)
                               (contract-version consumer))))
       adapter))))

(defun resolve-host (type-name placement input)
  (etypecase placement
    (host-named (host-named-name placement))
    (host-family
     (let ((value (and (hash-table-p input) (gethash (host-family-key placement) input))))
       (unless (and (stringp value) (plusp (length value)))
         (invalid "placement"
                  (format nil "~A: input field ~A names no host"
                          type-name (host-family-key placement))))
       (concatenate 'string (host-family-prefix placement) value)))))

(defun variant-table (&rest pairs)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (name state methods) on pairs by #'cdddr
          do (setf (gethash name table)
                   (json-object "state" state "methods" methods)))
    table))

(defun member-alist (&rest pairs)
  (loop for (name member) on pairs by #'cddr collect (cons name member)))
