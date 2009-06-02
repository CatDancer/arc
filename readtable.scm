; By Cat Dancer, cat@catdancer.ws
; This code is released to the public domain, except for
; the copy of ac-niltree, which is a part of Arc.

(module readtable mzscheme

(require "skipwhite.scm")

; need a copy of ac-niltree as long as the reader reads
; MzScheme lists instead of Arc lists

(define (ac-niltree x)
  (cond ((pair? x) (cons (ac-niltree (car x)) (ac-niltree (cdr x))))
        ((or (eq? x #f) (eq? x '())) 'nil)
        (#t x)))

(define (readnil port)
  (ac-niltree (read port)))

(define (slurp port a)
  (skip-whitespace port)
  (if (eq? (peek-char port) #\})
      (begin (read-char port)
             a)
      (let ((k (readnil port)))
        (let ((v (readnil port)))
          (hash-table-put! a k v)
          (slurp port a)))))

(define (parse-table ch port src line col pos)
  (slurp port (make-hash-table 'equal)))

(define (table-readtable)
  (make-readtable (current-readtable) #\{ 'non-terminating-macro parse-table))

(provide use-table-readtable)

(define (use-table-readtable)
  (current-readtable (table-readtable)))

)
