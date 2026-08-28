#!/usr/bin/env python3
"""
examples/load_and_join_data.py

Demonstrates how to load, connect, and analyze the tiger mosquito archive data
using Python and pandas / geopandas.

Requirements:
    pip install pandas geopandas
"""

import os
import sys
import pandas as pd

def find_file(filename):
    """Locate file whether running from root or examples/ directory."""
    if os.path.exists(filename):
        return filename
    parent_path = os.path.join("..", filename)
    if os.path.exists(parent_path):
        return parent_path
    raise FileNotFoundError(f"Could not find {filename}")

def main():
    history_path = find_file("feature_history.csv")
    snapshots_path = find_file("feature_history_snapshots.csv")
    geojson_path = find_file("tiger_mosquito_colonisation_in_france.geojson")

    print("Reading archive tables...")
    history = pd.read_csv(history_path)
    snapshots = pd.read_csv(snapshots_path)

    # Connect the tables using foreign keys:
    #   feature_history.first_seen_snapshot_id -> feature_history_snapshots.snapshot_id
    #   feature_history.last_seen_snapshot_id  -> feature_history_snapshots.snapshot_id
    print("Joining feature history with snapshot ledger...")
    
    first_snapshot_cols = snapshots[["snapshot_id", "commit", "tag", "source_update_date"]].rename(
        columns={
            "commit": "first_commit",
            "tag": "first_tag",
            "source_update_date": "first_source_update",
        }
    )
    last_snapshot_cols = snapshots[["snapshot_id", "commit", "tag", "source_update_date"]].rename(
        columns={
            "commit": "last_commit",
            "tag": "last_tag",
            "source_update_date": "last_source_update",
        }
    )

    history_annotated = history.merge(
        first_snapshot_cols,
        left_on="first_seen_snapshot_id",
        right_on="snapshot_id",
        how="left",
    ).drop(columns=["snapshot_id"]).merge(
        last_snapshot_cols,
        left_on="last_seen_snapshot_id",
        right_on="snapshot_id",
        how="left",
    ).drop(columns=["snapshot_id"])

    print("\n=== Summary of Joined Data ===")
    print(f"Total unique canonical polygons tracked: {len(history_annotated)}")
    print(f"Currently present in latest snapshot:    {history_annotated['currently_present'].sum()}")
    print(f"Retired / removed in past snapshots:     {(~history_annotated['currently_present']).sum()}")

    print("\n--- Polygons first observed by date (top 5 dates) ---")
    print(history_annotated["first_seen_archive_date"].value_counts().head(5))

    # Optional: Load GeoJSON with GeoPandas if installed
    try:
        import geopandas as gpd
        print(f"\nReading spatial GeoJSON with geopandas from {geojson_path}...")
        gdf = gpd.read_file(geojson_path)
        print(f"Current active GeoJSON polygons: {len(gdf)}")
        print(f"CRS: {gdf.crs}")
    except ImportError:
        print("\n(Install 'geopandas' to load and map the GeoJSON geometries: pip install geopandas)")

    print("\nDone! Data loaded and connected successfully.")

if __name__ == "__main__":
    main()
