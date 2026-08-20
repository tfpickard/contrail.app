# Contrail -- Roadmap

Four phases. Ordering is deliberate and was arrived at by working backwards from
dependencies, not by feature attractiveness.

**Standing rule across all phases:** working alpha/beta quality only. No stubs, no
placeholders, no non-functional views. A feature that cannot be completed to that
bar gets deferred to its own numbered subphase and flagged during planning. Never
half-shipped.

---

## Phase 1 -- Device sensors

*The instrument. Runs on one phone, alone, with no network and no account.*

### Scope
Everything the device itself can measure or compute, plus everything that can be
prefetched at the gate.

- Sensor acquisition layer with a `SensorSource` protocol and a replay
  implementation for desk-based development
- Estimator producing a single fused output struct, including dead reckoning and
  confidence radius
- Statistics engine: ring buffers, rolling windows, monotonic-deque min/max, peak
  detection with prominence
- Adaptive logging rate with phase classifier and event-triggered burst capture
- Turbulence measurement (EDR^(1/3), attitude-gated) and GTG forecast comparison
- Offline vector map via MapLibre + PMTiles, corridor verified before departure
- Pre-flight resolution: flight number to route, aircraft type, times
- Bundled datasets: divert airports with runway filtering, enroute fixes, ARTCC
  polygons, populated places
- NDJSON logging with per-flight manifest, iCloud replication, CSV/JSON export
- In-app camera with three-tier metadata and generated titles/captions
- Native iPhone and iPad layouts from the same view components

### Likely subphase candidates
Flag during planning if the effort demands it:

- **1.x GTG forecast pipeline.** GRIB2 slicing needs a pre-processing step outside
  the app. If that infrastructure isn't ready, the measurement half stands alone
  perfectly well and the comparison view waits.
- **1.x Camera.** Conceptually Phase 1 -- the camera is a device sensor -- but the
  metadata writing is real work. Split whole if needed, never partial.

### Exit criteria
Take a real flight. Land with a complete log, a track that matches reality, photos
carrying correct metadata, and a turbulence trace you would defend.

---

## Phase 2 -- Identity

*Users and profiles. Built second because it is foundational, not because it is
exciting.*

Retrofitting identity later would mean migrating every log and every media snapshot
ever written. It goes in early for the same reason you pour a foundation before
framing.

### Scope
- User account and profile model
- **Freeform profile section** -- what you write about yourself
- **Generated profile section** -- what your flight history says about you. Hours at
  altitude, flights logged, routes flown, and the genuinely charming statistical
  observations: whether you are unusually lucky or cursed with turbulence, your
  average delay, your roughest route. Derived, not self-reported, which is what
  makes it interesting.
- Sharing outward: flight summaries and captured media to the platforms the user
  chooses
- **Group flight records.** Several people on the same flight -- family, colleagues,
  friends -- each running the app, producing one combined record. Merged media,
  merged tracks, and, because they are seated in different places, genuinely
  different turbulence traces from the same airframe.

### Notes
The group flight record is the feature that matters here. It is also the direct
technical predecessor to Phase 3: front-of-cabin and back-of-cabin accelerometers
fifty feet apart are a distributed sensor array measuring the airframe's rotational
response, which is real instrumentation nobody has ever had at scale.

---

## Phase 3 -- Local discovery

*Two problems that are one problem: find things on the local network, parse whatever
you find, degrade gracefully.*

Folded together deliberately. Both halves share the same discovery scaffolding,
the same pluggable-transport abstraction, and the same failure semantics. Building
them as separate phases would mean writing that machinery twice.

### 3a -- Passenger discovery

Find other people on your flight running the app.

- **BLE as the beacon.** Advertise a custom service UUID. Advertisement payload is
  31 bytes total, leaving roughly 20 usable, so the advertisement carries presence
  only, nothing more.
- **GATT for the handshake.** First read returns a minimal record: display name, a
  few generated stats, and a hash of the avatar. The discovery screen is therefore
  instant.
- **Avatar transfers only on explicit request**, and the hash means a given person's
  image is fetched exactly once, ever.
