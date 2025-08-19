;; ========================================
;; NFT Fractionalization Contract
;; Split NFT ownership into tradeable fractions
;; ========================================

;; Define the original NFT and fraction tokens
(define-non-fungible-token original-nft uint)
(define-fungible-token fraction-token)

;; Data variables
(define-data-var nft-counter uint u0)
(define-data-var contract-owner principal tx-sender)
(define-data-var platform-fee uint u200) ;; 2% platform fee
(define-data-var min-fractions uint u100)
(define-data-var max-fractions uint u1000000)

;; NFT metadata and properties
(define-map nft-metadata
  { token-id: uint }
  {
    name: (string-ascii 64),
    description: (string-ascii 256),
    image-url: (string-ascii 256),
    creator: principal,
    created-at: uint,
    category: (string-ascii 32),
    rarity: uint,
    estimated-value: uint
  }
)

;; Fractionalization data
(define-map fractionalized-nfts
  { token-id: uint }
  {
    total-fractions: uint,
    price-per-fraction: uint,
    is-fractionalized: bool,
    original-owner: principal,
    vault-address: principal, ;; Where the NFT is held
    fractionalization-date: uint,
    minimum-bid-per-fraction: uint,
    buyout-threshold: uint, ;; Percentage needed for buyout (basis points)
    last-trade-price: uint,
    trading-volume: uint
  }
)

;; Fraction ownership tracking
(define-map fraction-ownership
  { owner: principal, token-id: uint }
  { fractions-owned: uint }
)

;; Trading marketplace for fractions
(define-map fraction-listings
  { token-id: uint, listing-id: uint }
  {
    seller: principal,
    fraction-amount: uint,
    price-per-fraction: uint,
    total-price: uint,
    is-active: bool,
    listed-at: uint,
    expires-at: (optional uint)
  }
)

(define-data-var listing-counter uint u0)

;; Buyout proposals
(define-map buyout-proposals
  { token-id: uint, proposal-id: uint }
  {
    proposer: principal,
    total-offer: uint,
    price-per-fraction: uint,
    expires-at: uint,
    votes-for: uint,
    votes-against: uint,
    fraction-threshold: uint,
    is-active: bool,
    executed: bool
  }
)

(define-data-var proposal-counter uint u0)

;; Voting on buyout proposals
(define-map buyout-votes
  { token-id: uint, proposal-id: uint, voter: principal }
  {
    vote: bool, ;; true = for, false = against
    fraction-weight: uint,
    voted-at: uint
  }
)

;; Revenue distribution system
(define-map revenue-pools
  { token-id: uint }
  {
    total-revenue: uint,
    revenue-per-fraction: uint,
    last-distribution: uint,
    pending-claims: uint,
    distribution-history: (list 20 { amount: uint, date: uint })
  }
)

;; Individual revenue claims
(define-map revenue-claims
  { token-id: uint, claimer: principal }
  {
    total-claimed: uint,
    last-claim: uint,
    pending-amount: uint
  }
)

;; Governance for fractionalized NFTs
(define-map governance-proposals
  { token-id: uint, gov-proposal-id: uint }
  {
    proposer: principal,
    proposal-type: (string-ascii 32), ;; "metadata-update", "revenue-distribution", etc.
    description: (string-ascii 256),
    votes-for: uint,
    votes-against: uint,
    voting-deadline: uint,
    execution-deadline: uint,
    is-active: bool,
    executed: bool,
    required-threshold: uint
  }
)

(define-data-var gov-proposal-counter uint u0)

;; Price discovery and valuation
(define-map valuation-history
  { token-id: uint, valuation-id: uint }
  {
    total-valuation: uint,
    price-per-fraction: uint,
    timestamp: uint,
    source: (string-ascii 32), ;; "trade", "appraisal", "buyout"
    volume: uint
  }
)

(define-data-var valuation-counter uint u0)

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-FRACTIONALIZED (err u409))
(define-constant ERR-NOT-FRACTIONALIZED (err u408))
(define-constant ERR-INSUFFICIENT-FRACTIONS (err u400))
(define-constant ERR-INVALID-AMOUNT (err u402))
(define-constant ERR-LISTING-INACTIVE (err u403))
(define-constant ERR-PROPOSAL-EXPIRED (err u410))
(define-constant ERR-INSUFFICIENT-THRESHOLD (err u405))
(define-constant ERR-ALREADY-VOTED (err u411))

