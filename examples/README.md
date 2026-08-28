# alboFr Data Archive Code Examples

This directory contains ready-to-run example scripts demonstrating how to load, connect, and analyze the dataset tables.

## Available Examples

- **[`load_and_join_data.R`](load_and_join_data.R)**: R script using `dplyr` (and optionally `sf`) to join `feature_history.csv` with `feature_history_snapshots.csv` on `snapshot_id`, inspect historical turnover, and read the GeoJSON spatial data.
- **[`load_and_join_data.py`](load_and_join_data.py)**: Python script using `pandas` (and optionally `geopandas`) to join the history table with the ledger and inspect summary statistics.

## How to Run

### In R:
```bash
Rscript examples/load_and_join_data.R
```

### In Python:
```bash
# With standard pip installation
python3 examples/load_and_join_data.py

# Or with uv (including spatial geopandas support)
uv run --with pandas --with geopandas examples/load_and_join_data.py
```
