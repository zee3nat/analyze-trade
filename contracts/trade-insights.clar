;; trade-insights.clar
;; A decentralized platform for trade data analysis and market insights
;; This contract manages registration, validation, and access control
;; for trade-related datasets, ensuring data transparency and market intelligence

;; ============================================
;; Error constants
;; ============================================
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-UNKNOWN-DATASET (err u101))
(define-constant ERR-UNKNOWN-RESEARCHER (err u102))
(define-constant ERR-ALREADY-REGISTERED (err u103))
(define-constant ERR-INVALID-ACCESS-TYPE (err u104))
(define-constant ERR-ACCESS-DENIED (err u105))
(define-constant ERR-INVALID-PARAMETERS (err u106))
(define-constant ERR-NO-ACTIVE-VOTE (err u107))
(define-constant ERR-ALREADY-VOTED (err u108))
(define-constant ERR-INVALID-VOTE (err u109))

;; ============================================
;; Access types
;; ============================================
(define-constant ACCESS-TYPE-OPEN u1)
(define-constant ACCESS-TYPE-PAID u2)
(define-constant ACCESS-TYPE-PERMISSIONED u3)

;; ============================================
;; Data maps and variables
;; ============================================

;; Contract administrator
(define-data-var contract-owner principal tx-sender)

;; Researcher registry
(define-map researchers
  { researcher-id: principal }
  {
    name: (string-ascii 100),
    institution: (string-ascii 100),
    credentials: (string-ascii 255),
    registration-time: uint,
    dataset-count: uint
  }
)

;; Dataset registry
(define-map datasets
  { dataset-id: (string-ascii 36) }
  {
    title: (string-ascii 100),
    data-type: (string-ascii 50),
    location: (string-ascii 100),
    date-collected: uint,
    methodology: (string-ascii 255),
    data-hash: (buff 32),
    researcher-id: principal,
    access-type: uint,
    access-price: uint,
    citation-count: uint,
    registered-at: uint,
    verified: bool
  }
)

;; Access permissions for permissioned datasets
(define-map dataset-permissions
  { dataset-id: (string-ascii 36), user: principal }
  { 
    has-access: bool,
    granted-at: uint,
    granted-by: principal
  }
)

;; Citations tracking
(define-map dataset-citations
  { dataset-id: (string-ascii 36), citing-researcher: principal }
  { 
    citation-time: uint,
    citation-context: (string-ascii 255)
  }
)

;; Governance proposals
(define-map governance-proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    proposed-at: uint,
    voting-ends-at: uint,
    yes-votes: uint,
    no-votes: uint,
    status: (string-ascii 20)  ;; "active", "passed", "rejected"
  }
)

;; Track votes
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  { vote: bool }
)

;; Track the next proposal ID
(define-data-var next-proposal-id uint u1)

;; ============================================
;; Private functions
;; ============================================


;; Validates the access type
(define-private (is-valid-access-type (access-type uint))
  (or
    (is-eq access-type ACCESS-TYPE-OPEN)
    (is-eq access-type ACCESS-TYPE-PAID)
    (is-eq access-type ACCESS-TYPE-PERMISSIONED)
  )
)

;; ============================================
;; Read-only functions
;; ============================================

;; Get researcher information
(define-read-only (get-researcher (researcher-id principal))
  (map-get? researchers { researcher-id: researcher-id })
)

;; Get dataset information
(define-read-only (get-dataset (dataset-id (string-ascii 36)))
  (map-get? datasets { dataset-id: dataset-id })
)

;; Get access permission details
(define-read-only (get-access-permission (dataset-id (string-ascii 36)) (user principal))
  (map-get? dataset-permissions { dataset-id: dataset-id, user: user })
)