- **Bulk transfer over peer-to-peer Wi-Fi.** `MultipeerConnectivity` or `NWListener`
  with `includePeerToPeer` negotiates over Bluetooth then brings up AWDL -- the same
  transport AirDrop rides -- giving megabytes per second with no access point
  involved. BLE's throughput is measured in tens of kilobytes per second and is not
  the right pipe for images.
- **Cabin Wi-Fi as an opportunistic third path.** Bonjour plus a plain TCP socket
  when both parties are on the aircraft network. Airline access points frequently
  enable client isolation specifically to prevent this, so it is a coin flip per
  carrier. Try it, fall back silently.

**Privacy architecture, non-negotiable:**
- Entirely opt-in and user-initiated. A dedicated screen the user deliberately opens.
- **Strict two-stage disclosure.** Advertising presence reveals exactly one bit:
  someone here runs this app. Profile exchange is a separate handshake requiring both
  parties to accept. Nobody learns anything about anybody until both have said yes.
- Background operation is best-effort, explicitly not a guarantee. iOS strips the
  local name from backgrounded advertisements, throttles scanning, and reduces
  advertising rate. Two backgrounded devices may take minutes to find each other or
  may not. Foreground is the reliable case, which is fine, because the user opened
  the screen on purpose.

### 3b -- Aircraft data endpoint

The single best data source in the entire product, if you can reach it.

- Panasonic and Thales in-flight entertainment systems typically serve their moving
  map from a local HTTP endpoint on the cabin network, usually as JSON. The IFE
  portal is free by design, so this often works **without purchasing connectivity.**
- Payload commonly includes **static air temperature, true airspeed, wind vector**,
  ground speed, position, and time to destination.
- This is the only source of genuine *outside* atmospheric data in the app.
  Everything else measures the inside of a pressurized tube.
- **Build it as a pluggable prober**: try a set of known endpoints, sniff the payload
  shape, adapt. No documentation exists, no stability is guaranteed, and the shape
  differs by vendor and by airline install.
- Failure costs nothing, because the Phase 1 core stands entirely alone.

This is why the per-channel `source` field exists in the data model from Phase 1:
temperature may arrive from IFE, or may simply be absent, and the UI needs to know
the difference between "zero" and "unknown."

---

## Phase 4 -- Meta-analysis

*What you learn from a hundred flights that you cannot learn from one.*

The whole reason logging was a hard requirement from day one. This phase writes no
new sensor code -- it reads the accumulated corpus.

### Scope
- **Route statistics.** Fly Denver to LA ten times and you have a real distribution:
  how turbulent that route actually runs, seasonally and by time of day.
- **Personal statistics.** Total hours at altitude, distance flown, airports visited,
  airspace crossed, delay distribution.
- **Forecast skill scoring.** You have paired predicted and measured turbulence for
  every sample of every flight. That is a verification dataset. Compute GTG's actual
  skill against your own measurements. Nobody has this for their own flying.
- **Aircraft and seat comparison.** Ride quality by airframe type. Whether your seat
  relative to the wing measurably changes what you feel -- which it does, and now
  you can prove it.
- **Route deviation patterns.** Cross-track history reveals where reroutes reliably
  happen.

---

## Deferred / speculative

Not scheduled. Recorded so the architecture does not preclude them.

- **External GNSS receiver.** A Bluetooth NMEA source (u-blox based, Bad Elf class)
  delivers GSV and GSA sentences: satellites in view per constellation, per-system
  fix quality, DOP. Everything iOS refuses to expose. Requires carrying a dongle,
  which changes the product from something anyone installs into something you commit
  to. The `SensorSource` protocol accommodates it without touching the estimator.
- **Live ADS-B when connectivity exists.** Airspace density around you, and
  correlating your measured turbulence against other aircraft's reported EDR in the
  same airspace.
- **Camera pointing resolution.** Attitude is logged at capture from Phase 1, so
  computing what mountain, city, or lake a photo was actually pointed at is a pure
  post-processing problem whenever someone wants to write it.
- **Web dashboard.** Because logs are open NDJSON in iCloud, a browser-based analysis
  view can read them without the app being involved at all. Native purity now does
  not cost the web version later.
