# Contrail -- Phase 1 Build Specification

> Working title. Rename freely.

You are building **Phase 1** of a native iOS application called Contrail. Read this
entire document, then produce a plan. Do not begin implementation until the plan is
reviewed.

Accompanying documents: `README.md` (product overview) and `ROADMAP.md` (all four
phases). Read both for context. This document is the authoritative scope for Phase 1.

---

## 0. Non-negotiable quality bar

**Every feature that ships in Phase 1 must be fully functional.**

- No stubs. No `// TODO: implement`. No placeholder views. No mock data paths left
  in the shipping build. No "coming soon" labels.
- The target is working alpha/beta quality software. Rough edges in polish, layout,
  and visual design are acceptable and expected. Non-functional code is not.
- If a view exists in the app, tapping it produces real behavior driven by real data.
- **If any feature in this spec is too large to complete to that bar in the current
  effort, flag it during the planning phase and propose it as its own numbered
  subphase (1.1, 1.2, ...).** Do not silently descope. Do not partially implement.
  It is strictly better to defer a whole feature than to ship half of one.
- Refinement across iterations is expected and welcome. Placeholders are not.

State explicitly in your plan which features you intend to complete in this pass and
which you are proposing to defer, with reasoning.

---

## 1. Platform and language

- Swift, SwiftUI. Native iOS only. No Capacitor, no React Native, no WebView shells.
- Minimum deployment target: iOS 17 unless you have a concrete argument otherwise.
  Raise it in planning if you do.
- **iPhone and iPad are both first-class.** iPad must not be a scaled iPhone layout.
- Architectural rule: **no view may branch on device type.** Layout adapts via size
  classes and a single top-level layout container that composes the same child views
  differently. iPhone gets a stacked single-column dashboard; iPad gets a
  `NavigationSplitView` with the map as primary canvas, metrics in a sidebar, and a
  media strip. Same views, different composition.
- Package structure: core logic in a local Swift Package (testable, no UIKit/SwiftUI
  dependency), thin app target on top.

---

## 2. Architecture

Four modules. Build them in this order.

### 2.1 `FlightPlan`
Immutable description of the flight, resolved before departure.

- Origin and destination airports (ICAO/IATA, coordinates, elevation, timezone).
- Great circle path between them, with the ability to compute along-track distance,
  cross-track error, and fractional progress for any given position.
- Scheduled departure and arrival, scheduled block time.
- Aircraft type (ICAO code) and, where available, registration.
- Filed route waypoint string when available (see §5.3).

Great circle math must be correct at flight distances. Use proper spherical
(or better, WGS-84 ellipsoidal) formulas. Cross-track error must be signed so that
left/right of course is distinguishable.

### 2.2 `Sensors`
Wraps the device's sensors into a single unified stream of timestamped samples.

**Define a `SensorSource` protocol as the boundary.** Two conforming implementations
are required in Phase 1:

1. `LiveSensorSource` -- CoreLocation, CoreMotion, CMAltimeter.
2. `ReplaySensorSource` -- plays back a recorded flight log file at configurable
   speed, including faster-than-realtime.

The replay source is not optional and is not a testing nicety. Dead reckoning,
turbulence estimation, and phase classification cannot be developed or verified
without it. Ship a bundled sample log so the app is exercisable on a desk.

Raw channels to acquire:

| Channel | Source | Notes |
|---|---|---|
| Latitude, longitude | CoreLocation | |
| GPS altitude | CoreLocation | ellipsoidal; note the datum |
| Horizontal / vertical accuracy | CoreLocation | these are the only fix-quality signals iOS gives you |
| CL speed, CL course | CoreLocation | treat as sanity check only, see below |
| Barometric pressure | CMAltimeter | this is **cabin** pressure, not ambient |
| User acceleration (3-axis) | CMDeviceMotion | gravity already separated |
| Gravity vector | CMDeviceMotion | |
| Attitude quaternion | CMDeviceMotion | |
| Rotation rate | CMDeviceMotion | |

**Critical:** CoreLocation's `speed` and `course` are filtered for terrestrial
motion and are unreliable at 500 knots. Compute groundspeed and true course yourself
from successive fixes using proper geodesic inverse. Display CoreLocation's values
separately, labeled as such, for comparison.

**iOS exposes no GNSS detail.** There is no satellite count, no per-constellation
breakdown, no DOP, no raw pseudoranges. Do not attempt to obtain these. Instead
surface what *is* inferable as a fix-quality panel: horizontal and vertical accuracy
and their trend, dropout intervals, time-to-reacquire after a loss, and time since
last valid fix. An external Bluetooth NMEA receiver is a future consideration --
design `SensorSource` so such a source could be added without touching the estimator.