;; Administrative functions
(define-public (set-platform-parameters (fee uint) (min-fractions-new uint) (max-fractions-new uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (<= fee u1000) ERR-INVALID-AMOUNT) ;; Max 10% fee
    (asserts! (< min-fractions-new max-fractions-new) ERR-INVALID-AMOUNT)
    
    (var-set platform-fee fee)
    (var-set min-fractions min-fractions-new)
    (var-set max-fractions max-fractions-new)
    (ok true)
  )
)

;; Mint original NFT
(define-public (mint-original-nft 
    (recipient principal) 
    (name (string-ascii 64)) 
    (description (string-ascii 256)) 
    (image-url (string-ascii 256))
    (category (string-ascii 32))
    (rarity uint)
    (estimated-value uint))
  (let ((token-id (+ (var-get nft-counter) u1)))
    (try! (nft-mint? original-nft token-id recipient))
    
    (map-set nft-metadata
      { token-id: token-id }
      {
        name: name,
        description: description,
        image-url: image-url,
        creator: tx-sender,
        created-at: block-height,
        category: category,
        rarity: rarity,
        estimated-value: estimated-value
      }
    )
    
    (var-set nft-counter token-id)
    (ok token-id)
  )
)

;; Fractionalize NFT
(define-public (fractionalize-nft 
    (token-id uint) 
    (total-fractions uint) 
    (price-per-fraction uint)
    (minimum-bid-per-fraction uint)
    (buyout-threshold uint))
  (let (
    (owner (unwrap! (nft-get-owner? original-nft token-id) ERR-NOT-FOUND))
    (existing-fractionalization (map-get? fractionalized-nfts { token-id: token-id }))
  )
    (asserts! (is-eq tx-sender owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-none existing-fractionalization) ERR-ALREADY-FRACTIONALIZED)
    (asserts! (>= total-fractions (var-get min-fractions)) ERR-INVALID-AMOUNT)
    (asserts! (<= total-fractions (var-get max-fractions)) ERR-INVALID-AMOUNT)
    (asserts! (> price-per-fraction u0) ERR-INVALID-AMOUNT)
    (asserts! (<= buyout-threshold u10000) ERR-INVALID-AMOUNT) ;; Max 100%
    
    ;; Transfer NFT to contract (vault)
    (try! (nft-transfer? original-nft token-id tx-sender (as-contract tx-sender)))
    
    ;; Create fractionalization record
    (map-set fractionalized-nfts
      { token-id: token-id }
      {
        total-fractions: total-fractions,
        price-per-fraction: price-per-fraction,
        is-fractionalized: true,
        original-owner: tx-sender,
        vault-address: (as-contract tx-sender),
        fractionalization-date: block-height,
        minimum-bid-per-fraction: minimum-bid-per-fraction,
        buyout-threshold: buyout-threshold,
        last-trade-price: price-per-fraction,
        trading-volume: u0
      }
    )
    
    ;; Give all fractions to original owner initially
    (map-set fraction-ownership
      { owner: tx-sender, token-id: token-id }
      { fractions-owned: total-fractions }
    )
    
    ;; Initialize revenue pool
    (map-set revenue-pools
      { token-id: token-id }
      {
        total-revenue: u0,
        revenue-per-fraction: u0,
        last-distribution: block-height,
        pending-claims: u0,
        distribution-history: (list)
      }
    )
    
    ;; Record initial valuation
    (record-valuation token-id (* total-fractions price-per-fraction) price-per-fraction "fractionalization" u0)
    
    (ok total-fractions)
  )
)

