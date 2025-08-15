;; peer-to-peer-insurance.clar
;;
;; A decentralized insurance system with community-driven claims processing
;; and automated risk assessment

;; --- Constants and Error Codes ---
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-NOT-FOUND (err u301))
(define-constant ERR-INSUFFICIENT-BALANCE (err u302))
(define-constant ERR-INVALID-AMOUNT (err u303))
(define-constant ERR-POOL-FULL (err u304))
(define-constant ERR-CLAIM-EXPIRED (err u305))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u306))
(define-constant ERR-INSUFFICIENT-VALIDATORS (err u307))
(define-constant ERR-ALREADY-VALIDATED (err u308))
(define-constant ERR-INVALID-RISK-SCORE (err u309))
(define-constant ERR-PAYOUT-FAILED (err u310))

(define-constant MIN-POOL-STAKE u1000000) ;; 1000 STX in microSTX
(define-constant MIN-VALIDATOR-STAKE u500000) ;; 500 STX in microSTX
(define-constant MAX-POOL-SIZE u100) ;; Maximum participants per pool
(define-constant CLAIM-VALIDATION-PERIOD u1008) ;; ~1 week in blocks
(define-constant MIN-VALIDATORS-REQUIRED u3)
(define-constant VALIDATOR-CONSENSUS-THRESHOLD u66) ;; 66% agreement needed
(define-constant PREMIUM-RATE-BASE u1000) ;; 10% annual premium base rate

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
  pool-type: (string-ascii 32),
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
  risk-score: uint,
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
  status: (string-ascii 16),
  payout-amount: uint
})

;; Claim validators
(define-map claim-validators { claim-id: uint, validator: principal } {
  stake-amount: uint,
  vote: (optional bool),
  vote-block: uint,
  evidence-reviewed: bool
})

;; Validator registry
(define-map validators principal {
  stake-amount: uint,
  claims-validated: uint,
  accuracy-score: uint,
  total-rewards: uint,
  active: bool,
  specialization: (string-ascii 32)
})

;; Pool membership tracking
(define-map pool-memberships { pool-id: uint, member: principal } uint)

;; Risk assessment data
(define-map risk-factors { pool-type: (string-ascii 32), factor: (string-ascii 32) } uint)

;; --- Pool Management ---

(define-public (create-insurance-pool 
  (pool-name (string-ascii 64))
  (pool-type (string-ascii 32))
  (max-coverage-per-claim uint)
  (base-premium-rate uint))
  (let ((pool-id (var-get next-pool-id)))
    (asserts! (> max-coverage-per-claim u0) ERR-INVALID-AMOUNT)
    (asserts! (and (> base-premium-rate u0) (<= base-premium-rate u5000)) ERR-INVALID-AMOUNT)

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
  (let ((pool (unwrap! (map-get? insurance-pools pool-id) ERR-NOT-FOUND))
        (policy-id (var-get next-policy-id)))
    (asserts! (get active pool) ERR-NOT-FOUND)
    (asserts! (>= stake-amount MIN-POOL-STAKE) ERR-INSUFFICIENT-BALANCE)
    (asserts! (<= coverage-amount (get max-coverage-per-claim pool)) ERR-INVALID-AMOUNT)
    (asserts! (< (get participant-count pool) MAX-POOL-SIZE) ERR-POOL-FULL)
    (asserts! (is-none (map-get? pool-memberships { pool-id: pool-id, member: tx-sender })) ERR-NOT-AUTHORIZED)

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
    (asserts! (>= stake-amount MIN-VALIDATOR-STAKE) ERR-INSUFFICIENT-BALANCE)
    (asserts! (is-none (map-get? validators tx-sender)) ERR-NOT-AUTHORIZED)

    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))

    (map-set validators tx-sender {
      stake-amount: stake-amount,
      claims-validated: u0,
      accuracy-score: u100,
      total-rewards: u0,
      active: true,
      specialization: specialization
    })

    (print { type: "validator-registered", validator: tx-sender, specialization: specialization })
    (ok true)
  )
)