### 2.3 `Estimator`
Consumes the sensor stream and produces a single output struct. **Define this struct
first. It is the contract everything downstream depends on.**

Required contents:

*Position and motion*
- Fused position with a confidence radius
- Groundspeed (computed), true course, track angle rate (rate of turn)
- GPS altitude, vertical speed (derived from altitude deltas)
- Longitudinal acceleration

*Cabin environment*
- Cabin pressure, cabin pressure altitude, pressurization rate

*Turbulence*
- Current measured intensity (see §4)

*Route-relative*
- Along-track distance flown and remaining
- Signed cross-track error against the filed route
- Fractional progress
- Nearest city with bearing and distance
- ETA with variance, schedule delta (ahead/behind block time)

*Meta*
- Flight phase (taxi, takeoff, climb, cruise, descent, landing)
- Per-channel data source and staleness

**Dead reckoning is required, not optional.** GPS drops constantly in a cabin --
aisle seats, wing shadow, banking away from the satellites. The estimator maintains
two independent position estimates: the GPS fix (high confidence, intermittent) and
a dead-reckoned position propagated along the filed route from departure time and
recent groundspeed (always available, degrading with time since last fix). Fuse
them, and expose the confidence radius so it visibly grows during GPS loss and snaps
tight on reacquisition.

ETA must be a distribution, not a point. Fold in the current groundspeed residual
against planned. Display as e.g. "38 min, ±6, running 11 min ahead of block."

### 2.4 `Statistics`
Time-windowed statistics over every numeric channel.

- **One ring buffer per channel at full sample rate.** All windows compute off the
  same buffer. Do not build separate accumulators per window -- adding a window
  later must be a configuration change, not new code.
- Windows: 1, 5, and 30 minutes, plus whole-flight.
- Per window: mean, min, max, standard deviation, and percentiles (p50, p95, p99).
- **Rolling min/max must use a monotonic deque** for amortized O(1) per sample. A
  naive O(n) rescan over a 30-minute window at high sample rate will destroy the
  battery. This is the one piece of the app where the algorithm genuinely matters.
- **Local extrema are a separate feature from rolling max.** Implement peak
  detection with a prominence threshold, producing discrete labeled events with
  timestamps and positions -- "the three biggest bumps of this flight" -- which are
  tappable and locate on the track. This is a different data structure and a
  different user-facing feature than a windowed maximum.

---

## 3. Adaptive sampling

Two rates, deliberately decoupled.

**Sensor rate is fixed and high.** Run CMDeviceMotion at 50-100 Hz continuously. It
is the cheapest sensor on the device and it is the trigger mechanism -- you cannot
detect a bump with a sensor you have turned down.

**Logging rate is what varies.**

- Per-phase floor rates: high during taxi, takeoff, climb, descent, and landing;
  low at cruise (30-60 s between records is fine).
- **Event-triggered burst:** when filtered vertical acceleration variance exceeds an
  adaptive threshold, log at full rate for a hold-off period, then decay back.
- **Pre-trigger capture is mandatory.** On trigger, flush the preceding several
  seconds from the ring buffer. A naive trigger loses the leading edge of the event,
  which is the most interesting part.
- The threshold is a multiple of a rolling baseline of vertical acceleration
  variance, not a fixed constant, so it self-calibrates to the airframe and to where
  the passenger is sitting relative to the wing.

**Phase classifier** drives the floor rates. Inputs you already have: groundspeed,
vertical rate, pressurization rate, altitude. Classify into taxi, takeoff, climb,
cruise, descent, landing. Pressurization rate is the strongest early descent signal
-- it typically leads the cabin announcement.

---

## 4. Turbulence

Two halves, and the comparison between them is the marquee feature of the product.

### 4.1 Measured
Estimate turbulence intensity from the device accelerometers.

- Rotate user acceleration into the world frame using the attitude quaternion. Work
  on the vertical axis.
- High-pass at 3-4 Hz. Handling motion (picking the phone up, typing, adjusting)
  lives below ~3 Hz and presents as large correlated tilt changes lasting one to two
  seconds. Turbulence is broadband stochastic energy extending into the 5-20 Hz band
  where a human hand cannot go.
- **Gate on attitude stability.** If the attitude quaternion is changing materially
  during a window, discard that window entirely. This is the primary discriminator
  against handling motion, and it is cheap.
- Report as **EDR^(1/3)** (cube root of eddy dissipation rate), derived from the RMS
  of the filtered vertical acceleration over a short window. This is the same metric
  and the same units airlines and pilots use, so the readout maps onto light /
  moderate / severe categories people already understand.
