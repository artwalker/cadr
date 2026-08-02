(define-rich-tool
 "parse_duration"
 :label "Parse Duration"
 :description
 "Parse a human-readable duration string (for example, 2 days, 1h, or 5m) to milliseconds"
 :parameters
 (cadr-ai::json-object
  "type" "object"
  "properties"
  (cadr-ai::json-object
   "duration"
   (cadr-ai::json-object
    "type" "string"
    "description" "Duration string like 2 days, 1h, or 5m"))
  "required" (vector "duration")
  "additionalProperties" nil)
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update context))
   (let* ((duration (gethash "duration" arguments))
          (milliseconds
            (cadr-example-duration:parse-duration-ms duration)))
     (unless milliseconds
       (error "Invalid duration: ~S" duration))
     (values
      (format nil "~A = ~D milliseconds" duration milliseconds)
      nil))))
