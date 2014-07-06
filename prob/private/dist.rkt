;; Copyright (c) 2014 Ryan Culpepper
;; Released under the terms of the 2-clause BSD license.
;; See the file COPYRIGHT for details.

#lang racket/base
(require (for-syntax racket/base
                     syntax/parse
                     racket/syntax)
         racket/generic
         racket/flonum
         racket/vector
         (prefix-in m: math/distributions))
(provide dist?
         dist-pdf
         dist-cdf
         dist-inv-cdf
         dist-sample
         dist-enum
         make-bernoulli-dist
         make-binomial-dist
         make-geometric-dist
         make-poisson-dist 
         make-beta-dist 
         make-cauchy-dist
         make-exponential-dist
         make-gamma-dist
         make-logistic-dist
         make-normal-dist
         make-uniform-dist
         ;; make-discrete-dist
         )

;; FIXME: discrete dists
;; - categorical has support 1..N
;; - discrete has arbitrary support
;;   - print nicely (sort)
;;   - enumerate etc should return discrete dist instead of list
;; - ??? normalized vs unnormalized?

;; FIXME: contracts

;; TODO:
;; - support
;; - dist statistics: mean, median, variance, etc

;; Distributions from math/distributions have performance penalty in untyped code
;; (Also, no discrete-dist? predicate.)

;; A Dist is (pdist pdf cdf inv-cdf sample enum)
;; - pdf : Real Boolean -> Flonum
;; - cdf : Real Boolean Boolean -> Flonum
;; - inv-cdf : Probability -> Flonum
;; - sample : Nat -> FlVector
;; - enum : PosInt    -- {0 ... n-1}
;;        | 'lazy     -- {0 ... }
;;        | #f        -- not enumerable
(struct pdist ())

(define-generics dist
  (*pdf dist x log?)
  (*cdf dist x log? 1-p?)
  (*inv-cdf dist x log? 1-p?)
  (*sample dist)
  (*type dist)
  (*params dist)
  (*enum dist))

