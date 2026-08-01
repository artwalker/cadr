(in-package #:cadr-cli)

(defstruct replacement
  index
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

(defun edit-old-text-empty-error (path index total)
  (if (= total 1)
      (error "oldText must not be empty in ~A." path)
      (error "edits[~D].oldText must not be empty in ~A."
             index path)))

(defun edit-not-found-error (path index total)
  (if (= total 1)
      (error
       "Could not find the exact text in ~A. The old text must match exactly including all whitespace and newlines."
       path)
      (error
       "Could not find edits[~D] in ~A. The oldText must match exactly including all whitespace and newlines."
       index path)))

(defun edit-duplicate-error (path index total occurrences)
  (if (= total 1)
      (error
       "Found ~D occurrences of the text in ~A. The text must be unique. Please provide more context to make it unique."
       occurrences path)
      (error
       "Found ~D occurrences of edits[~D] in ~A. Each oldText must be unique. Please provide more context to make it unique."
       occurrences index path)))

(defun fuzzy-match-range (old original path index total)
  (when (zerop (length old))
    (edit-old-text-empty-error path index total))
  (let* ((exact-positions
           (all-occurrences old original))
         (fuzzy-old (fuzzy-normalize old)))
    (when (zerop (length fuzzy-old))
      (edit-old-text-empty-error path index total))
    (multiple-value-bind
          (fuzzy-original starts ends)
        (fuzzy-normalize-with-map original)
      (let ((fuzzy-positions
              (all-occurrences
               fuzzy-old fuzzy-original)))
        (cond
          ((null fuzzy-positions)
           (edit-not-found-error path index total))
          ((cdr fuzzy-positions)
           (edit-duplicate-error
            path index total (length fuzzy-positions)))
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

(defun parse-replacements (arguments original path)
  (let ((edits (cadr-ai::json-get arguments "edits")))
    (unless (and (vectorp edits) (plusp (length edits)))
      (error
       "Edit tool input is invalid. edits must contain at least one replacement."))
    (let ((replacements nil))
      (loop for edit across edits
            for index from 0
            for old = (required-string edit "oldText")
            for new = (required-string edit "newText")
            do
            (multiple-value-bind (start end)
                (fuzzy-match-range
                 (normalize-line-endings old)
                 original path index (length edits))
               (push
                (make-replacement
                 :index index
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
              do
              (error
               "edits[~D] and edits[~D] overlap in ~A. Merge them into one edit or target disjoint regions."
               (replacement-index previous)
               (replacement-index replacement)
               path))
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

(defstruct edit-diff-range
  old-start
  old-end
  new-start
  new-end)

(defun edit-line-start-offsets (text)
  (let ((starts nil))
    (when (plusp (length text))
      (push 0 starts)
      (loop for index below (1- (length text))
            when (char= (char text index) #\Newline)
              do (push (1+ index) starts)))
    (coerce (nreverse starts) 'vector)))

(defun edit-line-index-at-offset (starts offset)
  (when (zerop (length starts))
    (return-from edit-line-index-at-offset 0))
  (let ((low 0)
        (high (1- (length starts)))
        (found 0))
    (loop while (<= low high)
          for middle = (floor (+ low high) 2)
          if (<= (aref starts middle) offset)
            do (setf found middle
                     low (1+ middle))
          else
            do (setf high (1- middle)))
    found))

(defun replacement-covers-whole-lines-p
    (replacement original starts old-start old-end)
  (and
   (= (replacement-start replacement)
      (aref starts old-start))
   (= (replacement-end replacement)
      (if (< (1+ old-end) (length starts))
          (aref starts (1+ old-end))
          (length original)))))

(defun replacement-diff-ranges
    (original updated replacements)
  (let ((old-starts
          (edit-line-start-offsets original))
        (new-starts
          (edit-line-start-offsets updated))
        (offset-delta 0)
        (ranges nil))
    (dolist (replacement replacements)
      (let* ((old-start
               (edit-line-index-at-offset
                old-starts
                (replacement-start replacement)))
             (old-end
               (edit-line-index-at-offset
                old-starts
                (max
                 (replacement-start replacement)
                 (1- (replacement-end replacement)))))
             (new-offset
               (+ (replacement-start replacement)
                  offset-delta))
             (new-length
               (length (replacement-new replacement)))
             (whole-lines-p
               (replacement-covers-whole-lines-p
                replacement original old-starts
                old-start old-end))
             (new-start
               (if (and (zerop new-length)
                        whole-lines-p
                        (= new-offset (length updated)))
                   (length new-starts)
                   (edit-line-index-at-offset
                    new-starts new-offset)))
             (new-end
               (cond
                 ((plusp new-length)
                  (edit-line-index-at-offset
                   new-starts
                   (+ new-offset new-length -1)))
                 ((or
                   (zerop (length new-starts))
                   whole-lines-p)
                  (1- new-start))
                 (t new-start))))
        (push
         (make-edit-diff-range
          :old-start old-start
          :old-end old-end
          :new-start new-start
          :new-end new-end)
         ranges)
        (incf
         offset-delta
         (- new-length
            (- (replacement-end replacement)
               (replacement-start replacement))))))
    (nreverse ranges)))

(defun group-edit-diff-ranges (ranges)
  (let ((groups nil))
    (dolist (range ranges)
      (let ((current (car groups)))
        (if
            (and
             current
             (<= (edit-diff-range-old-start range)
                 (+ (edit-diff-range-old-end current) 9)))
            (setf
             (edit-diff-range-old-end current)
             (max
              (edit-diff-range-old-end current)
              (edit-diff-range-old-end range))
             (edit-diff-range-new-end current)
             (max
              (edit-diff-range-new-end current)
              (edit-diff-range-new-end range)))
            (push (copy-edit-diff-range range)
                  groups))))
    (nreverse groups)))

(defun format-edit-diff-line
    (marker number width text)
  (format nil "~C~vD ~A"
          marker width number text))

(defun generate-edit-display-diff
    (original updated replacements)
  (let* ((old-lines
           (coerce (text-lines original) 'vector))
         (new-lines
           (coerce (text-lines updated) 'vector))
         (groups
           (group-edit-diff-ranges
            (replacement-diff-ranges
             original updated replacements)))
         (width
           (length
            (write-to-string
             (max 1
                  (length old-lines)
                  (length new-lines)))))
         (output nil))
    (loop for group in groups
          for group-index from 0
          for old-start =
            (edit-diff-range-old-start group)
          for old-end =
            (edit-diff-range-old-end group)
          for new-start =
            (edit-diff-range-new-start group)
          for new-end =
            (edit-diff-range-new-end group)
          for before = (max 0 (- old-start 4))
          for after =
            (min (length old-lines)
                 (+ old-end 5))
          do
          (when (plusp group-index)
            (push
             (format nil " ~vA ..." width "")
             output))
          (loop for index from before below old-start
                do
                (push
                 (format-edit-diff-line
                  #\Space (1+ index) width
                  (aref old-lines index))
                 output))
          (loop for index from old-start to old-end
                when (< index (length old-lines))
                  do
                  (push
                   (format-edit-diff-line
                    #\- (1+ index) width
                    (aref old-lines index))
                   output))
          (loop for index from new-start to new-end
                when (and (>= index 0)
                          (< index (length new-lines)))
                  do
                  (push
                   (format-edit-diff-line
                    #\+ (1+ index) width
                    (aref new-lines index))
                   output))
          (loop for index from (1+ old-end) below after
                do
                (push
                 (format-edit-diff-line
                  #\Space (1+ index) width
                  (aref old-lines index))
                 output)))
    (values
     (join-lines (nreverse output))
     (and groups
          (1+
           (max 0
                (edit-diff-range-new-start
                 (first groups)))))
     groups)))

(defun generate-edit-unified-patch
    (path original updated groups)
  (let ((old-lines
          (coerce (text-lines original) 'vector))
        (new-lines
          (coerce (text-lines updated) 'vector)))
    (with-output-to-string (stream)
      (format stream "--- ~A~%+++ ~A" path path)
      (dolist (group groups)
        (let* ((old-start
                 (edit-diff-range-old-start group))
               (old-end
                 (edit-diff-range-old-end group))
               (new-start
                 (edit-diff-range-new-start group))
               (new-end
                 (edit-diff-range-new-end group))
               (before-count (min 4 old-start))
               (after-count
                 (min 4
                      (max 0
                           (- (length old-lines)
                              old-end 1))))
               (old-hunk-start (- old-start before-count))
               (new-hunk-start
                 (max 0 (- new-start before-count)))
               (old-count
                 (+ before-count
                    (1+ (- old-end old-start))
                    after-count))
               (new-change-count
                 (max 0 (1+ (- new-end new-start))))
               (new-count
                 (+ before-count new-change-count
                    after-count)))
          (format
           stream
           "~%@@ -~D,~D +~D,~D @@"
           (1+ old-hunk-start) old-count
           (1+ new-hunk-start) new-count)
          (loop for index from old-hunk-start below old-start
                do (format stream "~% ~A"
                           (aref old-lines index)))
          (loop for index from old-start to old-end
                when (< index (length old-lines))
                  do (format stream "~%-~A"
                             (aref old-lines index)))
          (loop for index from new-start to new-end
                when (and (>= index 0)
                          (< index (length new-lines)))
                  do (format stream "~%+~A"
                             (aref new-lines index)))
          (loop for index from (1+ old-end)
                  below (+ (1+ old-end) after-count)
                do (format stream "~% ~A"
                           (aref old-lines index))))))))

(defun make-edit-tool (cwd &key context)
  (cadr-ai:make-tool
   :name "edit"
   :description
   "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes."
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
            (display-path
              (required-string arguments "path"))
            (path
              (if context
                  (resolve-execution-context-path context cwd display-path)
                  (resolve-tool-path cwd display-path)))
            (replacement-count 0)
            (display-diff nil)
            (patch nil)
            (first-changed-line nil))
       (unless (or context (probe-file path))
         (error "Could not edit file: ~A. Error code: ENOENT."
                display-path))
       (with-file-mutation-queue
        path
        (lambda ()
          (let* ((raw
                   (if context
                       (multiple-value-bind (value operation-error)
                           (cadr-agent:execution-tool-read-text context path)
                         (execution-context-value value operation-error))
                       (uiop:read-file-string path :external-format :utf-8)))
                 (ending (detect-line-ending raw)))
            (multiple-value-bind (bom body)
                (strip-utf8-bom raw)
              (let* ((original
                       (normalize-line-endings body))
                     (replacements
                       (parse-replacements
                        arguments original display-path))
                     (updated
                       (apply-replacements original replacements)))
                (setf replacement-count
                      (length replacements))
                (when (string= original updated)
                  (if (= replacement-count 1)
                      (error
                       "No changes made to ~A. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected."
                       display-path)
                      (error
                       "No changes made to ~A. The replacements produced identical content."
                       display-path)))
                (multiple-value-bind
                      (diff first-line groups)
                    (generate-edit-display-diff
                     original updated replacements)
                  (setf
                   display-diff diff
                   first-changed-line first-line
                   patch
                   (generate-edit-unified-patch
                    display-path original updated groups)))
                (let ((final-content
                        (concatenate
                         'string bom
                         (restore-line-endings updated ending))))
                  (if context
                      (multiple-value-bind (value operation-error)
                          (cadr-agent:execution-tool-write
                           context path final-content)
                        (execution-context-value value operation-error))
                      (atomic-write-utf8 path final-content))))))))
       (values
        (list
         (cadr-ai:make-text-content
          :text
          (format nil "Successfully replaced ~D block(s) in ~A."
                  replacement-count
                  display-path)))
        (list :diff display-diff
              :patch patch
              :first-changed-line
              first-changed-line))))))
