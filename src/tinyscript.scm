#!/usr/bin/guile \
-L /storage/Projects/tinyscript/src \
-e main -s
!#
;;; tinyscript - Tinyscript interpreter entry point
;;; Usage: tinyscript <file.ts>

(use-modules (tinyscript eval))

(define (main args)
  (if (< (length args) 2)
      (begin
        (display "Usage: tinyscript <file.ts>\n")
        (display "  or:   echo 'print(1+1)' | tinyscript -\n")
        (exit 1))
      (let ((file (list-ref args 1)))
        (catch #t
          (lambda ()
            (if (string=? file "-")
                (let ((src (read-string (current-input-port))))
                  (evaluate-string src))
                (evaluate-file file)))
          (lambda (key . args)
            (display "Error: ")
            (display key)
            (newline)
            (for-each (lambda (a)
                        (display "  ")
                        (write a)
                        (newline))
                      args)
            (exit 1))))))
