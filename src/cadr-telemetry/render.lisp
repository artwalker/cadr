(in-package #:cadr-telemetry)

(defun format-attributes (attributes)
  (with-output-to-string (output)
    (dolist (pair attributes)
      (format output " ~A=~A"
              (car pair)
              (json-attribute-value (cdr pair))))))

(defun render-span-error (status)
  (if (eq :error (telemetry-status-kind status))
      (if (telemetry-status-error-p status)
          (format nil " error ~A: ~A"
                  (telemetry-status-error-name status)
                  (telemetry-status-error-message status))
          " error")
      ""))

(defun dedup-stored-spans (spans)
  (let ((order nil)
        (by-id (make-hash-table :test #'equal)))
    (dolist (span spans)
      (let ((id (stored-span-id span)))
        (unless (gethash id by-id)
          (setf order (append order (list id))))
        (setf (gethash id by-id) span)))
    (mapcar (lambda (id) (gethash id by-id)) order)))

(defun render-trace (spans)
  (let* ((unique (dedup-stored-spans spans))
         (ordered
           (stable-sort
            (copy-list unique)
            (lambda (left right)
              (< (stored-span-started-ms left)
                 (stored-span-started-ms right)))))
         (by-id (make-hash-table :test #'equal))
         (children (make-hash-table :test #'equal))
         (roots nil))
    (dolist (span ordered)
      (setf (gethash (stored-span-id span) by-id) span))
    (dolist (span ordered)
      (let ((parent (stored-span-parent-id span)))
        (if (or (null parent) (not (gethash parent by-id)))
            (setf roots (append roots (list span)))
            (setf (gethash parent children)
                  (append (gethash parent children) (list span))))))
    (let ((lines nil)
          (pending (mapcar (lambda (span) (cons span 0)) roots)))
      (loop while pending
            do (let* ((item (pop pending))
                      (span (car item))
                      (depth (cdr item))
                      (indent (make-string (* depth 2) :initial-element #\Space)))
                 (push (format nil "~A~A~A (~Ams)~A"
                               indent
                               (stored-span-name span)
                               (format-attributes (stored-span-attributes span))
                               (js-number-text
                                (- (stored-span-ended-ms span)
                                   (stored-span-started-ms span)))
                               (render-span-error (stored-span-status span)))
                       lines)
                 (dolist (event (stored-span-events span))
                   (push (format nil "~A  · ~A~A (+~Ams)"
                                 indent
                                 (stored-event-name event)
                                 (format-attributes (stored-event-attributes event))
                                 (js-number-text (stored-event-time-ms event)))
                         lines))
                 (dolist (link (stored-span-links span))
                   (push (format nil "~A  → link trace ~A span ~A~A"
                                 indent
                                 (stored-link-trace-id link)
                                 (stored-link-span-id link)
                                 (format-attributes (stored-link-attributes link)))
                         lines))
                 (let ((descendants (gethash (stored-span-id span) children)))
                   (loop for index from (1- (length descendants)) downto 0
                         do (push (cons (nth index descendants) (1+ depth))
                                  pending)))))
      (if lines
          (format nil "~{~A~^~%~}" (nreverse lines))
          ""))))
