(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun cache-miss-notice-message
    (&key (model "test")
       (input 0)
       (cache-read 0)
       (cache-write 0)
       (input-cost 0d0)
       (cache-read-cost 0d0)
       (cache-write-cost 0d0)
       (timestamp 0)
       (stop-reason :stop))
  (cadr-ai:make-assistant-message
   :content nil
   :api :anthropic-messages
   :provider :test
   :model model
   :usage
   (cadr-ai:make-usage
    :input input
    :output 10
    :cache-read cache-read
    :cache-write cache-write
    :cost
    (cadr-ai:make-cost
     :input input-cost
     :cache-read cache-read-cost
     :cache-write cache-write-cost
     :total
     (+ input-cost
        cache-read-cost
        cache-write-cost)))
   :stop-reason stop-reason
   :timestamp timestamp))

(defun cache-miss-notice-texts (state)
  (loop for entry in (cadr-cli::tui-state-entries state)
        when (eq (cadr-cli::tui-entry-type entry) :notice)
          collect (cadr-cli::tui-entry-text entry)))

(defun cache-miss-notice-plain-text (text)
  (remove-if
   (lambda (char)
     (or (eql char #\Escape)
         (< (char-code char) 32)))
   text))

(test cache-miss-notices-setting-off-skips-large-miss
  (let* ((prior
           (cache-miss-notice-message
            :cache-write 100000
            :cache-write-cost 0.375d0
            :timestamp 0))
         (current
           (cache-miss-notice-message
            :input 100000
            :input-cost 0.3d0
            :timestamp 60000))
         (state (cadr-cli::make-tui-state)))
    (cadr-cli::maybe-show-cache-miss-notice
     state current
     :show-p nil
     :session-entries (list prior)
     :model-price-function
     (lambda (provider model)
       (declare (ignore provider model))
       0.3d0))
    (is (null (cache-miss-notice-texts state)))))

(test cache-miss-notices-setting-on-shows-large-miss
  (let* ((prior
           (cache-miss-notice-message
            :cache-write 100000
            :cache-write-cost 0.375d0
            :timestamp 0))
         (current
           (cache-miss-notice-message
            :input 100000
            :input-cost 0.3d0
            :timestamp 60000))
         (state (cadr-cli::make-tui-state)))
    (cadr-cli::maybe-show-cache-miss-notice
     state current
     :show-p t
     :session-entries (list prior)
     :model-price-function
     (lambda (provider model)
       (declare (ignore provider model))
       0.3d0))
    (let ((texts (cache-miss-notice-texts state)))
      (is (= 1 (length texts)))
      (let ((plain
              (cache-miss-notice-plain-text
               (first texts))))
        (is (search "Cache miss:" plain))
        (is (search "tokens re-billed" plain))
        (is (search "~$" plain))))))

(test cache-miss-notices-setting-on-skips-tiny-miss
  (let* ((prior
           (cache-miss-notice-message
            :cache-write 10000
            :cache-write-cost 0.03d0
            :timestamp 0))
         (current
           (cache-miss-notice-message
            :input 5000
            :cache-read 0
            :input-cost 0.01d0
            :timestamp 1000))
         (state (cadr-cli::make-tui-state))
         (miss
           (cadr-cli::detect-cache-miss-from-entries
            (list prior) current
            :model-price-function
            (lambda (provider model)
              (declare (ignore provider model))
              0.3d0))))
    (is (not (null miss)))
    (is (< (cadr-cli:cache-miss-missed-tokens miss) 20000))
    (is (< (cadr-cli:cache-miss-missed-cost miss) 0.1d0))
    (cadr-cli::maybe-show-cache-miss-notice
     state current
     :show-p t
     :session-entries (list prior)
     :model-price-function
     (lambda (provider model)
       (declare (ignore provider model))
       0.3d0))
    (is (null (cache-miss-notice-texts state)))))
