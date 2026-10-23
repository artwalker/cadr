(in-package #:cadr-durable)

(defstruct (codemode-sandbox (:constructor %make-codemode-sandbox))
  (fingerprint "sandbox")
  (closed nil))

(defun make-codemode-sandbox (&key (fingerprint "sandbox"))
  (%make-codemode-sandbox :fingerprint fingerprint))

(defstruct journal-entry seq kind name args result id issued-after)

(defparameter *codemode-store*
  (define-doc "codemode.store" :scope "conversation" :history "rewindable"
              :fork "asOf"))

(defun describe-call (kind name args)
  (let ((encoded (cadr-chord:canonical-json (or args (cadr-chord:json-object)))))
    (if (eq kind :tool)
        (format nil "tools.~A(~A)" name encoded)
        (format nil "~A(~A)" name encoded))))

(defun same-call-p (entry step)
  (and (eq (journal-entry-kind entry) (getf step :kind))
       (string= (journal-entry-name entry) (getf step :name))
       (string= (cadr-chord:canonical-json (or (journal-entry-args entry) (cadr-chord:json-object)))
                (cadr-chord:canonical-json (or (getf step :args) (cadr-chord:json-object))))))

(defun replay-mismatch (entry step)
  (error "The script took a different path when resumed after a restart: call ~A is ~A, but was ~A"
         (journal-entry-seq entry)
         (describe-call (getf step :kind) (getf step :name) (getf step :args))
         (if (eq (journal-entry-kind entry) :tool)
             "a tool call"
             (format nil "a call to ~A" (journal-entry-name entry)))))

(defun codemode-check-acks (journal acks &key first-issued)
  (let ((replaying (plusp (length journal))))
    (dolist (ack acks)
      (let ((seq (car ack))
            (issued (cdr ack)))
        (when (<= seq (length journal))
          (let ((recorded (if (zerop seq)
                              first-issued
                              (journal-entry-issued-after (aref journal (1- seq))))))
            (when (and recorded (/= recorded issued))
              (error "The script took a different path when resumed after a restart: ~A"
                     (if (zerop seq)
                         (format nil "its first run made ~A calls, where it had made ~A"
                                 issued recorded)
                         (format nil "after result ~A it had made ~A calls, where it had made ~A"
                                 seq issued recorded))))))
        (when (and replaying (< seq (length journal)))
          (let ((next-id (journal-entry-id (aref journal seq))))
            (when (and next-id (> next-id issued))
              (error "The script took a different path when resumed after a restart: it waits without making call ~A, which it made before"
                     next-id))))))))

(defun codemode-run (sandbox steps &key journal invoke before-deliver recorded-fingerprint
                                      acks first-issued)
  (when (codemode-sandbox-closed sandbox)
    (error "The code mode sandbox was closed while the script ran"))
  (when (and journal recorded-fingerprint
             (not (string= recorded-fingerprint (codemode-sandbox-fingerprint sandbox))))
    (error "The script cannot resume: the sandbox changed since it started (~A -> ~A)."
           recorded-fingerprint (codemode-sandbox-fingerprint sandbox)))
  (let ((log (coerce (or journal #()) 'vector))
        (delivered nil))
    (loop for step in steps
          for index from 0
          do (let ((entry (when (< index (length log)) (aref log index))))
               (cond
                 (entry
                  (unless (same-call-p entry step)
                    (replay-mismatch entry step))
                  (when (eq (journal-entry-kind entry) :tool)
                    (note-durable-replay (journal-entry-name entry)))
                  (push (journal-entry-result entry) delivered))
                 (t
                  (let* ((seq (1+ index))
                         (result (funcall invoke step))
                         (recorded (make-journal-entry
                                    :seq seq :kind (getf step :kind) :name (getf step :name)
                                    :args (getf step :args) :result result)))
                    (setf log (concatenate 'vector log (vector recorded)))
                    (when before-deliver
                      (funcall before-deliver (coerce log 'list))
                      (setf before-deliver nil))
                    (push result delivered))))))
    (codemode-check-acks log acks :first-issued first-issued)
    (when (< (length steps) (length log))
      (error "The script took a different path when resumed after a restart: it ended after result ~A, where it went on before."
             (length steps)))
    (values (nreverse delivered) (coerce log 'list))))

(defun codemode-store (session conversation-id key value)
  (session-commit session
                  (lambda (tx)
                    (doc-set (tx-doc tx *codemode-store* conversation-id) key value)))
  value)

(defun codemode-load (session conversation-id key)
  (let ((snapshot (session-snapshot session *codemode-store* conversation-id)))
    (when snapshot (cadr-chord:json-get snapshot key cadr-chord:+json-absent+))))