(define-public (increase-validator-stake (additional-amount uint))
  (let ((validator-info (unwrap! (map-get? validators tx-sender) ERR-NOT-FOUND)))
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
        (pool (unwrap! (map-get? insurance-pools pool-id) ERR-NOT-FOUND))
        (policy-id (unwrap! (map-get? pool-memberships { pool-id: pool-id, member: tx-sender }) ERR-NOT-FOUND))
        (policy (unwrap! (map-get? pool-policies policy-id) ERR-NOT-FOUND)))

    (asserts! (get active policy) ERR-NOT-FOUND)
    (asserts! (<= claim-amount (get coverage-amount policy)) ERR-INVALID-AMOUNT)
    (asserts! (<= claim-amount (get max-coverage-per-claim pool)) ERR-INVALID-AMOUNT)

    (map-set insurance-claims claim-id {
      claimant: tx-sender,
      pool-id: pool-id,
      policy-id: policy-id,
      claim-amount: claim-amount,
      claim-type: claim-type,
      description: description,
      evidence-hash: evidence-hash,
      submission-block: block-height,
      validation-deadline: (+ block-height CLAIM-VALIDATION-PERIOD),
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
  (let ((claim (unwrap! (map-get? insurance-claims claim-id) ERR-NOT-FOUND))
        (validator-info (unwrap! (map-get? validators tx-sender) ERR-NOT-FOUND)))
    (asserts! (get active validator-info) ERR-NOT-AUTHORIZED)
    (asserts! (< block-height (get validation-deadline claim)) ERR-CLAIM-EXPIRED)
    (asserts! (is-eq (get status claim) "pending") ERR-CLAIM-ALREADY-PROCESSED)
    (asserts! (is-none (map-get? claim-validators { claim-id: claim-id, validator: tx-sender })) ERR-ALREADY-VALIDATED)
    (asserts! (<= stake-amount (get stake-amount validator-info)) ERR-INSUFFICIENT-BALANCE)

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

      ;; Update validator stats
      (map-set validators tx-sender
        (merge validator-info {
          claims-validated: (+ (get claims-validated validator-info) u1)
        }))

      ;; Check if we have enough validators and can process the claim
      (if (>= new-validators-assigned MIN-VALIDATORS-REQUIRED)
        (process-claim-if-ready claim-id)
        (ok true)
      )
    )
  )
)

(define-private (process-claim-if-ready (claim-id uint))
  (let ((claim (unwrap-panic (map-get? insurance-claims claim-id))))
    (if (>= (get validators-assigned claim) MIN-VALIDATORS-REQUIRED)
      (let ((approval-rate (/ (* (get approved-validator-stake claim) u100) (get total-validator-stake claim))))
        (if (>= approval-rate VALIDATOR-CONSENSUS-THRESHOLD)
          (begin
            ;; Approve and process payout
            (map-set insurance-claims claim-id (merge claim { status: "approved" }))
            (process-payout claim-id)
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
        (match (as-contract (stx-transfer? (get claim-amount claim) tx-sender (get claimant claim)))
          success (begin
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
          error ERR-PAYOUT-FAILED
        )
      )
      ERR-PAYOUT-FAILED
    )
  )
)

;; --- Premium Collection ---

(define-public (pay-premium (policy-id uint))
  (let ((policy (unwrap! (map-get? pool-policies policy-id) ERR-NOT-FOUND))
        (pool (unwrap! (map-get? insurance-pools (get pool-id policy)) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get policyholder policy)) ERR-NOT-AUTHORIZED)
    (asserts! (get active policy) ERR-NOT-FOUND)

    ;; Calculate blocks since last payment (simplified monthly payment)
    (let ((blocks-since-payment (- block-height (get last-premium-block policy)))
          (monthly-blocks u4320) ;; Approximately 30 days
          (monthly-premium (/ (get premium-paid policy) u12)))

      (asserts! (>= blocks-since-payment monthly-blocks) ERR-INVALID-AMOUNT)

      (try! (stx-transfer? monthly-premium tx-sender (as-contract tx-sender)))

      (map-set pool-policies policy-id
        (merge policy {
          last-premium-block: block-height
        }))

      (print { type: "premium-paid", policy-id: policy-id, amount: monthly-premium })
      (ok true)
    )
  )
)

;; --- Utility Functions ---

(define-private (calculate-risk-score (user principal) (pool-type (string-ascii 32)))
  ;; Simplified risk calculation
  (let ((base-risk u50))
    (if (is-eq pool-type "health")
      (+ base-risk u10)
      (if (is-eq pool-type "property")
        (+ base-risk u5)
        base-risk
      )
    )
  )
)

(define-private (calculate-premium (coverage-amount uint) (base-rate uint) (risk-score uint))
  (let ((risk-multiplier (+ u100 risk-score)))
    (/ (* (* coverage-amount base-rate) risk-multiplier) u1000000)
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

(define-read-only (get-pool-health (pool-id uint))
  (match (map-get? insurance-pools pool-id)
    pool (let ((utilization-rate (if (> (get total-staked pool) u0)
                                   (/ (* (get total-coverage pool) u100) (get total-staked pool))
                                   u0)))
           (ok {
             total-staked: (get total-staked pool),
             total-coverage: (get total-coverage pool),
             utilization-rate: utilization-rate,
             participant-count: (get participant-count pool),
             active: (get active pool)
           }))
    (err ERR-NOT-FOUND)
  )
)

(define-read-only (is-claim-claimable (claim-id uint))
  (match (map-get? insurance-claims claim-id)
    claim (ok (and 
            (is-eq (get status claim) "approved")
            (is-eq (get payout-amount claim) u0)))
    (err ERR-NOT-FOUND)
  )
)

(define-read-only (get-validator-performance (validator principal))
  (match (map-get? validators validator)
    validator-info (ok {
      stake-amount: (get stake-amount validator-info),
      claims-validated: (get claims-validated validator-info),
      accuracy-score: (get accuracy-score validator-info),
      total-rewards: (get total-rewards validator-info),
      active: (get active validator-info),
      specialization: (get specialization validator-info)
    })
    (err ERR-NOT-FOUND)
  )
)