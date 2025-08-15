;; peer-to-peer-insurance.clar
;;
;; A decentralized insurance system with community-driven claims processing
;; and automated risk assessment

;; --- Constants and Error Codes ---
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u300))
(define-constant ERR_NOT_FOUND (err u301))
(define-constant ERR_INSUFFICIENT_BALANCE (err u302))
(define-constant ERR_INVALID_AMOUNT (err u303))
(define-constant ERR_POOL_FULL (err u304))
(define-constant ERR_CLAIM_EXPIRED (err u305))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u306))
(define-constant ERR_INSUFFICIENT_VALIDATORS (err u307))
(define-constant ERR_ALREADY_VALIDATED (err u308))
(define-constant ERR_INVALID_RISK_SCORE (err u309))
(define-constant ERR_PAYOUT_FAILED (err u310))

(define-constant MIN_POOL_STAKE u1000000) ;; 1000 STX in microSTX
(define-constant MIN_VALIDATOR_STAKE u500000) ;; 500 STX in microSTX
(define-constant MAX_POOL_SIZE u100) ;; Maximum participants per pool
(define-constant CLAIM_VALIDATION_PERIOD u1008) ;; ~1 week in blocks
(define-constant MIN_VALIDATORS_REQUIRED u3)
(define-constant VALIDATOR_CONSENSUS_THRESHOLD u66) ;; 66% agreement needed
(define-constant PREMIUM_RATE_BASE u1000) ;; 10% annual premium base rate

;; --- Data Variables ---
(define-data-var next-pool-id uint u1)
(define-data-var next-claim-id uint u1)
(define-data-var next-policy-id uint u1)
(define-data-var total-pools uint u0)
(define-data-var total-claims-processed uint u0)
(define-data-var total-payouts uint u0)

;; --- Data Maps ---

;; Insurance pools
(define-map insurance-pools uint {
  pool-name: (string-ascii 64),
  pool-type: (string-ascii 32), ;; "health", "property", "travel", etc.
  creator: principal,
  total-staked: uint,
  total-coverage: uint,
  participant-count: uint,
  max-coverage-per-claim: uint,
  base-premium-rate: uint,
  active: bool,
  creation-block: uint
})

;; Pool participants and their policies
(define-map pool-policies uint {
  pool-id: uint,
  policyholder: principal,
  stake-amount: uint,
  coverage-amount: uint,
  premium-paid: uint,
  risk-score: uint, ;; 1-100, higher = riskier
  join-block: uint,
  last-premium-block: uint,
  active: bool
})

;; Claims registry
(define-map insurance-claims uint {
  claimant: principal,
  pool-id: uint,
  policy-id: uint,
  claim-amount: uint,
  claim-type: (string-ascii 32),
  description: (string-ascii 256),
  evidence-hash: (string-ascii 64),
  submission-block: uint,
  validation-deadline: uint,
  validators-assigned: uint,
  validators-approved: uint,
  validators-rejected: uint,
  total-validator-stake: uint,
  approved-validator-stake: uint,
  status: (string-ascii 16), ;; "pending", "approved", "rejected", "paid"
  payout-amount: uint
})

;; Claim validators
(define-map claim-validators { claim-id: uint, validator: principal } {
  stake-amount: uint,
  vote: (optional bool), ;; true = approve, false = reject
  vote-block: uint,
  evidence-reviewed: bool
})

;; Validator registry
(define-map validators principal {
  stake-amount: uint,
  claims-validated: uint,
  accuracy-score: uint, ;; Percentage of correct validations
  total-rewards: uint,
  active: bool,
  specialization: (string-ascii 32)
})

;; Pool membership tracking
(define-map pool-memberships { pool-id: uint, member: principal } uint) ;; policy-id

;; Risk assessment data
(define-map risk-factors { pool-type: (string-ascii 32), factor: (string-ascii 32) } uint)

;; --- Pool Management ---

