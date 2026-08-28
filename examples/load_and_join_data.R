#!/usr/bin/env Rscript

# examples/load_and_join_data.R
#
# Demonstrates how to load, connect, and analyze the tiger mosquito archive data
# using R and dplyr / sf.
#
# Requirements:
#   install.packages(c("dplyr", "sf")) # sf is optional for spatial analysis

suppressPackageStartupMessages({
  library(dplyr)
})

# 1. Load the history table and the snapshot ledger
history_file <- "feature_history.csv"
snapshots_file <- "feature_history_snapshots.csv"
geojson_file <- "tiger_mosquito_colonisation_in_france.geojson"

# Locate files (works whether run from repository root or examples/ directory)
if (!file.exists(history_file) && file.exists(file.path("..", history_file))) {
  history_file <- file.path("..", history_file)
  snapshots_file <- file.path("..", snapshots_file)
  geojson_file <- file.path("..", geojson_file)
}

message("Reading archive tables...")
history <- read.csv(history_file, stringsAsFactors = FALSE)
snapshots <- read.csv(snapshots_file, stringsAsFactors = FALSE)

# 2. Connect the tables using foreign keys
#    - feature_history.first_seen_snapshot_id -> feature_history_snapshots.snapshot_id
#    - feature_history.last_seen_snapshot_id  -> feature_history_snapshots.snapshot_id
message("Joining feature history with snapshot ledger...")

history_annotated <- history %>%
  left_join(
    snapshots %>%
      select(
        snapshot_id,
        first_commit = commit,
        first_tag = tag,
        first_source_update = source_update_date
      ),
    by = c("first_seen_snapshot_id" = "snapshot_id")
  ) %>%
  left_join(
    snapshots %>%
      select(
        snapshot_id,
        last_commit = commit,
        last_tag = tag,
        last_source_update = source_update_date
      ),
    by = c("last_seen_snapshot_id" = "snapshot_id")
  )

# 3. Explore the connected dataset
cat("\n=== Summary of Joined Data ===\n")
cat("Total unique canonical polygons tracked:", nrow(history_annotated), "\n")
cat("Currently present in latest snapshot:   ", sum(history_annotated$currently_present), "\n")
cat("Retired / removed in past snapshots:    ", sum(!history_annotated$currently_present), "\n\n")

# Top 5 earliest snapshot dates
cat("--- Polygons first observed by date (top 5 dates) ---\n")
print(head(table(history_annotated$first_seen_archive_date), 5))

# 4. Optional: Load and inspect spatial GeoJSON
if (requireNamespace("sf", quietly = TRUE)) {
  message("\nReading spatial GeoJSON with sf...")
  communes_sf <- sf::st_read(geojson_file, quiet = TRUE)
  cat("Current active GeoJSON polygons:", nrow(communes_sf), "\n")
  cat("Geometry type:", as.character(sf::st_geometry_type(communes_sf, by_geometry = FALSE)), "\n")
} else {
  message("\n(Install the 'sf' package to load and map the GeoJSON geometries: install.packages('sf'))")
}

message("\nDone! Data loaded and connected successfully.")
