#!/usr/bin/env Rscript

# scripts/fetch_data.R
#
# Robustly fetches the tiger mosquito colonisation data from ANSES with:
# - Configurable connection timeout
# - Multi-attempt retry loop with exponential backoff and jitter
# - Custom User-Agent header
# - Response validation (verifies presence of commune data and valid GeoJSON)
# - Single-fetch output for both GeoJSON and source page metadata

suppressPackageStartupMessages({
  library(alboFr)
  library(jsonlite)
  library(RcppSimdJson)
})

SOURCE_URL <- "https://signalement-moustique.anses.fr/signalement_albopictus/colonisees"
DEFAULT_USER_AGENT <- "alboFr-data-archive/1.0 (+https://github.com/e-kotov/alboFr-data-archive)"

parse_cli_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opts <- list(
    output = "tiger_mosquito_colonisation_in_france.geojson",
    page_output = "raw_source_page.html",
    max_retries = 5L,
    timeout = 180L,
    initial_delay = 10.0,
    backoff_factor = 2.0
  )
  for (arg in args) {
    if (startsWith(arg, "--output=")) {
      opts$output <- sub("^--output=", "", arg)
    } else if (startsWith(arg, "--page-output=")) {
      opts$page_output <- sub("^--page-output=", "", arg)
    } else if (startsWith(arg, "--max-retries=")) {
      opts$max_retries <- as.integer(sub("^--max-retries=", "", arg))
    } else if (startsWith(arg, "--timeout=")) {
      opts$timeout <- as.integer(sub("^--timeout=", "", arg))
    } else if (startsWith(arg, "--initial-delay=")) {
      opts$initial_delay <- as.numeric(sub("^--initial-delay=", "", arg))
    }
  }
  opts
}

fetch_source_page <- function(url, max_retries, timeout_sec, initial_delay, backoff_factor, user_agent) {
  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = timeout_sec)

  last_error <- NULL
  for (attempt in seq_len(max_retries)) {
    message(sprintf("[attempt %d/%d] Fetching %s (timeout: %ds)...",
                    attempt, max_retries, url, timeout_sec))
    t0 <- proc.time()
    
    res <- tryCatch({
      con <- url(url, headers = c("User-Agent" = user_agent))
      on.exit(close(con), add = TRUE)
      lines <- readLines(con, warn = FALSE, encoding = "UTF-8")
      paste(lines, collapse = "\n")
    }, error = function(e) {
      e
    })

    elapsed <- (proc.time() - t0)[3]

    if (is.character(res) && length(res) == 1L && nzchar(res)) {
      if (grepl("var result_commune =", res, fixed = TRUE)) {
        message(sprintf("Fetch successful on attempt %d (%.2fs, %d bytes).",
                        attempt, elapsed, nchar(res)))
        return(res)
      } else {
        last_error <- "Response received but missing expected 'var result_commune =' marker"
        warning(sprintf("Attempt %d returned unexpected content: %s", attempt, last_error), immediate. = TRUE)
      }
    } else if (inherits(res, "error")) {
      last_error <- conditionMessage(res)
      warning(sprintf("Attempt %d failed (%.2fs): %s", attempt, elapsed, last_error), immediate. = TRUE)
    }

    if (attempt < max_retries) {
      delay <- initial_delay * (backoff_factor ^ (attempt - 1)) + stats::runif(1, 0, 5)
      message(sprintf("Waiting %.1f seconds before retry...", delay))
      Sys.sleep(delay)
    }
  }

  stop(sprintf("Failed to fetch %s after %d attempts. Last error: %s",
               url, max_retries, last_error), call. = FALSE)
}

extract_geojson_from_page <- function(page_text) {
  lines <- strsplit(page_text, "\n", fixed = TRUE)[[1]]
  data_line_idx <- grep("var result_commune =", lines)
  if (length(data_line_idx) == 0) {
    stop("Could not locate 'var result_commune =' in source page.", call. = FALSE)
  }
  sp_data_line <- lines[data_line_idx[[1]]]
  sp_data_json <- sub("^\\s*var result_commune\\s*=\\s*", "", sp_data_line)
  sp_data_list <- RcppSimdJson::fparse(sp_data_json)
  if (!is.list(sp_data_list) || length(sp_data_list) == 0) {
    stop("Parsed commune data list is empty or invalid.", call. = FALSE)
  }

  coords_strings <- vapply(sp_data_list, function(x) {
    co <- x[["coordonnees"]]
    if (is.null(co)) "[]" else as.character(co)
  }, character(1))

  corrupt_items <- which(coords_strings == "[]" | is.na(coords_strings))
  items_with_geometry <- if (length(corrupt_items) > 0) sp_data_list[-corrupt_items] else sp_data_list

  if (length(items_with_geometry) == 0) {
    stop("No valid geometry items found in commune data.", call. = FALSE)
  }

  features_list <- lapply(items_with_geometry, alboFr:::js_coords_to_geojson)
  geojson_full <- alboFr:::build_geojson_full(features_list)

  # Validate GeoJSON structure
  parsed <- jsonlite::fromJSON(geojson_full, simplifyVector = FALSE)
  if (!identical(parsed$type, "FeatureCollection") || length(parsed$features) == 0) {
    stop("Built GeoJSON is not a valid non-empty FeatureCollection.", call. = FALSE)
  }

  geojson_full
}

main <- function() {
  opts <- parse_cli_args()

  page_text <- fetch_source_page(
    url = SOURCE_URL,
    max_retries = opts$max_retries,
    timeout_sec = opts$timeout,
    initial_delay = opts$initial_delay,
    backoff_factor = opts$backoff_factor,
    user_agent = DEFAULT_USER_AGENT
  )

  if (nzchar(opts$page_output)) {
    writeLines(page_text, opts$page_output, useBytes = TRUE)
  }

  geojson_text <- extract_geojson_from_page(page_text)
  writeLines(geojson_text, opts$output, useBytes = TRUE)
  message(sprintf("Successfully written GeoJSON to %s", opts$output))
}

if (sys.nframe() == 0L) {
  main()
}
