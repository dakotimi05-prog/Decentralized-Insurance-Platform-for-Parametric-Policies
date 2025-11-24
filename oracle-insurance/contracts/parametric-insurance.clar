;; parametric-insurance.clar
;; Simplified parametric insurance pool that relies on the `oracles` contract
;; for external data and automates payouts based on those values.

(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_POLICY_NOT_FOUND (err u201))
(define-constant ERR_POLICY_INACTIVE (err u202))
(define-constant ERR_INSUFFICIENT_LIQUIDITY (err u300))
(define-constant ERR_INVALID_AMOUNT (err u301))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ORACLE_ERROR (err u600))

;; --- Core pool state -------------------------------------------------------

(define-data-var total-liquidity uint u0)
(define-data-var reserved-liquidity uint u0)
(define-data-var next-policy-id uint u1)

(define-map liquidity-providers
  { provider: principal }
  { amount: uint })

;; Flight-delay policies. Rainfall and earthquake support can be added
;; with similar maps and functions, but this map is enough to demonstrate
;; the parametric idea end-to-end.

(define-map flight-policies
  { id: uint }
  {
    owner: principal,
    flight-id: (string-ascii 32),
    threshold-minutes: uint,
    premium: uint,
    payout-amount: uint,
    active: bool,
    claimed: bool
  })

;; --- Helpers ---------------------------------------------------------------

(define-read-only (get-pool-stats)
  (ok {
    total-liquidity: (var-get total-liquidity),
    reserved-liquidity: (var-get reserved-liquidity)
  }))

(define-read-only (get-liquidity-of (provider principal))
  (ok (default-to u0
        (get amount (map-get? liquidity-providers { provider: provider })))))

(define-read-only (get-free-liquidity)
  (ok (- (var-get total-liquidity) (var-get reserved-liquidity))))

(define-private (ensure-free-liquidity (amount uint))
  (let ((free (- (var-get total-liquidity) (var-get reserved-liquidity))))
    (if (>= free amount)
        (ok true)
        ERR_INSUFFICIENT_LIQUIDITY)))

(define-read-only (get-flight-policy (id uint))
  (match (map-get? flight-policies { id: id })
    data (ok data)
    ERR_POLICY_NOT_FOUND))

;; --- Liquidity management --------------------------------------------------

(define-public (deposit-liquidity (amount uint))
  (if (is-eq amount u0)
      ERR_INVALID_AMOUNT
      (let ((current (default-to u0
                        (get amount (map-get? liquidity-providers { provider: tx-sender }))))
            (new-amount (+ current amount)))
        (map-set liquidity-providers { provider: tx-sender } { amount: new-amount })
        (var-set total-liquidity (+ (var-get total-liquidity) amount))
        (ok new-amount))))

(define-public (withdraw-liquidity (amount uint))
  (let ((record (map-get? liquidity-providers { provider: tx-sender })))
    (match record
      lp
        (let ((current (get amount lp)))
          (if (or (is-eq amount u0) (> amount current))
              ERR_INVALID_AMOUNT
              (begin
                (try! (ensure-free-liquidity amount))
                (let ((new-amount (- current amount)))
                  (if (is-eq new-amount u0)
                      (map-delete liquidity-providers { provider: tx-sender })
                      (map-set liquidity-providers { provider: tx-sender } { amount: new-amount }))
                  (var-set total-liquidity (- (var-get total-liquidity) amount))
                  (ok new-amount)))))
      ERR_NOT_FOUND)))

;; --- Flight-delay policy lifecycle ----------------------------------------

(define-public (buy-flight-policy
    (flight-id (string-ascii 32))
    (threshold-minutes uint)
    (premium uint)
    (payout-amount uint))
  (begin
    (if (or (is-eq payout-amount u0) (is-eq threshold-minutes u0))
        ERR_INVALID_AMOUNT
        (begin
          (try! (ensure-free-liquidity payout-amount))
          (let ((policy-id (var-get next-policy-id)))
            (map-set flight-policies { id: policy-id }
              {
                owner: tx-sender,
                flight-id: flight-id,
                threshold-minutes: threshold-minutes,
                premium: premium,
                payout-amount: payout-amount,
                active: true,
                claimed: false
              })
            (var-set next-policy-id (+ policy-id u1))
            (var-set reserved-liquidity (+ (var-get reserved-liquidity) payout-amount))
            (ok policy-id))))))

(define-public (check-flight-policy-and-payout (policy-id uint))
  (match (map-get? flight-policies { id: policy-id })
    pol
      (if (or (not (get active pol)) (get claimed pol))
          ERR_POLICY_INACTIVE
          (let ((oracle-response (contract-call? .oracles get-flight-delay (get flight-id pol))))
            (match oracle-response
              oracle-data
                (let ((delay (get delay-minutes oracle-data))
                      (threshold (get threshold-minutes pol))
                      (payout (get payout-amount pol)))
                  (if (>= delay threshold)
                      (begin
                        ;; condition met: mark as claimed and burn liquidity
                        (var-set reserved-liquidity (- (var-get reserved-liquidity) payout))
                        (var-set total-liquidity (- (var-get total-liquidity) payout))
                        (map-set flight-policies { id: policy-id }
                          {
                            owner: (get owner pol),
                            flight-id: (get flight-id pol),
                            threshold-minutes: threshold,
                            premium: (get premium pol),
                            payout-amount: payout,
                            active: false,
                            claimed: true
                          })
                        (ok true))
                      ;; condition not met yet
                      (ok false)))
              err-code
                ERR_ORACLE_ERROR)))
    ERR_POLICY_NOT_FOUND))
