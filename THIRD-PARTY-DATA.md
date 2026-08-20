# Third-party datasets

Bundled datasets compiled by `contrail-prep` (`Packages/ContrailKit/Sources/ContrailPrep`)
from the following upstream sources. Not code dependencies — tracked separately because
one of them carries a legal attribution requirement that must surface somewhere in the
shipping app (an About/Acknowledgments screen — App-target work, not yet built).

| Dataset | Source | License | Attribution required |
|---|---|---|---|
| Airports | [OurAirports](https://ourairports.com/data/) — `airports.csv` | Public domain | No, but customary |
| Populated places | [GeoNames](https://www.geonames.org/) — `cities1000` dump | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | **Yes** |

## GeoNames attribution

CC BY 4.0 requires crediting the source. When the app ships an Acknowledgments screen,
include:

> Populated place data © [GeoNames.org](https://www.geonames.org/), licensed under
> [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

## Compiling

```
swift run contrail-prep airports <path to airports.csv> <output airports.bin>
swift run contrail-prep places <path to cities1000.txt> <output places.bin>
```

Source files (not checked into this repo — download fresh when recompiling):
- `https://davidmegginson.github.io/ourairports-data/airports.csv`
- `https://download.geonames.org/export/dump/cities1000.zip` (unzip first)