;; Get citation information
(define-read-only (get-citation (dataset-id (string-ascii 36)) (citing-researcher principal))
  (map-get? dataset-citations { dataset-id: dataset-id, citing-researcher: citing-researcher })
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

;; Check if a user has voted on a proposal
(define-read-only (has-voted (proposal-id uint) (voter principal))
  (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

;; ============================================
;; Public functions
;; ============================================



;; Verify a dataset (can only be done by contract owner for now, could be extended to a verification committee)
(define-public (verify-dataset (dataset-id (string-ascii 36)))
  (let (
    (dataset (map-get? datasets { dataset-id: dataset-id }))
    (current-owner (var-get contract-owner))
  )
    ;; Ensure caller is authorized
    (asserts! (is-eq tx-sender current-owner) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-none dataset)) ERR-UNKNOWN-DATASET)
    
    ;; Update dataset verification status
    (map-set datasets
      { dataset-id: dataset-id }
      (merge (unwrap! dataset ERR-UNKNOWN-DATASET)
        { verified: true }
      )
    )
    
    (ok true)
  )
)

;; Grant access to a permissioned dataset
(define-public (grant-dataset-access (dataset-id (string-ascii 36)) (user principal))
  (let ((dataset (map-get? datasets { dataset-id: dataset-id })))
    ;; Validate dataset exists and caller is the owner
    (asserts! (not (is-none dataset)) ERR-UNKNOWN-DATASET)
    (asserts! (is-eq (get researcher-id (unwrap! dataset ERR-UNKNOWN-DATASET)) tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Record the access permission
    (map-set dataset-permissions
      { dataset-id: dataset-id, user: user }
      {
        has-access: true,
        granted-at: block-height,
        granted-by: tx-sender
      }
    )
    
    (ok true)
  )
)

;; Access a paid dataset by paying the required amount
(define-public (access-paid-dataset (dataset-id (string-ascii 36)))
  (let (
    (dataset (map-get? datasets { dataset-id: dataset-id }))
  )
    ;; Validate dataset exists and is of paid type
    (asserts! (not (is-none dataset)) ERR-UNKNOWN-DATASET)
    (asserts! (is-eq (get access-type (unwrap! dataset ERR-UNKNOWN-DATASET)) ACCESS-TYPE-PAID) ERR-INVALID-ACCESS-TYPE)
    
    ;; Transfer payment from user to dataset owner
    (let (
      (dataset-info (unwrap! dataset ERR-UNKNOWN-DATASET))
      (price (get access-price dataset-info))
      (owner (get researcher-id dataset-info))
    )
      ;; Process payment
      (try! (stx-transfer? price tx-sender owner))
      
      ;; Record the access permission
      (map-set dataset-permissions
        { dataset-id: dataset-id, user: tx-sender }
        {
          has-access: true,
          granted-at: block-height,
          granted-by: owner
        }
      )
      
      (ok true)
    )
  )
)


;; Create a governance proposal
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (voting-duration uint))
  (let (
    (researcher-info (get-researcher tx-sender))
    (proposal-id (var-get next-proposal-id))
  )
    ;; Validate caller is a registered researcher
    (asserts! (not (is-none researcher-info)) ERR-UNKNOWN-RESEARCHER)
    
    ;; Record the proposal
    (map-set governance-proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        proposer: tx-sender,
        proposed-at: block-height,
        voting-ends-at: (+ block-height voting-duration),
        yes-votes: u0,
        no-votes: u0,
        status: "active"
      }
    )
    
    ;; Increment proposal ID
    (var-set next-proposal-id (+ proposal-id u1))
    
    (ok proposal-id)
  )
)

;; Finalize a proposal that has reached its voting deadline
(define-public (finalize-proposal (proposal-id uint))
  (let (
    (proposal (map-get? governance-proposals { proposal-id: proposal-id }))
  )
    ;; Validate proposal exists
    (asserts! (not (is-none proposal)) ERR-INVALID-PARAMETERS)
    
    (let ((proposal-info (unwrap! proposal ERR-INVALID-PARAMETERS)))
      ;; Ensure proposal voting period has ended and proposal is still active
      (asserts! (> block-height (get voting-ends-at proposal-info)) ERR-INVALID-PARAMETERS)
      (asserts! (is-eq (get status proposal-info) "active") ERR-INVALID-PARAMETERS)
      
      ;; Determine outcome and update status
      (let (
        (yes-votes (get yes-votes proposal-info))
        (no-votes (get no-votes proposal-info))
        (new-status (if (> yes-votes no-votes) "passed" "rejected"))
      )
        (map-set governance-proposals
          { proposal-id: proposal-id }
          (merge proposal-info { status: new-status })
        )
        
        (ok true)
      )
    )
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (let ((current-owner (var-get contract-owner)))
    (asserts! (is-eq tx-sender current-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)