;; Buy fractions from original owner or other sellers
(define-public (buy-fractions (token-id uint) (fraction-amount uint) (max-price-per-fraction uint))
  (let (
    (nft-info (unwrap! (map-get? fractionalized-nfts { token-id: token-id }) ERR-NOT-FOUND))
    (current-price (get price-per-fraction nft-info))
    (total-cost (* fraction-amount current-price))
    (platform-fee-amount (/ (* total-cost (var-get platform-fee)) u10000))
    (seller-amount (- total-cost platform-fee-amount))
    (original-owner (get original-owner nft-info))
    (seller-fractions (default-to u0 
      (get fractions-owned (map-get? fraction-ownership 
        { owner: original-owner, token-id: token-id }))
    ))
    (buyer-fractions (default-to u0 
      (get fractions-owned (map-get? fraction-ownership 
        { owner: tx-sender, token-id: token-id }))
    ))
  )
    (asserts! (get is-fractionalized nft-info) ERR-NOT-FRACTIONALIZED)
    (asserts! (>= seller-fractions fraction-amount) ERR-INSUFFICIENT-FRACTIONS)
    (asserts! (<= current-price max-price-per-fraction) ERR-INVALID-AMOUNT)
    (asserts! (> fraction-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer payment
    (try! (stx-transfer? platform-fee-amount tx-sender (var-get contract-owner)))
    (try! (stx-transfer? seller-amount tx-sender original-owner))
    
    ;; Update fraction ownership
    (map-set fraction-ownership
      { owner: original-owner, token-id: token-id }
      { fractions-owned: (- seller-fractions fraction-amount) }
    )
    
    (map-set fraction-ownership
      { owner: tx-sender, token-id: token-id }
      { fractions-owned: (+ buyer-fractions fraction-amount) }
    )
    
    ;; Update trading data
    (map-set fractionalized-nfts
      { token-id: token-id }
      (merge nft-info {
        last-trade-price: current-price,
        trading-volume: (+ (get trading-volume nft-info) total-cost)
      })
    )
    
    ;; Record valuation
    (record-valuation token-id (* (get total-fractions nft-info) current-price) current-price "trade" total-cost)
    
    (ok fraction-amount)
  )
)

;; List fractions for sale
(define-public (list-fractions-for-sale 
    (token-id uint) 
    (fraction-amount uint) 
    (price-per-fraction uint)
    (duration-blocks (optional uint)))
  (let (
    (nft-info (unwrap! (map-get? fractionalized-nfts { token-id: token-id }) ERR-NOT-FOUND))
    (owner-fractions (default-to u0 
      (get fractions-owned (map-get? fraction-ownership 
        { owner: tx-sender, token-id: token-id }))
    ))
    (listing-id (+ (var-get listing-counter) u1))
  )
    (asserts! (get is-fractionalized nft-info) ERR-NOT-FRACTIONALIZED)
    (asserts! (>= owner-fractions fraction-amount) ERR-INSUFFICIENT-FRACTIONS)
    (asserts! (>= price-per-fraction (get minimum-bid-per-fraction nft-info)) ERR-INVALID-AMOUNT)
    
    (map-set fraction-listings
      { token-id: token-id, listing-id: listing-id }
      {
        seller: tx-sender,
        fraction-amount: fraction-amount,
        price-per-fraction: price-per-fraction,
        total-price: (* fraction-amount price-per-fraction),
        is-active: true,
        listed-at: block-height,
        expires-at: (match duration-blocks
          blocks (some (+ block-height blocks))
          none
        )
      }
    )
    
    (var-set listing-counter listing-id)
    (ok listing-id)
  )
)

;; Buy fractions from marketplace listing
(define-public (buy-from-listing (token-id uint) (listing-id uint) (fraction-amount uint))
  (let (
    (listing (unwrap! (map-get? fraction-listings { token-id: token-id, listing-id: listing-id }) ERR-NOT-FOUND))
    (nft-info (unwrap! (map-get? fractionalized-nfts { token-id: token-id }) ERR-NOT-FOUND))
    (seller (get seller listing))
    (total-cost (* fraction-amount (get price-per-fraction listing)))
    (platform-fee-amount (/ (* total-cost (var-get platform-fee)) u10000))
    (seller-amount (- total-cost platform-fee-amount))
    (seller-fractions (default-to u0 
      (get fractions-owned (map-get? fraction-ownership 
        { owner: seller, token-id: token-id }))
    ))
    (buyer-fractions (default-to u0 
      (get fractions-owned (map-get? fraction-ownership 
        { owner: tx-sender, token-id: token-id }))
    ))
  )
    (asserts! (get is-active listing) ERR-LISTING-INACTIVE)
    (asserts! (<= fraction-amount (get fraction-amount listing)) ERR-INSUFFICIENT-FRACTIONS)
    (asserts! (>= seller-fractions fraction-amount) ERR-INSUFFICIENT-FRACTIONS)
    
    ;; Check expiration
    (match (get expires-at listing)
      expiry (asserts! (<= block-height expiry) ERR-PROPOSAL-EXPIRED)
      true
    )
    
    ;; Transfer payment
    (try! (stx-transfer? platform-fee-amount tx-sender (var-get contract-owner)))
    (try! (stx-transfer? seller-amount tx-sender seller))
    
    ;; Update fraction ownership
    (map-set fraction-ownership
      { owner: seller, token-id: token-id }
      { fractions-owned: (- seller-fractions fraction-amount) }
    )
    
    (map-set fraction-ownership
      { owner: tx-sender, token-id: token-id }
      { fractions-owned: (+ buyer-fractions fraction-amount) }
    )
    
    ;; Update listing
    (if (is-eq fraction-amount (get fraction-amount listing))
      ;; Complete purchase - deactivate listing
      (map-set fraction-listings
        { token-id: token-id, listing-id: listing-id }
        (merge listing { is-active: false })
      )
      ;; Partial purchase - reduce amount
      (map-set fraction-listings
        { token-id: token-id, listing-id: listing-id }
        (merge listing { 
          fraction-amount: (- (get fraction-amount listing) fraction-amount),
          total-price: (* (- (get fraction-amount listing) fraction-amount) (get price-per-fraction listing))
        })
      )
    )
    
    ;; Update trading data
    (map-set fractionalized-nfts
      { token-id: token-id }
      (merge nft-info {
        last-trade-price: (get price-per-fraction listing),
        trading-volume: (+ (get trading-volume nft-info) total-cost)
      })
    )
    
    (ok fraction-amount)
  )
)

;; Propose buyout of entire NFT
(define-public (propose-buyout (token-id uint) (total-offer uint))
  (let (
    (nft-info (unwrap! (map-get? fractionalized-nfts { token-id: token-id }) ERR-NOT-FOUND))
    (total-fractions (get total-fractions nft-info))
    (price-per-fraction (/ total-offer total-fractions))
    (proposal-id (+ (var-get proposal-counter) u1))
    (voting-duration u1008) ;; ~1 week in blocks
  )
    (asserts! (get is-fractionalized nft-info) ERR-NOT-FRACTIONALIZED)
    (asserts! (> total-offer u0) ERR-INVALID-AMOUNT)
    
    ;; Escrow the buyout amount
    (try! (stx-transfer? total-offer tx-sender (as-contract tx-sender)))
    
    (map-set buyout-proposals
      { token-id: token-id, proposal-id: proposal-id }
      {
        proposer: tx-sender,
        total-offer: total-offer,
        price-per-fraction: price-per-fraction,
        expires-at: (+ block-height voting-duration),
        votes-for: u0,
        votes-against: u0,
        fraction-threshold: (get buyout-threshold nft-info),
        is-active: true,
        executed: false
      }
    )
    
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

;; Vote on buyout proposal
(define-public (vote-on-buyout (token-id uint) (proposal-id uint) (vote-for bool))
  (let (
    (proposal (unwrap! (map-get? buyout-proposals { token-id: token-id, proposal-id: proposal-id }) ERR-NOT-FOUND))
    (voter-fractions (default-to u0 
      (get fractions-owned (map-get? fraction-ownership 
        { owner: tx-sender, token-id: token-id }))
    ))
    (existing-vote (map-get? buyout-votes { token-id: token-id, proposal-id: proposal-id, voter: tx-sender }))
  )
    (asserts! (get is-active proposal) ERR-LISTING-INACTIVE)
    (asserts! (<= block-height (get expires-at proposal)) ERR-PROPOSAL-EXPIRED)
    (asserts! (> voter-fractions u0) ERR-INSUFFICIENT-FRACTIONS)
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    
    ;; Record vote
    (map-set buyout-votes
      { token-id: token-id, proposal-id: proposal-id, voter: tx-sender }
      {
        vote: vote-for,
        fraction-weight: voter-fractions,
        voted-at: block-height
      }
    )
    
    ;; Update vote totals
    (map-set buyout-proposals
      { token-id: token-id, proposal-id: proposal-id }
      (merge proposal {
        votes-for: (if vote-for 
          (+ (get votes-for proposal) voter-fractions)
          (get votes-for proposal)),
        votes-against: (if vote-for 
          (get votes-against proposal)
          (+ (get votes-against proposal) voter-fractions))
      })
    )
    
    (ok vote-for)
  )
)

;; Execute approved buyout
(define-public (execute-buyout (token-id uint) (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? buyout-proposals { token-id: token-id, proposal-id: proposal-id }) ERR-NOT-FOUND))
    (nft-info (unwrap! (map-get? fractionalized-nfts { token-id: token-id }) ERR-NOT-FOUND))
    (total-fractions (get total-fractions nft-info))
    (votes-for (get votes-for proposal))
    (threshold-needed (/ (* total-fractions (get fraction-threshold proposal)) u10000))
  )
    (asserts! (get is-active proposal) ERR-LISTING-INACTIVE)
    (asserts! (not (get executed proposal)) ERR-LISTING-INACTIVE)
    (asserts! (> block-height (get expires-at proposal)) ERR-PROPOSAL-EXPIRED)
    (asserts! (>= votes-for threshold-needed) ERR-INSUFFICIENT-THRESHOLD)
    
    ;; Transfer NFT to buyout proposer
    (try! (nft-transfer? original-nft token-id (as-contract tx-sender) (get proposer proposal)))
    
    ;; Distribute buyout proceeds to fraction holders
    (try! (distribute-buyout-proceeds token-id (get total-offer proposal)))
    
    ;; Mark NFT as no longer fractionalized
    (map-set fractionalized-nfts
      { token-id: token-id }
      (merge nft-info { is-fractionalized: false })
    )
    
    ;; Mark proposal as executed
    (map-set buyout-proposals
      { token-id: token-id, proposal-id: proposal-id }
      (merge proposal { executed: true, is-active: false })
    )
    
    (ok true)
  )
)

;; Distribute revenue to fraction holders
(define-public (distribute-revenue (token-id uint) (revenue-amount uint))
  (let (
    (nft-info (unwrap! (map-get? fractionalized-nfts { token-id: token-id }) ERR-NOT-FOUND))
    (revenue-pool (unwrap! (map-get? revenue-pools { token-id: token-id }) ERR-NOT-FOUND))
    (total-fractions (get total-fractions nft-info))
    (revenue-per-fraction (/ revenue-amount total-fractions))
  )
    (asserts! (get is-fractionalized nft-info) ERR-NOT-FRACTIONALIZED)
    (asserts! (> revenue-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer revenue to contract for distribution
    (try! (stx-transfer? revenue-amount tx-sender (as-contract tx-sender)))
    
    ;; Update revenue pool
    (let (
      (new-history (unwrap! (as-max-len? 
        (append (get distribution-history revenue-pool) { amount: revenue-amount, date: block-height }) u20) 
        ERR-INVALID-AMOUNT))
    )
      (map-set revenue-pools
        { token-id: token-id }
        {
          total-revenue: (+ (get total-revenue revenue-pool) revenue-amount),
          revenue-per-fraction: revenue-per-fraction,
          last-distribution: block-height,
          pending-claims: (+ (get pending-claims revenue-pool) revenue-amount),
          distribution-history: new-history
        }
      )
    )
    
    (ok revenue-per-fraction)
  )
)

;; Claim revenue share
(define-public (claim-revenue (token-id uint))
  (let (
    (nft-info (unwrap! (map-get? fractionalized-nfts { token-id: token-id }) ERR-NOT-FOUND))
    (revenue-pool (unwrap! (map-get? revenue-pools { token-id: token-id }) ERR-NOT-FOUND))
    (claimer-fractions (default-to u0 
      (get fractions-owned (map-get? fraction-ownership 
        { owner: tx-sender, token-id: token-id }))
    ))
    (claim-data (default-to 
      { total-claimed: u0, last-claim: u0, pending-amount: u0 }
      (map-get? revenue-claims { token-id: token-id, claimer: tx-sender })
    ))
    (claimable-amount (* claimer-fractions (get revenue-per-fraction revenue-pool)))
  )
    (asserts! (get is-fractionalized nft-info) ERR-NOT-FRACTIONALIZED)
    (asserts! (> claimer-fractions u0) ERR-INSUFFICIENT-FRACTIONS)
    (asserts! (> claimable-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer claimable amount
    (try! (as-contract (stx-transfer? claimable-amount tx-sender tx-sender)))
    
    ;; Update claim record
    (map-set revenue-claims
      { token-id: token-id, claimer: tx-sender }
      {
        total-claimed: (+ (get total-claimed claim-data) claimable-amount),
        last-claim: block-height,
        pending-amount: u0
      }
    )
    
    ;; Update revenue pool
    (map-set revenue-pools
      { token-id: token-id }
      (merge revenue-pool {
        pending-claims: (- (get pending-claims revenue-pool) claimable-amount)
      })
    )
    
    (ok claimable-amount)
  )
)

;; Helper function to distribute buyout proceeds
(define-private (distribute-buyout-proceeds (token-id uint) (total-amount uint))
  ;; In a full implementation, this would iterate through all fraction holders
  ;; For now, we mark it as available for claiming
  (let (
    (revenue-pool (unwrap! (map-get? revenue-pools { token-id: token-id }) ERR-NOT-FOUND))
    (nft-info (unwrap! (map-get? fractionalized-nfts { token-id: token-id }) ERR-NOT-FOUND))
    (total-fractions (get total-fractions nft-info))
    (amount-per-fraction (/ total-amount total-fractions))
  )
    (map-set revenue-pools
      { token-id: token-id }
      (merge revenue-pool {
        total-revenue: (+ (get total-revenue revenue-pool) total-amount),
        revenue-per-fraction: amount-per-fraction,
        pending-claims: (+ (get pending-claims revenue-pool) total-amount)
      })
    )
    (ok true)
  )
)

;; Helper function to record valuation
(define-private (record-valuation (token-id uint) (total-val uint) (price-per-fraction uint) (source (string-ascii 32)) (volume uint))
  (let ((valuation-id (+ (var-get valuation-counter) u1)))
    (map-set valuation-history
      { token-id: token-id, valuation-id: valuation-id }
      {
        total-valuation: total-val,
        price-per-fraction: price-per-fraction,
        timestamp: block-height,
        source: source,
        volume: volume
      }
    )
    (var-set valuation-counter valuation-id)
    true
  )
)

;; Read-only functions
(define-read-only (get-nft-metadata (token-id uint))
  (map-get? nft-metadata { token-id: token-id })
)

(define-read-only (get-fractionalization-info (token-id uint))
  (map-get? fractionalized-nfts { token-id: token-id })
)

(define-read-only (get-fraction-balance (owner principal) (token-id uint))
  (default-to u0 
    (get fractions-owned (map-get? fraction-ownership { owner: owner, token-id: token-id }))
  )
)

(define-read-only (get-listing (token-id uint) (listing-id uint))
  (map-get? fraction-listings { token-id: token-id, listing-id: listing-id })
)

(define-read-only (get-buyout-proposal (token-id uint) (proposal-id uint))
  (map-get? buyout-proposals { token-id: token-id, proposal-id: proposal-id })
)

(define-read-only (get-revenue-pool (token-id uint))
  (map-get? revenue-pools { token-id: token-id })
)

(define-read-only (get-revenue-claims (token-id uint) (claimer principal))
  (map-get? revenue-claims { token-id: token-id, claimer: claimer })
)

(define-read-only (get-valuation-history (token-id uint) (valuation-id uint))
  (map-get? valuation-history { token-id: token-id, valuation-id: valuation-id })
)

(define-read-only (get-contract-info)
  {
    total-nfts: (var-get nft-counter),
    platform-fee: (var-get platform-fee),
    min-fractions: (var-get min-fractions),
    max-fractions: (var-get max-fractions),
    total-listings: (var-get listing-counter),
    total-proposals: (var-get proposal-counter),
    owner: (var-get contract-owner)
  }
)