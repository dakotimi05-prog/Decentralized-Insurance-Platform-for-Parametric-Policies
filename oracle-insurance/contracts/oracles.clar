;; oracles.clar
;; Simplified oracle registry for parametric insurance products.
;; In a real deployment, these values would be written by an off-chain
;; oracle service that aggregates trustworthy data sources.

(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u404))

;; --- Data maps -------------------------------------------------------------

(define-map flight-delays
  { flight-id: (string-ascii 32) }
  { delay-minutes: uint, updated-at: uint })

(define-map rainfall
  { location: (string-ascii 32), season-id: (string-ascii 32) }
  { millimeters: uint, updated-at: uint })

(define-map earthquakes
  { region: (string-ascii 32) }
  { magnitude-times-100: uint, updated-at: uint })

;; --- Mutating functions (oracle writes) ------------------------------------

(define-public (set-flight-delay
    (flight-id (string-ascii 32))
    (delay-minutes uint)
    (timestamp uint))
  (begin
    (map-set flight-delays
      { flight-id: flight-id }
      { delay-minutes: delay-minutes, updated-at: timestamp })
    (ok true)))

(define-public (set-rainfall
    (location (string-ascii 32))
    (season-id (string-ascii 32))
    (millimeters uint)
    (timestamp uint))
  (begin
    (map-set rainfall
      { location: location, season-id: season-id }
      { millimeters: millimeters, updated-at: timestamp })
    (ok true)))

(define-public (set-earthquake
    (region (string-ascii 32))
    (magnitude-times-100 uint)
    (timestamp uint))
  (begin
    (map-set earthquakes
      { region: region }
      { magnitude-times-100: magnitude-times-100, updated-at: timestamp })
    (ok true)))

;; --- Read-only views -------------------------------------------------------

(define-read-only (get-flight-delay (flight-id (string-ascii 32)))
  (match (map-get? flight-delays { flight-id: flight-id })
    data (ok data)
    ERR_NOT_FOUND))

(define-read-only (get-rainfall
    (location (string-ascii 32))
    (season-id (string-ascii 32)))
  (match (map-get? rainfall { location: location, season-id: season-id })
    data (ok data)
    ERR_NOT_FOUND))

(define-read-only (get-earthquake (region (string-ascii 32)))
  (match (map-get? earthquakes { region: region })
    data (ok data)
    ERR_NOT_FOUND))
