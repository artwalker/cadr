(load (merge-pathnames "support.lisp" *load-truename*))

(defun example-provider-log-path (context)
  (merge-pathnames
   ".cadr/provider-payload.log"
   (cadr-agent:extension-context-cwd context)))

(defun example-append-provider-log (context text)
  (let ((path (example-provider-log-path context)))
    (ensure-directories-exist path)
    (with-open-file (stream path :direction :output
                                 :if-exists :append
                                 :if-does-not-exist :create
                                 :external-format :utf-8)
      (format stream "~A~%~%" text))))

(defun example-write-pretty-json (value stream depth)
  (labels ((indent (level)
             (write-string (make-string (* 2 level)
                                        :initial-element #\Space)
                           stream)))
    (cond
      ((hash-table-p value)
       (let ((keys
               (sort
                (loop for key being the hash-keys of value collect key)
                #'string<)))
         (if (null keys)
             (write-string "{}" stream)
             (progn
               (write-char #\{ stream)
               (terpri stream)
               (loop for key in keys
                     for first-p = t then nil
                     do
                     (unless first-p
                       (write-char #\, stream)
                       (terpri stream))
                     (indent (1+ depth))
                     (cadr-ai::write-json-string key stream)
                     (write-string ": " stream)
                     (example-write-pretty-json
                      (gethash key value) stream (1+ depth)))
               (terpri stream)
               (indent depth)
               (write-char #\} stream)))))
      ((and (or (vectorp value) (listp value)) value)
       (let ((items (coerce value 'vector)))
         (write-char #\[ stream)
         (when (plusp (length items))
           (terpri stream)
           (loop for item across items
                 for first-p = t then nil
                 do
                 (unless first-p
                   (write-char #\, stream)
                   (terpri stream))
                 (indent (1+ depth))
                 (example-write-pretty-json item stream (1+ depth)))
           (terpri stream)
           (indent depth))
         (write-char #\] stream)))
      (t (cadr-ai::write-json-value value stream)))))

(defun example-pretty-json (value)
  (with-output-to-string (stream)
    (example-write-pretty-json value stream 0)))

(cadr-agent:define-event-hook
 :before-provider-request
 :handler
 (lambda (event context)
   (let ((payload (example-event-value event :payload)))
     (example-append-provider-log
      context (example-pretty-json payload))
     nil)))

(cadr-agent:define-event-hook
 :after-provider-response
 :handler
 (lambda (event context)
   (example-append-provider-log
    context
    (format nil "[~A] ~A"
            (example-event-value event :status)
            (cadr-ai::stringify-json
             (example-event-value event :headers))))))
