#!/usr/bin/env Rscript

# scripts/build_feature_history.R
#
# Tracks when each canonical GeoJSON feature first appeared in this archive and
# when it was last seen.
#
# Modes:
#   --rebuild   replay every commit that touched the data file (slow, one-off)
#   (default)   apply the current working-tree snapshot to the existing tables
#
# Outputs:
#   feature_history.csv            one row per canonical feature
#   feature_history_snapshots.csv  one row per applied snapshot (the ledger)

Sys.setlocale("LC_COLLATE", "C")

suppressPackageStartupMessages({
  library(alboFr)
  library(jsonlite)
  library(digest)
})

HISTORY_COLS <- c(
  feature_hash = "character",
  first_seen_archive_date = "character",
  last_seen_archive_date = "character",
  n_snapshots_seen = "integer",
  currently_present = "logical",
  first_seen_snapshot_id = "integer",
  last_seen_snapshot_id = "integer",
  first_seen_release = "character",
  last_seen_release = "character",
  first_seen_source_update_date = "character",
  last_seen_source_update_date = "character",
  bbox_xmin = "numeric",
  bbox_ymin = "numeric",
  bbox_xmax = "numeric",
  bbox_ymax = "numeric",
  n_vertices = "integer",
  geometry_type = "character",
  properties_json = "character"
)

LEDGER_COLS <- c(
  snapshot_id = "integer",
  archive_date = "character",
  commit = "character",
  tag = "character",
  source_update_date = "character",
  feature_set_hash = "character",
  data_canonical_sha256 = "character",
  n_features = "integer"
)

# ---------------------------------------------------------------- utilities --

# NOTE: system2() pastes arguments into a shell command string without quoting,
# so every argument MUST go through shQuote(). Without it, a format string such
# as "--format=%H|%ad" is parsed as a shell pipe.
git_lines <- function(args) {
  out <- suppressWarnings(system2("git", shQuote(args), stdout = TRUE, stderr = FALSE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) {
    stop("git ", paste(args, collapse = " "), " failed with status ", st, call. = FALSE)
  }
  as.character(out)
}

git_show_to_file <- function(spec, path) {
  st <- system2("git", shQuote(c("show", spec)), stdout = path, stderr = FALSE)
  identical(st, 0L)
}

na_to_blank <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x
}

feature_set_hash <- function(hashes) {
  digest::digest(paste(sort(unique(hashes)), collapse = ""),
                 algo = "sha256", serialize = FALSE)
}

read_table <- function(path, spec) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE,
                        colClasses = as.character(spec),
                        na.strings = character(0))
  missing <- setdiff(names(spec), names(df))
  if (length(missing) > 0) {
    stop(basename(path), " is missing column(s): ", paste(missing, collapse = ", "),
         ". Delete it and re-run with --rebuild.", call. = FALSE)
  }
  df[names(spec)]
}

write_table <- function(df, path, spec) {
  df <- df[names(spec)]
  for (nm in names(spec)) {
    if (spec[[nm]] == "character") df[[nm]] <- na_to_blank(df[[nm]])
  }
  utils::write.csv(df, path, row.names = FALSE, na = "")
}

# ------------------------------------------------------- geometry summaries --

# One row per unique feature_hash describing a representative geometry.
# `hashes` must be the per-feature hash vector for `path`, in file order.
summarise_features <- function(path, hashes) {
  geo <- jsonlite::fromJSON(paste(readLines(path, warn = FALSE), collapse = "\n"),
                            simplifyVector = FALSE)
  n <- length(geo$features)
  if (n != length(hashes)) {
    stop("Feature count (", n, ") does not match hash count (", length(hashes), ").",
         call. = FALSE)
  }
  out <- data.frame(
    feature_hash = hashes,
    bbox_xmin = NA_real_, bbox_ymin = NA_real_,
    bbox_xmax = NA_real_, bbox_ymax = NA_real_,
    n_vertices = NA_integer_,
    geometry_type = NA_character_,
    properties_json = NA_character_,
    stringsAsFactors = FALSE
  )
  for (i in seq_len(n)) {
    f <- geo$features[[i]]
    v <- unlist(f$geometry$coordinates, use.names = FALSE)
    lon <- v[seq(1L, length(v), by = 2L)]
    lat <- v[seq(2L, length(v), by = 2L)]
    out$bbox_xmin[i] <- round(min(lon), 6)
    out$bbox_ymin[i] <- round(min(lat), 6)
    out$bbox_xmax[i] <- round(max(lon), 6)
    out$bbox_ymax[i] <- round(max(lat), 6)
    out$n_vertices[i] <- length(lon)
    out$geometry_type[i] <- as.character(f$geometry$type)
    out$properties_json[i] <- as.character(
      jsonlite::toJSON(f$properties, auto_unbox = TRUE, null = "null")
    )
  }
  out[!duplicated(out$feature_hash), , drop = FALSE]
}

