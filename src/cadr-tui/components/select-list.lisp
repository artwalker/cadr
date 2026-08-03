(in-package #:cadr-tui)

(defstruct select-item
  (label "" :type string)
  value
  description)

(defstruct (select-list
            (:constructor %make-select-list))
  (items nil :type list)
  (query "" :type string)
  (selected 0 :type (integer 0 *))
  (height 8 :type (integer 1 *))
  (show-filter-p t :type boolean)
  (min-primary-column-width 32
                            :type (integer 1 *))
  (max-primary-column-width 32
                            :type (integer 1 *))
  truncate-primary)

(defun make-select-list
    (&key items (height 5) (show-filter-p t)
       (min-primary-column-width 32)
       (max-primary-column-width 32)
       truncate-primary)
  (%make-select-list
   :items (copy-list items)
   :height height
   :show-filter-p show-filter-p
   :min-primary-column-width
   min-primary-column-width
   :max-primary-column-width
   max-primary-column-width
   :truncate-primary truncate-primary))

(defun select-list-filtered-items (list)
  (let ((query
          (string-downcase
           (select-list-query list))))
    (if (zerop (length query))
        (copy-list (select-list-items list))
        (remove-if-not
         (lambda (item)
           (let ((value
                   (select-item-value item)))
             (string-prefix-p
              query
              (string-downcase
               (cond
                 ((stringp value) value)
                 ((symbolp value)
                  (symbol-name value))
                 (t
                  (select-item-label item)))))))
         (select-list-items list)))))

(defun clamp-select-index (list)
  (let ((count
          (length
           (select-list-filtered-items list))))
    (setf (select-list-selected list)
          (if (zerop count)
              0
              (min (select-list-selected list)
                   (1- count))))))

(defun move-select-index (list delta)
  (let ((count
          (length
           (select-list-filtered-items list))))
    (setf (select-list-selected list)
          (if (zerop count)
              0
              (mod (+ (select-list-selected list)
                      delta)
                   count)))))

(defun select-list-handle-event (list event)
  (let ((kind (input-event-kind event)))
    (case kind
      (:text
       (setf
        (select-list-query list)
        (concatenate 'string
                     (select-list-query list)
                     (or (input-event-text event) ""))
        (select-list-selected list) 0))
      (:backspace
       (let ((query (select-list-query list)))
         (when (> (length query) 0)
           (setf
            (select-list-query list)
            (subseq
             query 0
             (previous-cluster-boundary
              query (length query)))
            (select-list-selected list) 0))))
      (:up
       (move-select-index list -1))
      (:down
       (move-select-index list 1))
      (:page-up
       (move-select-index
        list (- (select-list-height list))))
      (:page-down
       (move-select-index
        list (select-list-height list)))
      (:escape
       (return-from select-list-handle-event
         (values :cancel nil)))
      (:enter
       (clamp-select-index list)
       (let ((item
               (nth (select-list-selected list)
                    (select-list-filtered-items list))))
         (when item
           (return-from select-list-handle-event
             (values :select
                     (select-item-value item)))))))
    (values nil nil)))

(defun render-select-list
    (list width &key (ansi-theme-p nil))
  (let* ((items (select-list-filtered-items list))
         (count (length items))
         (selected
           (if (zerop count)
               0
               (min (select-list-selected list)
                    (1- count))))
         (height (select-list-height list))
         (start
           (max
            0
            (min
             (- selected
                (floor height 2))
             (- count height))))
         (end
           (min count (+ start height)))
         (minimum
           (min
            (select-list-min-primary-column-width
             list)
            (select-list-max-primary-column-width
             list)))
         (maximum
           (max
            (select-list-min-primary-column-width
             list)
            (select-list-max-primary-column-width
             list)))
         (widest
           (loop for item in items
                 maximize
                 (+ 2
                    (visible-width
                     (select-item-label item)))))
         (primary-width
           (max minimum
                (min maximum widest))))
    (labels
        ((normalize-description (description)
           (when description
             (string-trim
              '(#\Space #\Tab)
              (cl-ppcre:regex-replace-all
               "[\\r\\n]+" description " "))))
         (primary (item selected-p max-width)
           (let* ((label (select-item-label item))
                  (custom
                    (select-list-truncate-primary list))
                  (value
                    (if custom
                        (funcall
                         custom label max-width
                         primary-width item selected-p)
                        (truncate-to-width
                         label max-width ""))))
             (truncate-to-width value max-width "")))
         (render-item (item index)
           (let* ((selected-p (= index selected))
                  (prefix
                    (if selected-p "→ " "  "))
                  (prefix-width (visible-width prefix))
                  (description
                    (normalize-description
                     (select-item-description item))))
             (if (and description (> width 40))
                 (let* ((effective
                          (max
                           1
                           (min primary-width
                                (- width
                                   prefix-width 4))))
                        (maximum-primary
                          (max 1 (- effective 2)))
                        (label
                          (primary
                           item selected-p
                           maximum-primary))
                        (label-width
                          (visible-width label))
                        (spacing
                          (make-string
                           (max 1
                                (- effective label-width))
                           :initial-element #\Space))
                        (remaining
                          (- width prefix-width
                             label-width
                             (length spacing) 2)))
                   (if (> remaining 10)
                       (let ((line
                               (concatenate
                                'string
                                prefix label spacing
                                (truncate-to-width
                                 description
                                 remaining ""))))
                         (if selected-p
                             (theme-foreground
                              :accent line
                              :enabled-p
                              ansi-theme-p)
                             (concatenate
                              'string
                              prefix label
                              (theme-foreground
                               :muted
                               (concatenate
                                'string spacing
                                (truncate-to-width
                                 description
                                 remaining ""))
                               :enabled-p
                               ansi-theme-p))))
                       (let ((line
                               (concatenate
                                'string prefix
                                (primary
                                 item selected-p
                                 (- width
                                    prefix-width
                                    2)))))
                         (if selected-p
                             (theme-foreground
                              :accent line
                              :enabled-p
                              ansi-theme-p)
                             line))))
                 (concatenate
                  'string
                  (if selected-p
                      (theme-foreground
                       :accent
                       (concatenate
                        'string prefix
                        (primary
                         item selected-p
                         (max
                          1
                          (- width
                             prefix-width 2))))
                       :enabled-p ansi-theme-p)
                      (concatenate
                       'string prefix
                       (primary
                        item selected-p
                        (max
                         1
                         (- width
                            prefix-width 2))))))))))
      (nconc
       (when (select-list-show-filter-p list)
         (list
          (theme-foreground
           :muted
           (fit-status
            (format nil "filter: ~A"
                    (select-list-query list))
            width)
           :enabled-p ansi-theme-p)))
       (if (zerop count)
           (list
            (theme-foreground
             :muted "  No matching commands"
             :enabled-p ansi-theme-p))
           (nconc
            (loop for item in
                  (subseq items start end)
                  for index from start
                  collect
                  (render-item item index))
            (when
                (or (plusp start)
                    (< end count))
              (list
               (theme-foreground
                :muted
                (truncate-to-width
                 (format nil "  (~D/~D)"
                         (1+ selected)
                         count)
                 (max 1 (- width 2))
                 "")
                :enabled-p
                ansi-theme-p)))))))))