(define-public (create-insurance-pool 
  (pool-name (string-ascii 64))
  (pool-type (string-ascii 32))
  (max-coverage-per-claim uint)
  (base-premium-rate uint))
  (let ((pool-id (var-get next-pool-id)))
    (asserts! (> max-coverage-per-claim u0) ERR_INVALID_AMOUNT)
    (asserts! (and (> base-premium-rate u0) (<= base-premium-rate u5000)) ERR_INVALID_AMOUNT) ;; Max 50% premium

    (map-set insurance-pools pool-id {
      pool-name: pool-name,
      pool-type: pool-type,
      creator: tx-sender,
      total-staked: u0,
      total-coverage: u0,
      participant-count: u0,
      max-coverage-per-claim: max-coverage-per-claim,
      base-premium-rate: base-premium-rate,
      active: true,
      creation-block: block-height
    })

    (var-set next-pool-id (+ pool-id u1))
    (var-set total-pools (+ (var-get total-pools) u1))

    (print { type: "pool-created", pool-id: pool-id, creator: tx-sender })
    (ok pool-id)
  )
)

(define-public (join-insurance-pool (pool-id uint) (stake-amount uint) (coverage-amount uint))
  (let ((pool (unwrap! (map-get? insurance-pools pool-id) ERR_NOT_FOUND))
        (policy-id (var-get next-policy-id)))
    (asserts! (get active pool) ERR_NOT_FOUND)
    (asserts! (>= stake-amount MIN_POOL_STAKE) ERR_INSUFFICIENT_BALANCE)
    (asserts! (<= coverage-amount (get max-coverage-per-claim pool)) ERR_INVALID_AMOUNT)
    (asserts! (< (get participant-count pool) MAX_POOL_SIZE) ERR_POOL_FULL)
    (asserts! (is-none (map-get? pool-memberships { pool-id: pool-id, member: tx-sender })) ERR_NOT_AUTHORIZED)

    ;; Calculate risk score and premium
    (let ((risk-score (calculate-risk-score tx-sender (get pool-type pool)))
          (annual-premium (calculate-premium coverage-amount (get base-premium-rate pool) risk-score)))

      (try! (stx-transfer? (+ stake-amount annual-premium) tx-sender (as-contract tx-sender)))

      (map-set pool-policies policy-id {
        pool-id: pool-id,
        policyholder: tx-sender,
        stake-amount: stake-amount,
        coverage-amount: coverage-amount,
        premium-paid: annual-premium,
        risk-score: risk-score,
        join-block: block-height,
        last-premium-block: block-height,
        active: true
      })

      (map-set pool-memberships { pool-id: pool-id, member: tx-sender } policy-id)

      ;; Update pool stats
      (map-set insurance-pools pool-id 
        (merge pool {
          total-staked: (+ (get total-staked pool) stake-amount),
          total-coverage: (+ (get total-coverage pool) coverage-amount),
          participant-count: (+ (get participant-count pool) u1)
        }))

      (var-set next-policy-id (+ policy-id u1))
      (print { type: "policy-created", policy-id: policy-id, pool-id: pool-id, holder: tx-sender })
      (ok policy-id)
    )
  )
)

;; --- Validator System ---

(define-public (register-as-validator (stake-amount uint) (specialization (string-ascii 32)))
  (begin
    (asserts! (>= stake-amount MIN_VALIDATOR_STAKE) ERR_INSUFFICIENT_BALANCE)
    (asserts! (is-none (map-get? validators tx-sender)) ERR_NOT_AUTHORIZED)

    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))

    (map-set validators tx-sender {
      stake-amount: stake-amount,
      claims-validated: u0,
      accuracy-score: u100, ;; Start with perfect score
      total-rewards: u0,
      active: true,
      specialization: specialization
    })

    (print { type: "validator-registered", validator: tx-sender, specialization: specialization })
    (ok true)
  )
)

(define-public (increase-validator-stake (additional-amount uint))
  (let ((validator-info (unwrap! (map-get? validators tx-sender) ERR_NOT_FOUND)))
    (try! (stx-transfer? additional-amount tx-sender (as-contract tx-sender)))

    (map-set validators tx-sender 
      (merge validator-info { 
        stake-amount: (+ (get stake-amount validator-info) additional-amount) 
      }))

    (ok true)
  )
)