# ------------------------------------------------------------------ rebuild --

# Handles annotated tags: %(*objectname) is the dereferenced commit and is empty
# for lightweight tags.
tag_by_commit <- function() {
  raw <- git_lines(c("for-each-ref",
                     "--format=%(objectname) %(*objectname) %(refname:short)",
                     "refs/tags"))
  if (length(raw) == 0) return(character(0))
  parts <- strsplit(raw, " ", fixed = TRUE)
  parts <- Filter(function(p) length(p) >= 3, parts)
  if (length(parts) == 0) return(character(0))
  commits <- vapply(parts, function(p) if (nzchar(p[2])) p[2] else p[1], character(1))
  tags    <- vapply(parts, function(p) p[3], character(1))
  o <- order(tags)
  commits <- commits[o]; tags <- tags[o]
  keep <- !duplicated(commits)
  stats::setNames(tags[keep], commits[keep])
}

metadata_at_commit <- function(commit) {
  out <- suppressWarnings(
    system2("git", shQuote(c("show", paste0(commit, ":metadata.json"))),
            stdout = TRUE, stderr = FALSE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) return(NULL)
  if (length(out) == 0) return(NULL)
  tryCatch(jsonlite::fromJSON(paste(out, collapse = "\n")), error = function(e) NULL)
}

meta_field <- function(meta, field) {
  v <- meta[[field]]
  if (is.null(v)) return(NA_character_)
  v <- as.character(v)[1]
  if (is.na(v) || !nzchar(v)) return(NA_character_)
  v
}

rebuild_from_git_history <- function(data_path, history_path, ledger_path, cores) {
  message("Full rebuild from git history...")

  log_lines <- git_lines(c("log", "--reverse", "--format=%H|%ad", "--date=short",
                           "--", data_path))
  if (length(log_lines) == 0) stop("No commits found for ", data_path, call. = FALSE)

  parts <- strsplit(log_lines, "|", fixed = TRUE)
  snaps <- data.frame(
    snapshot_id = seq_along(parts),
    commit = vapply(parts, `[`, character(1), 1L),
    commit_date = vapply(parts, `[`, character(1), 2L),
    stringsAsFactors = FALSE
  )
  message(sprintf("Found %d commits touching %s.", nrow(snaps), data_path))

  tmap <- tag_by_commit()
  snaps$tag <- unname(tmap[snaps$commit])

  # --- pass 1: canonical feature hashes for every snapshot (parallel) --------
  cores <- max(1L, min(as.integer(cores), parallel::detectCores()))
  message(sprintf("Hashing %d snapshots on %d core(s)...", nrow(snaps), cores))
  t0 <- Sys.time()
  hashed <- parallel::mclapply(seq_len(nrow(snaps)), function(i) {
    tmp <- tempfile(fileext = ".geojson")
    on.exit(unlink(tmp), add = TRUE)
    if (!git_show_to_file(paste0(snaps$commit[i], ":", data_path), tmp)) {
      stop("git show failed for ", snaps$commit[i])
    }
    alboFr::get_tiger_mosquito_feature_hashes(tmp)
  }, mc.cores = cores)

  # A killed child returns NULL, not a try-error. Both must be caught.
  bad <- vapply(hashed, function(x) is.null(x) || inherits(x, "try-error"), logical(1))
  if (any(bad)) {
    stop("Hashing failed for snapshot index/indices: ",
         paste(which(bad), collapse = ", "),
         ". Re-run with --cores=1 to see the underlying error.", call. = FALSE)
  }
  message(sprintf("Hashed in %.1f s.", as.numeric(Sys.time() - t0, units = "secs")))

  # --- per-snapshot metadata (sequential, cheap) ----------------------------
  snaps$source_update_date <- NA_character_
  snaps$data_canonical_sha256 <- NA_character_
  snaps$archive_date <- NA_character_
  snaps$feature_set_hash <- NA_character_
  snaps$n_features <- NA_integer_

  for (i in seq_len(nrow(snaps))) {
    meta <- metadata_at_commit(snaps$commit[i])
    snaps$source_update_date[i] <- meta_field(meta, "source_official_update_date")
    snaps$data_canonical_sha256[i] <- meta_field(meta, "data_canonical_sha256")
    fetched <- meta_field(meta, "fetched_at")
    tag <- snaps$tag[i]
    snaps$archive_date[i] <- if (!is.na(fetched)) {
      substr(fetched, 1, 10)
    } else if (!is.na(tag) && grepl("^\\d{4}-\\d{2}-\\d{2}", tag)) {
      substr(tag, 1, 10)
    } else {
      snaps$commit_date[i]
    }
    snaps$feature_set_hash[i] <- feature_set_hash(hashed[[i]])
    snaps$n_features[i] <- length(unique(hashed[[i]]))
  }

  # --- observation table ----------------------------------------------------
  obs <- do.call(rbind, lapply(seq_len(nrow(snaps)), function(i) {
    u <- unique(hashed[[i]])
    data.frame(feature_hash = u, snapshot_idx = i, stringsAsFactors = FALSE)
  }))

  first_idx <- tapply(obs$snapshot_idx, obs$feature_hash, min)
  last_idx  <- tapply(obs$snapshot_idx, obs$feature_hash, max)
  n_seen    <- tapply(obs$snapshot_idx, obs$feature_hash, length)
  hashes_all <- names(first_idx)

  latest <- unique(hashed[[nrow(snaps)]])

  fi <- as.integer(first_idx); li <- as.integer(last_idx)
  history <- data.frame(
    feature_hash = hashes_all,
    first_seen_archive_date = snaps$archive_date[fi],
    last_seen_archive_date = snaps$archive_date[li],
    n_snapshots_seen = as.integer(n_seen),
    currently_present = hashes_all %in% latest,
    first_seen_snapshot_id = snaps$snapshot_id[fi],
    last_seen_snapshot_id = snaps$snapshot_id[li],
    first_seen_release = snaps$tag[fi],
    last_seen_release = snaps$tag[li],
    first_seen_source_update_date = snaps$source_update_date[fi],
    last_seen_source_update_date = snaps$source_update_date[li],
    stringsAsFactors = FALSE
  )

  # --- pass 2: geometry only for snapshots that introduce new hashes ---------
  # In this repo that is 3 snapshots out of 214, so this is cheap.
  need <- split(hashes_all, fi)
  message(sprintf("Extracting representative geometry from %d snapshot(s)...", length(need)))
  geom <- do.call(rbind, lapply(names(need), function(k) {
    i <- as.integer(k)
    tmp <- tempfile(fileext = ".geojson")
    on.exit(unlink(tmp), add = TRUE)
    if (!git_show_to_file(paste0(snaps$commit[i], ":", data_path), tmp)) {
      stop("git show failed for ", snaps$commit[i])
    }
    s <- summarise_features(tmp, hashed[[i]])
    s[s$feature_hash %in% need[[k]], , drop = FALSE]
  }))

  history <- merge(history, geom, by = "feature_hash", all.x = TRUE, sort = FALSE)
  history <- history[order(history$first_seen_archive_date, history$feature_hash), ]
  rownames(history) <- NULL

  ledger <- snaps[c("snapshot_id", "archive_date", "commit", "tag",
                    "source_update_date", "feature_set_hash",
                    "data_canonical_sha256", "n_features")]

  write_table(history, history_path, HISTORY_COLS)
  write_table(ledger, ledger_path, LEDGER_COLS)
  message(sprintf("Wrote %d features to %s and %d snapshots to %s.",
                  nrow(history), history_path, nrow(ledger), ledger_path))
  invisible(history)
}

# -------------------------------------------------------------- incremental --

update_incrementally <- function(data_path, metadata_path, history_path, ledger_path) {
  if (!file.exists(data_path)) stop("Data file not found: ", data_path, call. = FALSE)
  for (p in c(history_path, ledger_path)) {
    if (!file.exists(p)) {
      stop(p, " not found. Run with --rebuild first; refusing to guess history.",
           call. = FALSE)
    }
  }

  history <- read_table(history_path, HISTORY_COLS)
  ledger  <- read_table(ledger_path, LEDGER_COLS)

  meta <- if (file.exists(metadata_path)) {
    tryCatch(jsonlite::fromJSON(metadata_path), error = function(e) NULL)
  } else NULL

  release_tag <- meta_field(meta, "release_tag")
  source_update_date <- meta_field(meta, "source_official_update_date")
  data_sha <- meta_field(meta, "data_canonical_sha256")
  fetched <- meta_field(meta, "fetched_at")
  archive_date <- if (!is.na(fetched)) {
    substr(fetched, 1, 10)
  } else if (!is.na(release_tag) && grepl("^\\d{4}-\\d{2}-\\d{2}", release_tag)) {
    substr(release_tag, 1, 10)
  } else {
    format(Sys.Date(), "%Y-%m-%d")
  }

  hashes <- alboFr::get_tiger_mosquito_feature_hashes(data_path)
  current <- unique(hashes)
  fsh <- feature_set_hash(hashes)
  message(sprintf("Current snapshot: %d unique canonical features.", length(current)))

  # Idempotency guard. Compares against the LAST ledger row only, so a genuine
  # upstream revert to an older state is still recorded as a new snapshot.
  if (nrow(ledger) > 0 && identical(ledger$feature_set_hash[nrow(ledger)], fsh)) {
    message("Feature set is identical to the last recorded snapshot. Nothing to do.")
    return(invisible(history))
  }

  # Back-fill the previous snapshot's commit, which only became knowable after
  # that run committed.
  if (nrow(ledger) > 0 && !nzchar(na_to_blank(ledger$commit[nrow(ledger)]))) {
    prev <- suppressWarnings(
      system2("git", shQuote(c("log", "-1", "--format=%H", "--", data_path)),
              stdout = TRUE, stderr = FALSE))
    if (length(prev) == 1L && nzchar(prev)) ledger$commit[nrow(ledger)] <- prev
  }

  new_id <- if (nrow(ledger) > 0) max(ledger$snapshot_id) + 1L else 1L

  idx <- match(current, history$feature_hash)
  known <- idx[!is.na(idx)]
  new_hashes <- current[is.na(idx)]

  history$last_seen_archive_date[known] <- archive_date
  history$last_seen_snapshot_id[known]  <- new_id
  history$n_snapshots_seen[known]       <- history$n_snapshots_seen[known] + 1L
  history$last_seen_release[known]            <- release_tag
  history$last_seen_source_update_date[known] <- source_update_date

  # DO NOT write first_seen_source_update_date here. For a feature that predates
  # this run the value is unknowable, not merely missing. Filling it in would
  # stamp 2025 features with a 2026 source date. This is defect B1.

  history$currently_present <- history$feature_hash %in% current

  if (length(new_hashes) > 0) {
    message(sprintf("%d new feature(s).", length(new_hashes)))
    geom <- summarise_features(data_path, hashes)
    geom <- geom[match(new_hashes, geom$feature_hash), , drop = FALSE]
    add <- data.frame(
      feature_hash = new_hashes,
      first_seen_archive_date = archive_date,
      last_seen_archive_date = archive_date,
      n_snapshots_seen = 1L,
      currently_present = TRUE,
      first_seen_snapshot_id = new_id,
      last_seen_snapshot_id = new_id,
      first_seen_release = release_tag,
      last_seen_release = release_tag,
      first_seen_source_update_date = source_update_date,
      last_seen_source_update_date = source_update_date,
      stringsAsFactors = FALSE
    )
    add <- cbind(add, geom[setdiff(names(geom), "feature_hash")])
    history <- rbind(history[names(HISTORY_COLS)], add[names(HISTORY_COLS)])
  }

  ledger <- rbind(ledger, data.frame(
    snapshot_id = new_id,
    archive_date = archive_date,
    commit = NA_character_,
    tag = release_tag,
    source_update_date = source_update_date,
    feature_set_hash = fsh,
    data_canonical_sha256 = data_sha,
    n_features = length(current),
    stringsAsFactors = FALSE
  ))

  history <- history[order(history$first_seen_archive_date, history$feature_hash), ]
  rownames(history) <- NULL

  write_table(history, history_path, HISTORY_COLS)
  write_table(ledger, ledger_path, LEDGER_COLS)
  message(sprintf("Snapshot %d applied: %d features total, %d present, %d new.",
                  new_id, nrow(history), length(current), length(new_hashes)))
  invisible(history)
}

# --------------------------------------------------------------------- main --

parse_args <- function(args) {
  p <- list(
    rebuild = FALSE,
    data_path = "tiger_mosquito_colonisation_in_france.geojson",
    metadata_path = "metadata.json",
    history_path = "feature_history.csv",
    ledger_path = "feature_history_snapshots.csv",
    cores = min(parallel::detectCores(), 8L)
  )
  for (a in args) {
    if (a %in% c("--rebuild", "-r"))       p$rebuild <- TRUE
    else if (startsWith(a, "--data="))     p$data_path <- sub("^--data=", "", a)
    else if (startsWith(a, "--metadata=")) p$metadata_path <- sub("^--metadata=", "", a)
    else if (startsWith(a, "--output="))   p$history_path <- sub("^--output=", "", a)
    else if (startsWith(a, "--ledger="))   p$ledger_path <- sub("^--ledger=", "", a)
    else if (startsWith(a, "--cores="))    p$cores <- as.integer(sub("^--cores=", "", a))
    else stop("Unknown argument: ", a, call. = FALSE)
  }
  p
}

main <- function() {
  p <- parse_args(commandArgs(trailingOnly = TRUE))
  if (p$rebuild) {
    rebuild_from_git_history(p$data_path, p$history_path, p$ledger_path, p$cores)
  } else {
    update_incrementally(p$data_path, p$metadata_path, p$history_path, p$ledger_path)
  }
}

if (!interactive()) main()
