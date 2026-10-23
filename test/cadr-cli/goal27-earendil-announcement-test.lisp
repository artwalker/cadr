(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defparameter +clankolas-sha256+
  "169acd0dfe6fbb8d8742ed24a3fc654fd0b2e2d4223c733249c5493723f1b72d")

(defun clankolas-bytes ()
  (let ((path
          (asdf:system-relative-pathname
           "cadr-cli" "assets/interactive/clankolas.png")))
    (with-open-file (stream path
                            :element-type '(unsigned-byte 8))
      (let* ((length (file-length stream))
             (bytes (make-array length
                                :element-type '(unsigned-byte 8))))
        (read-sequence bytes stream)
        bytes))))

(defun clankolas-png-size (bytes)
  (values
   (logior (ash (aref bytes 16) 24)
           (ash (aref bytes 17) 16)
           (ash (aref bytes 18) 8)
           (aref bytes 19))
   (logior (ash (aref bytes 20) 24)
           (ash (aref bytes 21) 16)
           (ash (aref bytes 22) 8)
           (aref bytes 23))))

(defun announcement-image (component)
  (find-if (lambda (child)
             (typep child 'cadr-tui:image-component))
           (cadr-tui:component-children component)))

(defun with-announcement-caps (images function)
  (let ((previous cadr-tui::*terminal-capabilities*))
    (multiple-value-bind (cell-width cell-height)
        (cadr-tui:get-cell-dimensions)
      (unwind-protect
           (progn
             (cadr-tui:set-cell-dimensions 9 18)
             (cadr-tui:set-terminal-capabilities
              (cadr-tui:make-terminal-capabilities
               :images images
               :true-color-p nil
               :hyperlinks-p nil))
             (funcall function))
        (cadr-tui:set-cell-dimensions cell-width cell-height)
        (setf cadr-tui::*terminal-capabilities* previous)))))

(test clankolas-png-matches-the-v140-announcement-asset
  ;; v1.4.0 packages/coding-agent/src/modes/interactive/assets/clankolas.png
  ;; SHA-256 locked in test/fixtures/render-diff/baseline-visible-strings.json
  (let ((bytes (clankolas-bytes))
        (digest
          (string-trim
           '(#\Newline #\Space)
           (uiop:run-program
            (list "sha256sum"
                  (namestring
                   (asdf:system-relative-pathname
                    "cadr-cli"
                    "assets/interactive/clankolas.png")))
            :output :string))))
    (is (= 539053 (length bytes)))
    (is (string= +clankolas-sha256+ (subseq digest 0 64)))
    (is (= #x89 (aref bytes 0)))
    (is (string= "PNG"
                 (map 'string #'code-char
                      (subseq bytes 1 4))))
    (multiple-value-bind (width height)
        (clankolas-png-size bytes)
      (is (= 640 width))
      (is (= 537 height)))))

(test earendil-announcement-places-clankolas-after-the-link
  ;; v1.4.0 earendil-announcement.ts IMAGE_FILENAME, maxWidthCells 56,
  ;; mime image/png, fallbackColor muted. image.ts clamps width to
  ;; min(width-2, 56). Cell size 9x18 makes the default max height 28.
  ;; calculateImageCellSize on 640x537 yields columns 56 and rows 24,
  ;; idealRows 23.49375. Kitty passes optimizeAspectRatio and keeps
  ;; r=23 (23 lines). iTerm2 leaves the flag false and reserves 24.
  (let ((cadr-cli::*earendil-announcement-image-base64* :unloaded)
        (bytes (clankolas-bytes)))
    (let* ((component
             (cadr-cli:make-earendil-announcement-component))
           (children (cadr-tui:component-children component))
           (image (announcement-image component))
           (standard
             (string-trim
              '(#\Newline)
              (uiop:run-program
               (list "python3" "-c"
                     "import base64,pathlib,sys; sys.stdout.write(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode())"
                     (namestring
                      (asdf:system-relative-pathname
                       "cadr-cli"
                       "assets/interactive/clankolas.png")))
               :output :string))))
      (is (stringp cadr-cli::*earendil-announcement-image-base64*))
      (is (eq image (nth 6 children)))
      (is (typep (nth 7 children) 'cadr-tui:spacer-component))
      (is (= 1 (cadr-tui:spacer-component-lines (nth 7 children))))
      (is (= 56
             (cadr-tui::image-component-max-width-cells image)))
      (is (string= "clankolas.png"
                   (cadr-tui::image-component-filename image)))
      (is (string= "image/png"
                   (cadr-tui::image-component-mime-type image)))
      (is (string= standard
                   (cadr-tui::image-component-base64-data image)))
      (is (equalp bytes
                  (cadr-cli::decode-base64-bytes standard)))
      (with-announcement-caps
          nil
          (lambda ()
            (let ((plain
                    (mapcar #'cadr-tui:strip-terminal-sequences
                            (cadr-tui:component-render
                             component 80))))
              (is (string= "[Image: clankolas.png [image/png] 640x537]"
                           (find "[Image:" plain :test #'search)))
              (is (< (position "https://mariozechner.at/posts/2026-04-08-ive-sold-out/"
                               plain :test #'search)
                     (position "[Image:" plain :test #'search)))
              (is (char= #\─ (char (first plain) 0)))
              (is (char= #\─ (char (car (last plain)) 0))))))
      (with-announcement-caps
          :kitty
          (lambda ()
            (cadr-tui:component-invalidate image)
            (let ((lines (cadr-tui:component-render image 80)))
              (is (= 23 (length lines)))
              (is (cadr-tui:image-line-p (first lines)))
              (is (search "c=56" (first lines)))
              (is (search "r=23" (first lines)))
              (is (every #'string= (rest lines)
                         (make-list 22 :initial-element ""))))))
      (with-announcement-caps
          :iterm2
          (lambda ()
            (cadr-tui:component-invalidate image)
            (let ((lines (cadr-tui:component-render image 80)))
              (is (= 24 (length lines)))
              (is (every #'string=
                         (butlast lines)
                         (make-list 23 :initial-element "")))
              (is (search "width=56" (car (last lines))))
              (is (cadr-tui:image-line-p (car (last lines))))))))))

(test earendil-announcement-omits-the-image-when-the-asset-is-missing
  ;; v1.4.0 loadImageBase64 catches a failed read and skips Image and
  ;; the spacer that follows it. The title, link, and both borders stay.
  (is (null
       (cadr-cli::read-bundled-interactive-asset-base64
        "assets/interactive/no-such-clankolas.png")))
  (let ((cadr-cli::*earendil-announcement-image-base64* nil))
    (let* ((component
             (cadr-cli:make-earendil-announcement-component))
           (plain
             (mapcar #'cadr-tui:strip-terminal-sequences
                     (cadr-tui:component-render component 60))))
      (is (null (announcement-image component)))
      (is (search "pi has joined Earendil"
                  (format nil "~{~A~^~%~}" plain)))
      (is (search
           "https://mariozechner.at/posts/2026-04-08-ive-sold-out/"
           (format nil "~{~A~^~%~}" plain)))
      (is (not (find "[Image:" plain :test #'search)))
      (is (char= #\─ (char (first plain) 0)))
      (is (char= #\─ (char (car (last plain)) 0))))))
