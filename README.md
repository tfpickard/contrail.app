# Contrail

> Working title.

**A flight instrument for the passenger cabin.**

---

## What this is

An iOS app that turns the phone in your pocket into a full instrument panel for the
flight you happen to be sitting on. You enter your flight number before you board.
The app resolves the route, downloads everything it needs, and then -- with no
connectivity for the next five hours -- shows you where you are, how fast, how high,
how rough, how far, and how late.

It works entirely offline because that is the entire point. GPS is a receive-only
system; the satellite fix keeps working at FL380 in airplane mode. What stops
working is everything that needs a network. So everything that needs a network
happens at the gate.

## Who it's for

The passenger who wants to know. Engineers, pilots, nervous flyers, aviation
enthusiasts, anyone who has ever looked at the seatback moving map and thought *that
is a criminally small amount of information.*

It is deliberately not a flight-booking app, not a flight-status app for people on
the ground, and not a general-purpose navigation app. It is an instrument for the
duration of one flight.

## Why it exists

Two reasons.

**Airlines are removing seatback screens.** The moving map is disappearing from
short and medium haul, replaced by a QR code and a streaming app that mostly wants
to sell you a movie.

**The interesting question is planned versus actual.** Every flight has a filed
route, a scheduled block time, and a turbulence forecast. Every flight then deviates
from all three. The device in your pocket can measure the deviation. Nobody ships
that comparison, and it is the most interesting thing available.

## What makes it different

- **Everything is offline-verified before pushback**, not opportunistically cached
  and hoped for.
- **Turbulence is measured, not just forecast** -- and plotted against the forecast,
  so you can see how good the model was over your own track.
- **Position is honest about uncertainty.** GPS drops constantly in an aluminum
  tube. The app runs a dead-reckoning estimate alongside the fix and shows a
  confidence radius that grows when the signal is lost and snaps tight when it comes
  back. No fake blue dot.
- **The data is yours.** Every flight logs to newline-delimited JSON in iCloud,
  exportable as CSV or JSON, readable by anything.
- **Photos carry the whole state.** A picture out the window is tagged with position,
  altitude, groundspeed, turbulence, nearest city, and flight phase -- written into
  standard EXIF and IPTC fields so it stays searchable in Photos forever, plus a full
  structured snapshot in XMP.

## Development phases

**Phase 1 -- Device sensors.** The instrument itself. GPS, barometer, accelerometers,
camera. Offline map, route resolution, divert planning, airspace, waypoints,
turbulence measurement and forecast comparison, statistics, logging. Works alone, on
one phone, with no network and no account.

**Phase 2 -- Identity.** Users, profiles, and sharing. Profiles combine what you
write with what your flight history says about you. Built early because identity is
foundational and retrofitting it would touch every log ever written.

**Phase 3 -- Local discovery.** Two problems that are really one problem: finding
other passengers running the app (BLE beacon, peer-to-peer Wi-Fi for bulk transfer,
strictly opt-in and double-consented), and finding the aircraft's own in-flight
entertainment data endpoint, which on many airframes serves outside air temperature
and wind data over the cabin network for free. Both are "probe the local network,
discover something, parse whatever you find, degrade gracefully."

**Phase 4 -- Meta-analysis.** Statistics across your own accumulated flight history.
Fly Denver to LA ten times and you learn how turbulent that route actually runs, how
your delays trend, and how well the turbulence forecast performed against your own
measurements.

Full detail in `ROADMAP.md`.

## Feature list

### Position and navigation
- Real-time position on an offline vector map
- Groundspeed computed from successive fixes (CoreLocation's filtered value shown
  separately, for comparison)
- True course and track angle rate
- GPS altitude and vertical speed
- Dead reckoning along the filed route when GPS drops, with a visible confidence
  radius
- Great circle distance flown and remaining
- Signed cross-track error against the filed route -- a live reroute indicator
- Fractional progress
- Nearest city with bearing and distance
- ETA with variance, and schedule delta against block time
- Fix-quality panel: accuracy trend, dropout intervals, time to reacquire

### Cabin environment
- Cabin pressure and cabin pressure altitude
- Pressurization rate -- typically detects descent before it is announced

### Turbulence
- Measured intensity as EDR^(1/3), the same metric airlines report
- Handling-motion rejection via high-pass filtering and attitude gating
- NOAA GTG forecast interpolated in three dimensions along the route
- Predicted versus measured, plotted along the track with residual
- Discrete peak events -- "the three biggest bumps of this flight" -- labeled,
  timestamped, and locatable on the map

### Statistics
- Rolling windows at 1, 5, and 30 minutes plus whole-flight
- Mean, min, max, standard deviation, percentiles for every numeric channel
- Local extrema detection with prominence thresholding, distinct from windowed max

### Route intelligence
- Flight number resolution to route, times, aircraft type, and registration
- Filed route waypoints where published
- Enroute fixes: nearest, next along track, and a running scroll as they are crossed
- ARTCC/FIR jurisdiction -- which center has you right now
- Divert planning: usable airports filtered by runway length against your actual
  aircraft type, ranked by glide reach rather than straight-line distance

### Capture
- In-app photo and video without leaving the app
- Metadata window captured around the shutter, not a single instant
- Standard EXIF/GPS tags, searchable IPTC caption, full JSON snapshot in XMP
- Generated titles and captions: route, date, nearest city, flight phase, and the
  numbers
- Saved to Apple Photos and to iCloud, full share sheet support

### Data ownership
- Newline-delimited JSON, append-safe, one file per flight
- Self-describing per-flight manifest
- Local storage as source of truth, iCloud as replication
- CSV and JSON export

### Sampling
- Adaptive logging rate driven by a flight phase classifier
- Continuous high-rate accelerometer as a trigger, with pre-trigger ring buffer
  capture so the leading edge of an event is never lost
- Adaptive threshold calibrated to a rolling baseline, self-tuning to the airframe
  and to your seat relative to the wing

## Technical stack

- Swift and SwiftUI, native iOS, no cross-platform layer
- iPhone-first as the sensor platform; native iPad layouts, not a scaled port
- MapLibre Native with PMTiles/Protomaps for verifiably offline vector maps
- CoreLocation, CoreMotion, CMAltimeter, AVFoundation, Photos
- iCloud Documents for log replication
- Core logic in a platform-agnostic Swift Package, thin app target on top

## A note on limitations

iOS does not expose GNSS internals. No satellite count, no per-constellation fix
quality, no DOP, no raw pseudoranges. CoreLocation gives a fused position and an
accuracy radius, and that is all. An external Bluetooth NMEA receiver would provide
the full picture and is a possible future addition, but is out of scope.

Turbulence is measured at the tray table, not at the airframe. There is an unknown
mechanical transfer function in between. The measurement is a well-calibrated
relative intensity, not an absolute airframe figure, and the app says so where the
number is displayed.
