[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.14914293.svg)](https://doi.org/10.5281/zenodo.14914293)

This repository is an automatic archive of data displayed at [https://signalement-moustique.anses.fr/signalement_albopictus/colonisees](https://signalement-moustique.anses.fr/signalement_albopictus/colonisees).

The data is fetched once a week with the [`alboFr`](https://github.com/e-kotov/alboFr) R package. A new commit and GitHub release are created only when the canonical feature-set hash changes, so releases should correspond to actual data changes rather than GeoJSON formatting or feature-order noise.

Each release ZIP contains:

- `tiger_mosquito_colonisation_in_france.geojson`
- `metadata.json`
- `SNAPSHOT.md`
- `README.md`
- `CITATION.cff`
- `.zenodo.json`
- `LICENSE.md`

`metadata.json` contains per-snapshot metadata, including:

- fetch timestamp
- official source update date parsed from the ANSES page when available
- canonical data hash
- feature count
- `alboFr` version and GitHub SHA
- GitHub Actions workflow run ID

`SNAPSHOT.md` is a human-readable summary of the same per-snapshot metadata. `.zenodo.json` is stable repository-level metadata for the Zenodo GitHub integration and is not updated for each snapshot.

The data at [https://signalement-moustique.anses.fr/signalement_albopictus/colonisees](https://signalement-moustique.anses.fr/signalement_albopictus/colonisees) may not be updated every week. `source_official_update_date` is parsed from the page text and may be unavailable if the source page changes.

The original data does not have a well defined license, but the legal matters regarding this data can be found here: [https://signalement-moustique.anses.fr/signalement_albopictus/mentionslegales](https://signalement-moustique.anses.fr/signalement_albopictus/mentionslegales).
