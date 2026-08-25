[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.14914293.svg)](https://doi.org/10.5281/zenodo.14914293)

This repository is an automatic archive of data displayed at [https://signalement-moustique.anses.fr/signalement_albopictus/colonisees](https://signalement-moustique.anses.fr/signalement_albopictus/colonisees).

The data is fetched once a week with the [`alboFr`](https://github.com/e-kotov/alboFr) R package. A new commit and GitHub release are created only when the canonical feature-set hash changes, so releases should correspond to actual data changes rather than GeoJSON formatting or feature-order noise.

Each release ZIP contains:

- `tiger_mosquito_colonisation_in_france.geojson`
- `metadata.json`
- `feature_history.csv`
- `feature_history_snapshots.csv`
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

### Feature History and Interpretation Rules

`feature_history.csv` has one row per canonical polygon ever archived.
`feature_history_snapshots.csv` has one row per archived snapshot; join the two on
`first_seen_snapshot_id` / `last_seen_snapshot_id` to recover commits and release tags.

> `first_seen_archive_date` is the first date this polygon was observed in this archive,
> not necessarily the true first official ANSES publication date.

Important notes on interpreting history:

- `source_official_update_date` comes from the ANSES page text and may be empty when
  parsing fails.
- `first_seen_source_update_date` and `last_seen_source_update_date` are **empty for every
  snapshot archived before `metadata.json` existed**. They are left empty deliberately;
  they are not back-filled with a later date.
- Feature hashes are exact canonical-feature identifiers, not guaranteed stable real-world
  entity identifiers. If a polygon geometry or a meaningful property changes, the changed
  feature is recorded as a new hash and the old one becomes `currently_present = FALSE`.
- `bbox_*`, `n_vertices`, `geometry_type` and `properties_json` describe the feature as it
  looked when first seen, so polygons that have since disappeared remain identifiable.
- Canonical identity relies on JSON round-tripping of coordinates at 15 significant
  digits. If the upstream source ever changes its coordinate precision, every feature will
  be assigned a new hash and the history will show a full turnover on that date.

The data at [https://signalement-moustique.anses.fr/signalement_albopictus/colonisees](https://signalement-moustique.anses.fr/signalement_albopictus/colonisees) may not be updated every week. `source_official_update_date` is parsed from the page text and may be unavailable if the source page changes.

The original data does not have a well defined license, but the legal matters regarding this data can be found here: [https://signalement-moustique.anses.fr/signalement_albopictus/mentionslegales](https://signalement-moustique.anses.fr/signalement_albopictus/mentionslegales).