(define (dist-pdf d x [log? #f])
  (*pdf d x log?))
(define (dist-cdf d x [log? #f] [1-p? #f])
  (*cdf d x log? 1-p?))
(define (dist-inv-cdf d x [log? #f] [1-p? #f])
  (*inv-cdf d x log? 1-p?))
(define (dist-sample d)
  (*sample d))
(define (dist-enum d)
  (*enum d))

;; ----

(define-syntax (define-dist-type stx)

  (define-syntax-class param-spec
    (pattern param:id))

  (syntax-parse stx
    [(define-dist-type name (p:param-spec ...)
       (~and kind-kw (~or #:nat #:real #:any))
       (~or (~optional (~seq #:enum enum:expr) #:defaults ([enum #'#f]))
            (~optional (~seq #:guard guard-fun:expr) #:defaults ([guard-fun #'#f])))
       ...
       extra-clause ...)
     (define kind
       (case (syntax->datum #'kind-kw)
         [(#:nat) 'nat] [(#:real) 'real] [(#:any) 'any]))
     (define prefix (case kind [(nat real) "m:fl"] [(any) "raw"]))
     (with-syntax ([name-dist (format-id #'name "~a-dist" #'name)]
                   [make-name-dist (format-id #'name "make-~a-dist" #'name)]
                   [(get-param ...)
                    (for/list ([param (in-list (syntax->list #'(p.param ...)))])
                      (format-id #'name "~a-dist-~a" #'name param))]
                   [fl-pdf (format-id #'name "~a~a-pdf" prefix #'name)]
                   [fl-cdf (format-id #'name "~a~a-cdf" prefix #'name)]
                   [fl-inv-cdf (format-id #'name "~a~a-inv-cdf" prefix #'name)]
                   [fl-sample (format-id #'name "~a~a-sample" prefix #'name)]
                   [kind kind])
       #'(struct name-dist pdist (p.param ...)
                 #:extra-constructor-name make-name-dist
                 #:guard
                 (or guard-fun
                     (make-guard-fun (p.param ...) kind-kw))
                 #:methods gen:dist
                 [(define (*pdf d x log?)
                    (fl-pdf (get-param d) ... (exact->inexact x) log?))
                  (define (*cdf d x log? 1-p?)
                    (fl-cdf (get-param d) ... (exact->inexact x) log? 1-p?))
                  (define (*inv-cdf d x log? 1-p?)
                    (fl-inv-cdf (get-param d) ... (exact->inexact x) log? 1-p?))
                  (define (*sample d)
                    (case 'kind
                      [(nat) (inexact->exact (flvector-ref (fl-sample (get-param d) ... 1) 0))]
                      [(real) (flvector-ref (fl-sample (get-param d) ... 1) 0)]
                      [(any) (fl-sample (get-param d) ...)]))
                  (define (*type d) 'name)
                  (define (*params d) (vector (get-param d) ...))
                  (define (*enum d)
                    (let ([p.param (get-param d)] ...)
                      enum))]
                 extra-clause ...
                 #:transparent))]))

(define-syntax (make-guard-fun stx)
  (syntax-parse stx
    [(make-guard-fun (param ...) #:any)
     #'#f]
    [(make-guard-fun (param ...) #:nat)
     #'(lambda (param ... _name) (values (exact->inexact param) ...))]
    [(make-guard-fun (param ...) #:real)
     #'(lambda (param ... _name) (values (exact->inexact param) ...))]))

;; ----

(define-dist-type bernoulli   (prob)        #:nat #:enum 2)
(define-dist-type binomial    (n p)         #:nat #:enum (add1 n))
(define-dist-type geometric   (p)           #:nat #:enum 'lazy)
(define-dist-type poisson     (mean)        #:nat #:enum 'lazy)
(define-dist-type beta        (a b)         #:real)
(define-dist-type cauchy      (mode scale)  #:real)
(define-dist-type exponential (mean)        #:real)
(define-dist-type gamma       (shape scale) #:real)
(define-dist-type logistic    (mean scale)  #:real)
(define-dist-type normal      (mean stddev) #:real)
(define-dist-type uniform     (min max)     #:real)

(define-dist-type categorical (weights) #:any #:enum (length weights)
  #:guard (lambda (weights _name) (validate/normalize-weights 'categorical-dist weights)))

#|
(define-dist-type discrete (vals weights) #:any #:enum vals
  #:guard (lambda (vals weights _name)
            (unless (and (vector? vals) (vector? weights)
                         (= (vector-length vals) (vector-length weights)))
              (raise-arguments-error 'discrete-dist
                "values and weights have unequal lengths\n  values: ~e\n  weights: ~e"
                vals weights))
            (define weights* (validate-weights 'discrete-dist weights))
            (values (vector->immutable-vector vals) weights*)))
|#

(define (validate/normalize-weights who weights)
  (unless (and (vector? weights)
               (for/and ([w (in-vector weights)])
                 (and (rational? w) (>= w 0))))
    (raise-argument-error 'categorical-dist "(vectorof (>=/c 0))" weights))
  (define weight-sum (for/sum ([w (in-vector weights)]) w))
  (unless (> weight-sum 0)
    (error 'categorical-dist "weights sum to zero\n  weights: ~e" weights))
  (if (= weight-sum 1)
      (vector->immutable-vector weights)
      (vector-map (lambda (w) (/ w weight-sum)) weights)))

#|
(define (make-discrete-dist probs)
  (let ([n (length probs)]
        [prob-sum (apply + probs)])
    (make-dist discrete #:raw-params (probs prob-sum) #:enum n)))
|#

;; ============================================================
;; Categorical weighted dist functions
;; -- Assume weights are nonnegative, normalized.

(define (rawcategorical-pdf probs k log?)
  (unless (< k (vector-length probs))
    (error 'categorical-pdf "index out of bounds\n  index: ~e\n  bounds: [0,~s]"
           k (sub1 (vector-length probs))))
  (define l (vector-ref probs k))
  (if log? (log l) l))
(define (rawcategorical-cdf probs k log? 1-p?)
  (define p (for/sum ([i (in-range (add1 k))] [prob (in-list probs)]) prob))
  (convert-p p log? 1-p?))
(define (rawcategorical-inv-cdf probs p log? 1-p?)
  (when (or log? 1-p?) (error 'rawcategorical-inv-cdf "unimplemented"))
  (let loop ([probs probs] [p p] [i 0])
    (cond [(null? probs)
           (error 'rawcategorical-inv-cdf "out of values")]
          [(< p (car probs))
           i]
          [else
           (loop (cdr probs) (- p (car probs)) (add1 i))])))
(define (rawcategorical-sample probs)
  (rawcategorical-inv-cdf probs (random) #f #f))

(define (convert-p p log? 1-p?)
  (define p* (if 1-p? (- 1 p) p))
  (if log? (log p*) p*))