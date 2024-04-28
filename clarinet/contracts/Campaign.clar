
;; errors
(define-constant err-not-enough-funds u100)
(define-constant err-already-funded u101)
(define-constant err-max-funders u102)
(define-constant err-unwrap u103)
(define-constant err-contract-funded u104)
(define-constant err-already-claimed u105)
(define-constant err-has-not-submitted-milestone u106)
(define-constant err-not-owner u107)
(define-constant err-already-voted u108)

;; global variables
(define-data-var funding-goal uint u0)
(define-data-var end-block uint u0)
(define-data-var milestones uint u0)
(define-map donator-tokens principal uint)
(define-data-var donators (list 500 principal) (list tx-sender))
(define-data-var funded bool false)
(define-data-var total-tokens uint u0)
(define-data-var stats-per-token uint u0)
(define-data-var claimed-first bool false)
(define-data-var owner principal tx-sender)
(define-map milestone-details uint {details: (string-ascii 50)})
(define-data-var current-milestone uint u1)
(define-map has-submitted-milestone uint bool)
(define-map milestone-votes uint uint)
(define-map has-voted-milestone { user:principal, milestone:uint} bool)
(define-map vote-frozen principal bool)
(define-data-var num-frozen-votes uint u0)
(define-data-var frozen bool false)

(define-data-var temp-tx-sender principal tx-sender)


;; Procedural Private functions
(define-private (funding-ended)
    (ok (asserts! (is-eq (var-get funded) false) (err err-already-funded)))
)

(define-private (check-end-deadline) 
    (begin
        (asserts! (is-eq true true) (err u1))
        (if (>= block-height (var-get funding-goal))
        (begin 
            (var-set frozen true)
            (ok (var-set stats-per-token (/ (stx-get-balance (as-contract tx-sender)) (var-get total-tokens))))
        )
        (ok true))
    )
)


;; Create Campaign

(define-public (start (goal uint) (block-duration uint) (num-milestones uint)) 
    (begin
        (var-set funding-goal goal)
        (var-set end-block (+ block-height block-duration))
        (var-set milestones num-milestones)
        (ok true)
    )
)

;; Funding Related Functions

(define-public (donate (amount uint))
    (begin 
        (try! (funding-ended))
        (try! (check-end-deadline))
        (asserts! (> (stx-get-balance tx-sender) amount) (err err-not-enough-funds))
        (map-insert donator-tokens tx-sender amount)
        (if (is-eq (len (var-get donators)) u0) 
            (var-set donators (list tx-sender))
            (var-set donators (default-to (var-get donators) (as-max-len? (concat (var-get donators) (list tx-sender)) u500)))
        )
        (var-set total-tokens (+ (var-get total-tokens) amount))
        (if (> (var-get funding-goal) (stx-get-balance (as-contract tx-sender)))
            (var-set funded true)
            (var-set funded false)
        )
        (stx-transfer? amount tx-sender (as-contract tx-sender))
    )
)

(define-public (claim-refund) 
    (begin
        (asserts! (< (var-get funding-goal) (stx-get-balance (as-contract tx-sender))) (err err-not-enough-funds))
        (asserts! (is-eq (var-get frozen) true)  (err err-contract-funded)) 
        (asserts! 
            (>= 
                (stx-get-balance (as-contract tx-sender)) 
                (* (var-get stats-per-token) (default-to u0 (map-get? donator-tokens tx-sender)))
            ) 
            (err err-not-enough-funds)
        )
        (var-set temp-tx-sender tx-sender)
        (as-contract (stx-transfer? (* (var-get stats-per-token) (default-to u0 (map-get? donator-tokens (var-get temp-tx-sender)))) tx-sender (var-get temp-tx-sender)))) ;; Returns 20
)

(define-public (claim-first-milestone) 
    (begin 
        (asserts! (is-eq (var-get funded) true) (err err-not-enough-funds))
        (asserts! (is-eq (var-get claimed-first) false) (err err-already-claimed))
        (var-set current-milestone (+ u1 (var-get current-milestone)))
        (as-contract (stx-transfer? (/ (stx-get-balance tx-sender) (var-get milestones)) tx-sender (var-get owner)))
    )
)

;; DAO Functions
(define-public (submit-milestone (submission-details (string-ascii 50)))
    (begin 
        (asserts! (is-eq tx-sender (var-get owner)) (err err-not-owner))
        (map-insert milestone-details (var-get current-milestone) {details:submission-details})
        (map-insert has-submitted-milestone (var-get current-milestone) true)
        (ok true)
    )
)

(define-public (vote-on-milestone) 
    (begin  
        (asserts! (default-to false (map-get? has-submitted-milestone (var-get current-milestone))) (err err-has-not-submitted-milestone))
        (asserts! (default-to true (map-get? has-voted-milestone {user:tx-sender, milestone:(var-get current-milestone)})) (err err-already-voted))
        (map-insert milestone-votes (var-get current-milestone) 
            (+ 
                (default-to u0 (map-get? donator-tokens tx-sender)) 
                (default-to u0 (map-get? milestone-votes (var-get current-milestone)))
            )
        )
        (map-insert has-voted-milestone {user:tx-sender, milestone:(var-get current-milestone)} false)
        (if (> (default-to u0 (map-get? milestone-votes (var-get current-milestone))) (/ (var-get total-tokens) u2)) 
                (begin 
                    (var-set current-milestone (+ u1 (var-get current-milestone)))
                    (as-contract (stx-transfer? (/ (stx-get-balance tx-sender) (var-get milestones)) tx-sender (var-get owner)))
                )
                (ok (var-set current-milestone (var-get current-milestone)))
        )
    )
)

(define-public (vote-to-freeze)
    (begin
        (asserts! (default-to true (map-get? vote-frozen tx-sender)) (err err-already-voted))
        (map-insert vote-frozen tx-sender false)
        (var-set num-frozen-votes (+ (default-to u0 (map-get? donator-tokens tx-sender)) (var-get num-frozen-votes)))
        (if ( > (var-get num-frozen-votes) (/ (var-get total-tokens) u2))
            (begin 
                (var-set frozen true)
                (ok (var-set stats-per-token (/ (stx-get-balance (as-contract tx-sender)) (var-get total-tokens))))
            )
            (ok true)
        ) 
    ) 
)





