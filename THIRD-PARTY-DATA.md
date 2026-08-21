# Third-party datasets

## GTG turbulence forecast (live API, not a bundled dataset)

§4.2/§4.3's forecast-vs-measured comparison uses [GribStream](https://gribstream.com)'s
`dafsgtg` model, a mirror of NOAA/NCEP's real DAFS GTG feed with the values already
decoded from GRIB2 into JSON. This is a deliberate substitute for parsing raw GRIB2
on-device -- inspecting a real NCEP DAFS GTG file during this build confirmed the spec's
own prediction ("a rabbit hole"): Lambert Conformal projection, a bitmap, and complex
packing with second-order spatial differencing, not a decoder to hand-write against a
single feature's remaining budget.

**This requires your own GribStream account.** Sign up for a free account at
gribstream.com, generate an API token, and enter it on the Flight tab before starting a
flight (Turbulence Forecast section). No account or token is bundled with this app --
creating one is a real account/billing decision that belongs to whoever runs the app,
not something to embed. Leaving the token blank just means the app logs and shows
measured turbulence only, same as before this feature existed.

The request-building and response-parsing logic (`ContrailForecast`) is unit-tested
against fixtures matching GribStream's documented API shape and has been exercised
against the real live endpoint (confirmed reachable, returning a genuine `401` for an
invalid token -- i.e. the request format reaches GribStream's auth layer correctly) but
not yet against a real authenticated response, since that needs an account this build
doesn't have.

Bundled datasets compiled by `contrail-prep` (`Packages/ContrailKit/Sources/ContrailPrep`)
from the following upstream sources. Not code dependencies — tracked separately because
one of them carries a legal attribution requirement that must surface somewhere in the
shipping app (an About/Acknowledgments screen — App-target work, not yet built).

| Dataset | Source | License | Attribution required |
|---|---|---|---|
| Airports | [OurAirports](https://ourairports.com/data/) — `airports.csv` | Public domain | No, but customary |
| Populated places | [GeoNames](https://www.geonames.org/) — `cities1000` dump | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | **Yes** |
| Fixes & navaids | [FAA NASR 28-day subscription](https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/) — `FIX_BASE.csv`, `NAV_BASE.csv` | Public domain (US federal government work) | No |
| ARTCC boundaries | FAA NASR 28-day subscription — `ARB_BASE.csv`, `ARB_SEG.csv` | Public domain (US federal government work) | No |

## GeoNames attribution

CC BY 4.0 requires crediting the source. When the app ships an Acknowledgments screen,
include:

> Populated place data © [GeoNames.org](https://www.geonames.org/), licensed under
> [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

## NASR data goes stale every 28 days

Unlike the airports/places datasets, FAA NASR publishes a new subscription cycle every
28 days — fixes, navaids, and ARTCC boundaries do change (new procedures, decommissioned
navaids, sector realignments). The bundled `navfixes.bin`/`artcc.bin` are a snapshot from
the cycle effective **2026-08-06**, not a live feed; recompiling from a fresher cycle
before each app release is a housekeeping task, not a one-time setup step.

## Compiling

```
swift run contrail-prep airports <path to airports.csv> <output airports.bin>
swift run contrail-prep places <path to cities1000.txt> <output places.bin>
swift run contrail-prep navfixes <path to FIX_BASE.csv> <path to NAV_BASE.csv> <output navfixes.bin>
swift run contrail-prep artcc <path to ARB_BASE.csv> <path to ARB_SEG.csv> <output artcc.bin>
```

Source files (not checked into this repo — download fresh when recompiling):
- `https://davidmegginson.github.io/ourairports-data/airports.csv`
- `https://download.geonames.org/export/dump/cities1000.zip` (unzip first)
- FAA NASR CSV subscriber files, from the current cycle's page linked above (look for
  `FIX_CSV.zip`, `NAV_CSV.zip`, and `ARB_CSV.zip` under that cycle's downloads; unzip
  each to get `FIX_BASE.csv`, `NAV_BASE.csv`, `ARB_BASE.csv`, `ARB_SEG.csv`)
