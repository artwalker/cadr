(in-package #:cadr-cli)

(defstruct replacement
  start
  end
  old
  new)

(defun normalize-line-endings (text)
  (cadr-ai::replace-all
   (cadr-ai::replace-all
    text (format nil "~C~C" #\Return #\Newline)
    (string #\Newline))
   (string #\Return)
   (string #\Newline)))

(defun detect-line-ending (text)
  (if (search (format nil "~C~C" #\Return #\Newline) text)
      :crlf
      :lf))

(defun restore-line-endings (text ending)
  (if (eq ending :crlf)
      (cadr-ai::replace-all
       text (string #\Newline)
       (format nil "~C~C" #\Return #\Newline))
      text))

(defun strip-utf8-bom (text)
  (if (and (plusp (length text))
           (= #xfeff (char-code (char text 0))))
      (values (string (char text 0)) (subseq text 1))
      (values "" text)))

(defun normalize-edit-array (value)
  (if (stringp value)
      (handler-case
          (let ((parsed (cadr-ai::parse-json value)))
            (if (typep parsed 'simple-vector)
                parsed
                value))
        (error () value))
      value))

(defun prepare-edit-arguments (arguments)
  (unless (hash-table-p arguments)
    (return-from prepare-edit-arguments arguments))
  (let* ((prepared (cadr-ai::copy-json-value arguments))
         (edits
           (normalize-edit-array
            (cadr-ai::json-get prepared "edits")))
         (legacy-old (cadr-ai::json-get prepared "oldText"))
         (legacy-new (cadr-ai::json-get prepared "newText")))
    (when (and (stringp legacy-old)
               (stringp legacy-new))
      (let ((legacy
              (cadr-ai::json-object
               "oldText" legacy-old
               "newText" legacy-new)))
        (setf edits
              (if (vectorp edits)
                  (concatenate 'vector edits (vector legacy))
                  (vector legacy)))))
    (when edits
      (cadr-ai::json-put prepared "edits" edits))
    (remhash "oldText" prepared)
    (remhash "newText" prepared)
    prepared))

(defun all-occurrences (needle haystack)
  (when (zerop (length needle))
    (error "oldText must not be empty"))
  (loop with start = 0
        for position = (search needle haystack :start2 start)
        while position
        collect position
        do (setf start (1+ position))))

(defun fuzzy-space-p (character)
  (or (member character '(#\Space #\Tab))
      (unicode-space-p character)))

(defun fuzzy-character (character)
  (let ((code (char-code character)))
    (cond
      ((<= #xff01 code #xff5e)
       (code-char (- code #xfee0)))
      ((member code '(#x2018 #x2019 #x201a #x201b))
       #\')
      ((member code '(#x201c #x201d #x201e #x201f))
       #\")
      ((member code
               '(#x2010 #x2011 #x2012 #x2013
                 #x2014 #x2015 #x2212))
       #\-)
      ((unicode-space-p character) #\Space)
      (t character))))

(defun composed-acute-character (character)
  (case character
    (#\a (code-char #xe1))
    (#\A (code-char #xc1))
    (#\e (code-char #xe9))
    (#\E (code-char #xc9))
    (#\i (code-char #xed))
    (#\I (code-char #xcd))
    (#\o (code-char #xf3))
    (#\O (code-char #xd3))
    (#\u (code-char #xfa))
    (#\U (code-char #xda))
    (otherwise nil)))

(defun fuzzy-normalize-with-map (text)
  (let ((characters
          (make-array
           0 :element-type 'character
           :adjustable t :fill-pointer 0))
        (starts
          (make-array
           0 :element-type 'fixnum
           :adjustable t :fill-pointer 0))
        (ends
          (make-array
           0 :element-type 'fixnum
           :adjustable t :fill-pointer 0)))
    (labels ((append-character (character start end)
               (vector-push-extend character characters)
               (vector-push-extend start starts)
               (vector-push-extend end ends))
             (trim-line-end ()
               (loop while
                     (and
                      (plusp (fill-pointer characters))
                      (fuzzy-space-p
                       (aref characters
                             (1- (fill-pointer characters)))))
                     do
                     (decf (fill-pointer characters))
                     (decf (fill-pointer starts))
                     (decf (fill-pointer ends)))))
      (loop for character across text
            for index from 0
            do
            (cond
              ((char= character #\Newline)
               (trim-line-end)
               (append-character character index (1+ index)))
              ((and (= (char-code character) #x301)
                    (plusp (fill-pointer characters)))
               (let* ((position
                        (1- (fill-pointer characters)))
                      (composed
                        (composed-acute-character
                         (aref characters position))))
                 (if composed
                     (setf (aref characters position) composed
                           (aref ends position) (1+ index))
                     (append-character
                      character index (1+ index)))))
              (t
               (append-character
                (fuzzy-character character)
                index (1+ index)))))
      (trim-line-end))
    (values
     (coerce characters 'string)
     starts
     ends)))

(defun fuzzy-normalize (text)
  (nth-value 0
             (fuzzy-normalize-with-map text)))

(defun fuzzy-match-range (old original)
  (let* ((exact-positions
           (all-occurrences old original))
         (fuzzy-old (fuzzy-normalize old)))
    (when (zerop (length fuzzy-old))
      (error "oldText must not be empty"))
    (multiple-value-bind
          (fuzzy-original starts ends)
        (fuzzy-normalize-with-map original)
      (let ((fuzzy-positions
              (all-occurrences
               fuzzy-old fuzzy-original)))
        (cond
          ((null fuzzy-positions)
           (error "oldText was not found: ~S" old))
          ((cdr fuzzy-positions)
           (error "oldText is not unique: ~S" old))
          ((and exact-positions
                (null (cdr exact-positions)))
           (values
            (first exact-positions)
            (+ (first exact-positions)
               (length old))))
          (t
           (let* ((position (first fuzzy-positions))
                  (last
                    (+ position
                       (length fuzzy-old)
                       -1)))
             (values
              (aref starts position)
              (aref ends last)))))))))

(defun parse-replacements (arguments original)
  (let ((edits (cadr-ai::json-get arguments "edits")))
    (unless (and (vectorp edits) (plusp (length edits)))
      (error "edits must contain at least one replacement"))
    (let ((replacements nil))
      (loop for edit across edits
            for old = (required-string edit "oldText")
            for new = (required-string edit "newText")
            do
            (multiple-value-bind (start end)
                (fuzzy-match-range
                 (normalize-line-endings old)
                 original)
               (push
                (make-replacement
                 :start start
                 :end end
                 :old old
                 :new (normalize-line-endings new))
                replacements)))
      (setf replacements
            (sort replacements #'< :key #'replacement-start))
      (loop for previous = nil then replacement
            for replacement in replacements
            when (and previous
                      (< (replacement-start replacement)
                         (replacement-end previous)))
              do (error "Edits overlap in the original file"))
      replacements)))

(defun apply-replacements (original replacements)
  (with-output-to-string (output)
    (loop with cursor = 0
          for replacement in replacements
          do (write-string
              original output
              :start cursor
              :end (replacement-start replacement))
             (write-string (replacement-new replacement) output)
             (setf cursor (replacement-end replacement))
          finally (write-string original output :start cursor))))

(defun make-edit-tool (cwd)
  (cadr-ai:make-tool
   :name "edit"
   :description
   "Apply one or more unique, non-overlapping exact replacements."
   :parameters
   (object-schema
    (cadr-ai::json-object
     "path" (string-property)
     "edits"
     (cadr-ai::json-object
      "type" "array"
      "minItems" 1
      "items"
      (object-schema
       (cadr-ai::json-object
        "oldText" (string-property)
        "newText" (string-property))
       '("oldText" "newText"))))
    '("path" "edits"))
   :execution-mode :sequential
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (let* ((arguments (prepare-edit-arguments arguments))
            (path
              (resolve-tool-path
               cwd (required-string arguments "path")))
            (replacement-count 0))
       (with-file-mutation-queue
        path
        (lambda ()
          (let* ((raw
                   (uiop:read-file-string
                    path :external-format :utf-8))
                 (ending (detect-line-ending raw)))
            (multiple-value-bind (bom body)
                (strip-utf8-bom raw)
              (let* ((original
                       (normalize-line-endings body))
                     (replacements
                       (parse-replacements arguments original))
                     (updated
                       (apply-replacements original replacements)))
                (setf replacement-count
                      (length replacements))
                (atomic-write-utf8
                 path
                 (concatenate
                  'string bom
                  (restore-line-endings
                   updated ending))))))))
       (values
        (list
         (cadr-ai:make-text-content
          :text
          (format nil "Applied ~D replacement~:P to ~A"
                  replacement-count
                  (namestring path))))
        (list :path (namestring path)
              :replacements replacement-count))))))
