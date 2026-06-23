#!/usr/bin/guile
-e main -s
!#
;;; gmake — GNU Guile Build System
;;; A Make replacement using Guile Scheme
;;; Usage: gmake [target]
;;; Looks for a gmakefile in the current directory

(use-modules (ice-9 rdelim) (ice-9 ftw) (srfi srfi-1)
             (srfi srfi-9) (ice-9 format) (ice-9 regex)
             (ice-9 match))

;; --- File utilities ---

(define (file-newer? a b)
  "Return #t if file A is newer than file B"
  (let ((stat-a (stat a #f))
        (stat-b (stat b #f)))
    (if (and stat-a stat-b)
        (> (stat:mtime stat-a) (stat:mtime stat-b))
        #t)))

(define (file-exists? path)
  (->bool (stat path #f)))

(define (find-gmakefile)
  "Look for a gmakefile in current or parent dirs"
  (let ((candidates '("gmakefile" "GMAKEFILE" "Gmakefile")))
    (any (lambda (f)
           (and (file-exists? f) f))
         candidates)))

(define (sh command)
  "Run a shell command, return exit status"
  (let ((ret (system command)))
    (unless (zero? ret)
      (format #t "gmake: [~a] Error ~a~%" command (status:exit-val ret)))
    ret))

(define (sh-output command)
  "Run a shell command and return stdout as string"
  (let* ((port (open-input-pipe command))
         (output (read-string port)))
    (close-pipe port)
    output))

;; --- Build rule types ---

(define-record-type <target>
  (make-target name deps actions doc)
  target?
  (name    target-name)
  (deps    target-deps)
  (actions target-actions)
  (doc     target-doc))

(define %targets (make-hash-table))
(define %default-target #f)
(define %variables (make-hash-table))

(define (add-target! name deps actions doc)
  (hash-set! %targets name
             (make-target name deps actions doc)))

(define (get-target name)
  (hash-ref %targets name #f))

(define (var-ref name)
  "Get a build variable value"
  (hash-ref %variables name ""))

(define (var-set! name val)
  (hash-set! %variables name val))

(define (expand-vars str)
  "Expand $(VAR) references in a string"
  (regexp-substitute/global #f "\\$\\([^)]+\\)" str
    'pre (lambda (m) (var-ref (match:substring m 1))) 'post))

;; --- Build execution ---

(define (build-target name)
  "Build a target and its dependencies"
  (let ((target (get-target name)))
    (unless target
      (format #t "gmake: *** No rule to make target '~a'.~%" name)
      (exit 2))

    (let ((tname (target-name target))
          (deps  (target-deps target))
          (acts  (target-actions target)))

      ;; Build dependencies first
      (for-each (lambda (dep)
                  (if (get-target dep)
                      (build-target dep)
                      (unless (file-exists? dep)
                        (format #t "gmake: *** No rule to make '~a'.~%" dep)
                        (exit 2))))
                deps)

      ;; Check if we need to rebuild
      (let* ((target-file (if (file-exists? tname) tname #f))
             (dep-files (filter file-exists? deps))
             (need-build (or (not target-file)
                             (and (pair? dep-files)
                                  (any (lambda (d)
                                         (file-newer? d target-file))
                                       dep-files))
                             (and (null? dep-files) (pair? acts)))))

        (when need-build
          (format #t "gmake: Building '~a'...~%" tname)
          (for-each (lambda (action)
                      (let ((cmd (expand-vars action)))
                        (format #t "  ~a~%" cmd)
                        (unless (zero? (sh cmd))
                          (format #t "gmake: *** [~a] Error~%" tname)
                          (exit 1))))
                    acts))
        (if need-build
            (format #t "gmake: '~a' built.~%" tname)
            (format #t "gmake: '~a' is up to date.~%" tname))))))

;; --- Load gmakefile ---

(define (load-gmakefile filename)
  "Load and evaluate a gmakefile"
  (format #t "gmake: Reading '~a'~%" filename)

  (define (target name doc deps actions)
    (add-target! name deps actions doc))

  (define (default-target name)
    (set! %default-target name))

  (define (variable name val)
    (var-set! name val))

  (define action sh)

  ;; Export DSL to the gmakefile's scope
  (let ((env (current-module)))
    (module-define! env 'target target)
    (module-define! env 'default-target default-target)
    (module-define! env 'variable variable)
    (module-define! env 'action action))

  (load filename))

;; --- List targets ---

(define (list-targets)
  (format #t "~%Targets:~%")
  (hash-for-each (lambda (name target)
                   (let ((doc (target-doc target)))
                     (if (and doc (not (string-null? doc)))
                         (format #t "  ~a  ~a~%" name doc)
                         (format #t "  ~a~%" name))))
                 %targets)
  (newline))

;; --- Main ---

(define (main args)
  (let ((gmakefile (find-gmakefile)))
    (unless gmakefile
      (format #t "gmake: *** No gmakefile found.~%")
      (exit 1))

    (load-gmakefile gmakefile)

    (if (<= (length args) 1)
        ;; No target specified — build default or list
        (if %default-target
            (build-target %default-target)
            (list-targets))
        ;; Build specified targets
        (for-each build-target (cdr args)))))