;; --- Claims Processing ---

(define-public (submit-claim 
  (pool-id uint)
  (claim-amount uint)
  (claim-type (string-ascii 32))
  (description (string-ascii 256))
  (evidence-hash (string-ascii 64)))
  (let ((claim-id (var-get next-claim-id))
        (pool (unwrap! (map-get? insurance-pools pool-id) ERR_NOT_FOUND))
        (policy-id (unwrap! (map-get? pool-memberships { pool-id: pool-id, member: tx-sender }) ERR_NOT_FOUND))
        (policy (unwrap! (map-get? pool-policies policy-id) ERR_NOT_FOUND)))

    (asserts! (get active policy) ERR_NOT_FOUND)
    (asserts! (<= claim-amount (get coverage-amount policy)) ERR_INVALID_AMOUNT)
    (asserts! (<= claim-amount (get max-coverage-per-claim pool)) ERR_INVALID_AMOUNT)

    (map-set insurance-claims claim-id {
      claimant: tx-sender,
      pool-id: pool-id,
      policy-id: policy-id,
      claim-amount: claim-amount,
      claim-type: claim-type,
      description: description,
      evidence-hash: evidence-hash,
      submission-block: block-height,
      validation-deadline: (+ block-height CLAIM_VALIDATION_PERIOD),
      validators-assigned: u0,
      validators-approved: u0,
      validators-rejected: u0,
      total-validator-stake: u0,
      approved-validator-stake: u0,
      status: "pending",
      payout-amount: u0
    })

    (var-set next-claim-id (+ claim-id u1))
    (print { type: "claim-submitted", claim-id: claim-id, claimant: tx-sender, amount: claim-amount })
    (ok claim-id)
  )
)

(define-public (validate-claim (claim-id uint) (approve bool) (stake-amount uint))
  (let ((claim (unwrap! (map-get? insurance-claims claim-id) ERR_NOT_FOUND))
        (validator-info (unwrap! (map-get? validators tx-sender) ERR_NOT_FOUND)))
    (asserts! (get active validator-info) ERR_NOT_AUTHORIZED)
    (asserts! (< block-height (get validation-deadline claim)) ERR_CLAIM_EXPIRED)
    (asserts! (is-eq (get status claim) "pending") ERR_CLAIM_ALREADY_PROCESSED)
    (asserts! (is-none (map-get? claim-validators { claim-id: claim-id, validator: tx-sender })) ERR_ALREADY_VALIDATED)
    (asserts! (<= stake-amount (get stake-amount validator-info)) ERR_INSUFFICIENT_BALANCE)

    (map-set claim-validators { claim-id: claim-id, validator: tx-sender } {
      stake-amount: stake-amount,
      vote: (some approve),
      vote-block: block-height,
      evidence-reviewed: true
    })

    ;; Update claim validation stats
    (let ((new-validators-assigned (+ (get validators-assigned claim) u1))
          (new-total-stake (+ (get total-validator-stake claim) stake-amount))
          (new-approved (if approve (+ (get validators-approved claim) u1) (get validators-approved claim)))
          (new-rejected (if approve (get validators-rejected claim) (+ (get validators-rejected claim) u1)))
          (new-approved-stake (if approve (+ (get approved-validator-stake claim) stake-amount) (get approved-validator-stake claim))))

      (map-set insurance-claims claim-id 
        (merge claim {
          validators-assigned: new-validators-assigned,
          validators-approved: new-approved,
          validators-rejected: new-rejected,
          total-validator-stake: new-total-stake,
          approved-validator-stake: new-approved-stake
        }))

      ;; Check if we have enough validators and can process the claim
      (if (>= new-validators-assigned MIN_VALIDATORS_REQUIRED)
        (try! (process-claim-if-ready claim-id))
        (ok true)
      )
    )
  )
)