- **Be honest in the UI about what is being measured.** The sensor is on a tray
  table or in a lap, not bolted to the airframe, so there is an unknown transfer
  function in between. Present this as a calibrated-relative intensity trace, with
  the absolute-scale caveat stated in the interface, not buried.

### 4.2 Forecast
NOAA Graphical Turbulence Guidance (GTG).

- GTG is a **3D grid**: latitude, longitude, and flight level. Interpolation must be
  trilinear -- altitude interpolation is not optional, since turbulence forecasts
  vary strongly with flight level.
- Native format is GRIB2. GRIB2 parsing on-device is a rabbit hole. **Do a
  server-side or pre-flight-side slice**: fetch the grid, cut the route corridor,
  re-emit as a compact packed binary or flat JSON that the app reads directly. Keep
  the phone dumb.
- If this pre-processing step is beyond the current effort, this is exactly the kind
  of feature to flag as a subphase. Do not ship a forecast panel with no forecast in
  it.

### 4.3 Comparison
Every logged sample carries the forecast value interpolated at that position, time,
and flight level **alongside** the measured value. The flight log is therefore not
just a track -- it is a forecast-verification record. Provide a live and post-flight
view plotting predicted against measured along the track, with the residual.

---

## 5. Pre-flight resolution and caching

One screen. User enters a flight number and date. The app resolves and caches
everything needed for a fully offline flight, and reports readiness per asset with
an explicit verified state -- not a hopeful one.

### 5.1 Flight resolution
- Flight number and date to: origin, destination, scheduled times, aircraft ICAO
  type, registration where available.
- Use a flight data API. Free tiers are thin (aviationstack is on the order of 100
  requests/month free) but a personal-use flight costs one or two calls. Put the
  provider behind a protocol so it can be swapped.

### 5.2 Map corridor
- **MapLibre Native for iOS** as the renderer. Not MapKit -- MapKit's offline
  behavior is opportunistic, uncontrollable, and unverifiable, which is
  disqualifying for an app whose entire premise is working with no connectivity.
  Not Google Maps -- their terms prohibit tile pre-caching.
- **PMTiles (Protomaps)** as the tile source. A single-file archive, range-requested,
  no tile server, no API key.
- Cut a corridor along the great circle wide enough to also cover the divert airport
  set from §5.4. Download it, verify byte-completeness, and report it as verified.

### 5.3 Route and waypoints
- Filed route (the actual waypoint string) is public via FAA SWIM and appears in
  FlightAware AeroAPI's filed-route field, typically within a few hours of
  departure. Fetch it if available.
- The filed route is not the flown route. ATC reroutes and direct-to clearances are
  routine. **This is a feature:** cross-track error against the filed route becomes
  a live "we have been rerouted" indicator.
- Bundle the FAA NASR enroute fix and navaid database as a fallback and as a
  standalone feature: display the nearest fix, the next fix along track, and a
  running scroll of fixes as they are crossed. (The names are a delight -- this is
  a genuinely charming feature in its own right.)

### 5.4 Divert planning
- Bundle the OurAirports open dataset (worldwide, includes runway length and
  surface). No API required.
- Pre-compute the candidate set along the corridor, **filtered by runway length
  against the resolved aircraft type.** A 737 needs roughly 7,000 ft; a 2,000 ft
  grass strip is noise. This filter is the whole point, and it is why aircraft type
  matters beyond trivia.
- In flight, the metric is **glide reach, not straight-line distance.** A clean jet
  glides roughly 17:1, so from FL380 the reachable radius is on the order of 120 nm,
  shrinking with altitude. Display the reachable set, with those inside glide range
  distinguished from those outside.

### 5.5 Airspace jurisdiction
- Bundle ARTCC/FIR boundary polygons (FAA publishes US ARTCC polygons; open world
  FIR datasets exist).
- Point-in-polygon against current position, displaying e.g. "Denver Center (ZDV)"
  and updating on crossings.
- Center-level only. Sector-level boundaries are altitude-stratified and shift with
  traffic flow -- out of scope.

### 5.6 Place database
- Bundle a populated-places dataset with coordinates and population.
- Nearest city must always be reported **with bearing and distance**, because over
  the Great Basin the nearest city may be 90 miles away and "near Ely, Nevada" is a
  lie. Format: "42 mi N of Ely, Nevada."

---

## 6. Logging and iCloud

**Hard requirement: the user owns their data and can get at it from any device.**

