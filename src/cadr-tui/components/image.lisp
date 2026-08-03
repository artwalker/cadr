(in-package #:cadr-tui)

(defun render-image-component
    (base64-data mime-type width
     &key dimensions filename image-id
       max-width-cells max-height-cells
       (capabilities
         (get-terminal-capabilities)))
  (let* ((image-width (or (first dimensions) 800))
         (image-height (or (second dimensions) 600))
         (maximum-width
           (max 1
                (min (- width 2)
                     (or max-width-cells 60)))))
    (if (terminal-capabilities-images capabilities)
        (let ((result
                (render-terminal-image
                 base64-data image-width image-height
                 :capabilities capabilities
                 :max-width-cells maximum-width
                 :max-height-cells max-height-cells
                 :image-id image-id
                 :move-cursor-p nil)))
          (if result
              (cons
               (image-render-result-sequence result)
               (make-list
                (1- (image-render-result-rows result))
                :initial-element ""))
              (list
               (truncate-to-width
                (image-fallback
                 mime-type :width image-width
                 :height image-height
                 :filename filename
                 :capabilities capabilities)
                width))))
        (list
         (truncate-to-width
          (image-fallback
           mime-type :width image-width
           :height image-height
           :filename filename
           :capabilities capabilities)
          width)))))