(define-private (process-claim-if-ready (claim-id uint))
  (let ((claim (unwrap-panic (map-get? insurance-claims claim-id))))
    (if (>= (get validators-assigned claim) MIN_VALIDATORS_REQUIRED)
      (let ((approval-rate (/ (* (get approved-validator-stake claim) u100) (get total-validator-stake claim))))
        (if (>= approval-rate VALIDATOR_CONSENSUS_THRESHOLD)
          (begin
            ;; Approve and process payout
            (map-set insurance-claims claim-id (merge claim { status: "approved" }))
            (try! (process-payout claim-id))
            (ok true)
          )
          (begin
            ;; Reject claim
            (map-set insurance-claims claim-id (merge claim { status: "rejected" }))
            (ok false)
          )
        )
      )
      (ok true)
    )
  )
)

(define-private (process-payout (claim-id uint))
  (let ((claim (unwrap-panic (map-get? insurance-claims claim-id))))
    (if (is-eq (get status claim) "approved")
      (begin
        (try! (as-contract (stx-transfer? (get claim-amount claim) tx-sender (get claimant claim))))
        (map-set insurance-claims claim-id 
          (merge claim { 
            status: "paid", 
            payout-amount: (get claim-amount claim) 
          }))
        (var-set total-claims-processed (+ (var-get total-claims-processed) u1))
        (var-set total-payouts (+ (var-get total-payouts) (get claim-amount claim)))
        (print { type: "claim-paid", claim-id: claim-id, amount: (get claim-amount claim) })
        (ok true)
      )
      ERR_PAYOUT_FAILED
    )
  )
)

;; --- Utility Functions ---

(define-private (calculate-risk-score (user principal) (pool-type (string-ascii 32)))
  ;; Simplified risk calculation - in production would use more sophisticated algorithms
  (let ((base-risk u50)) ;; Base risk score of 50
    (if (is-eq pool-type "health")
      (+ base-risk u10) ;; Health insurance has higher base risk
      (if (is-eq pool-type "property")
        (+ base-risk u5)
        base-risk
      )
    )
  )
)

(define-private (calculate-premium (coverage-amount uint) (base-rate uint) (risk-score uint))
  (let ((risk-multiplier (+ u100 risk-score))) ;; Risk score adds to base 100%
    (/ (* (* coverage-amount base-rate) risk-multiplier) u1000000) ;; Normalize
  )
)

;; --- Read-Only Functions ---

(define-read-only (get-pool-details (pool-id uint))
  (map-get? insurance-pools pool-id)
)

(define-read-only (get-policy-details (policy-id uint))
  (map-get? pool-policies policy-id)
)

(define-read-only (get-claim-details (claim-id uint))
  (map-get? insurance-claims claim-id)
)

(define-read-only (get-validator-info (validator principal))
  (map-get? validators validator)
)

(define-read-only (get-claim-validation (claim-id uint) (validator principal))
  (map-get? claim-validators { claim-id: claim-id, validator: validator })
)

(define-read-only (get-user-policy (pool-id uint) (user principal))
  (match (map-get? pool-memberships { pool-id: pool-id, member: user })
    policy-id (map-get? pool-policies policy-id)
    none
  )
)

(define-read-only (get-insurance-stats)
  (ok {
    total-pools: (var-get total-pools),
    total-claims-processed: (var-get total-claims-processed),
    total-payouts: (var-get total-payouts),
    next-pool-id: (var-get next-pool-id),
    next-claim-id: (var-get next-claim-id),
    next-policy-id: (var-get next-policy-id)
  })
)

(define-read-only (calculate-pool-health (pool-id uint))
  (match (map-get? insurance-pools pool-id)
    pool (let ((utilization-rate (if (> (get total-staked pool) u0)
                                   (/ (* (get total-coverage pool) u100) (get total-staked pool))
                                   u0)))
           (some {
             total-staked: (get total-staked pool),
             total-coverage: (get total-coverage pool),
             utilization-rate: utilization-rate,
             participant-count: (get participant-count pool)
           }))
    none
  )
)