- **Local storage is the source of truth. iCloud is replication.** Sync will not
  happen in the air; it queues and pushes on landing. Design accordingly.
- One file per flight in the app's iCloud Documents container.
- **Newline-delimited JSON, append-only.** Line-oriented and append-safe so that a
  crash, a thermal shutdown, or a dead battery mid-flight costs at most the last
  line, not the flight.
- **A manifest per flight** capturing everything fetched pre-flight: resolved flight
  data, aircraft type, filed route, forecast grid slice, app version, schema
  version. A log must be fully self-describing years later with no network.
- CSV is an **export transform**, not a storage format. Provide CSV and JSON export
  via the share sheet.
- Every sample carries a schema version. Assume the schema will change.

---

## 7. Camera

Treated as part of Phase 1 because the camera is a device sensor. If it must be
split out for scheduling reasons, propose it as Phase 1.5 -- but complete, not
partial.

### 7.1 Capture
- In-app still photo and video capture. The user sees something out the window and
  captures it without leaving the app.
- **Capture against the ring buffer, not the instant.** Grab a window of roughly ten
  seconds before and after the shutter, so a photo of a rough patch carries the
  actual acceleration trace around it rather than a single sample.
- Log device attitude at capture. This enables computing what the camera was pointed
  at later (a future-phase feature, but the data must be captured now or it is lost
  forever).

### 7.2 Metadata
Three tiers, deliberately:

1. **Standard EXIF/GPS tags** -- position, altitude, heading, timestamp. These are
   understood by Photos, by every other tool, and make the asset behave correctly on
   maps.
2. **Free-form text fields** -- EXIF `UserComment` and the IPTC caption/description
   field. Photos surfaces the IPTC caption as an editable, *searchable* description.
   Write the generated summary here so it is findable years later without the app.
3. **XMP block carrying the full structured snapshot as JSON** -- the complete
   estimator output at capture time. This makes the image self-describing even if
   the sidecar is lost.

Additionally, write a sidecar snapshot record into iCloud alongside the flight log,
keyed by the Photos asset local identifier.

### 7.3 Generated text

**Title** -- identifies flight and place. Route, date, nearest city, flight phase.
No clock time, no percentage.

> `Denver (DEN) to Los Angeles (LAX), August 20 -- over Provo, Utah, cruise`

Every asset from the same flight shares the same route/date prefix, which makes the
flight function as a de facto searchable album in Photos.

**Description/caption** -- the numbers, per photo.

> `38,000 ft, 511 kt ground, smooth. 42 mi N of Ely, Nevada.`

### 7.4 Sharing
- Save to Apple Photos with all of the above.
- Full share sheet support for the asset and for exported logs.

---

## 8. Interface

Not a design spec -- design freedom is yours. Requirements only:

- The map is the primary surface: your track, the filed route, the aircraft symbol,
  divert airports, and the position confidence ellipse.
- A metrics surface exposing every channel in §2.3, with window selection (1/5/30
  min/flight) and the statistics from §2.4.
- The turbulence view showing measured and forecast together, plus the labeled peak
  events from the extrema detector.
- The fix-quality panel from §2.2.
- The pre-flight readiness screen from §5, with per-asset verified state.
- The media strip.
- Readability at cabin brightness matters. Assume a person glancing at this in a
  dark cabin next to someone sleeping.

---

## 9. Explicitly out of scope for Phase 1

Do not build, do not stub, do not leave hooks that imply these exist:

- User accounts, profiles, authentication (Phase 2)
- Any social or sharing-to-network feature beyond the system share sheet (Phase 2)
- Peer-to-peer discovery, BLE, Multipeer (Phase 3)
- In-flight entertainment endpoint probing (Phase 3)
- Cross-flight statistics or history analysis (Phase 4)

One exception: the per-channel **source** field in the data model should exist from
day one, because Phase 3 introduces channels arriving from non-device sources
(outside air temperature, wind vector) and retrofitting that field would touch every
log ever written.

---

## 10. Deliverables from planning

Before writing code, produce:

1. The `Estimator` output struct definition -- the contract.
2. The log schema (NDJSON line format and manifest format), versioned.
3. Module and package layout.
4. **The explicit list of what you will complete to full working quality in this
   pass, and what you propose to defer to a numbered subphase, with reasoning.**
5. Third-party dependency list with licenses.
6. The bundled dataset list with sizes -- OurAirports, NASR fixes, ARTCC polygons,
   places -- and whether each ships in the bundle or downloads on demand.

Flag anything in this document you believe is wrong, infeasible, or more expensive
than it appears. Push back during planning rather than discovering it mid-build.
