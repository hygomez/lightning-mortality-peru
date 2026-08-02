repo_root <- function(start = getwd(), max_up = 8L) {
  cur <- normalizePath(start, winslash = "/", mustWork = TRUE)
  for (i in 0:max_up) {
    if (file.exists(file.path(cur, "config", "config.R")) &&
        file.exists(file.path(cur, "README.md"))) return(cur)
    nxt <- dirname(cur)
    if (identical(nxt, cur)) break
    cur <- nxt
  }
  stop("Repository root not found. Open RStudio in the repository folder.", call. = FALSE)
}

ensure_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
  if (length(missing)) {
    stop("Missing R packages: ", paste(missing, collapse = ", "),
         ". Install them before continuing.", call. = FALSE)
  }
}

safe_col <- function(dt, candidates, required = FALSE) {
  hit <- candidates[candidates %in% names(dt)]
  if (length(hit)) return(hit[1])
  if (required) stop("None of these columns was found: ", paste(candidates, collapse = ", "), call. = FALSE)
  NA_character_
}

norm_text <- function(x) {
  z <- as.character(x)
  nas <- is.na(z)
  z <- iconv(z, from = "", to = "ASCII//TRANSLIT", sub = "")
  z <- toupper(trimws(z))
  z[nas] <- NA_character_
  z
}

year_of <- function(x) {
  if (inherits(x, "Date") || inherits(x, "POSIXt")) return(as.integer(format(x, "%Y")))
  z <- as.character(x)
  out <- suppressWarnings(as.integer(substr(z, 1L, 4L)))
  bad <- is.na(out)
  if (any(bad)) {
    zz <- suppressWarnings(as.Date(z[bad]))
    out[bad] <- suppressWarnings(as.integer(format(zz, "%Y")))
  }
  out
}

month_of <- function(x) {
  if (inherits(x, "Date") || inherits(x, "POSIXt")) return(as.integer(format(x, "%m")))
  z <- as.character(x)
  out <- suppressWarnings(as.integer(substr(z, 6L, 7L)))
  bad <- is.na(out) | out < 1L | out > 12L
  if (any(bad)) {
    zz <- suppressWarnings(as.Date(z[bad]))
    out[bad] <- suppressWarnings(as.integer(format(zz, "%m")))
  }
  out
}

as_date_safe <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  suppressWarnings(as.Date(as.character(x)))
}

row_any_regex <- function(dt, cols, include, exclude = NULL, normalize = TRUE) {
  if (!length(cols)) return(rep(FALSE, nrow(dt)))
  ans <- lapply(cols, function(cc) {
    z <- if (normalize) norm_text(dt[[cc]]) else as.character(dt[[cc]])
    ok <- !is.na(z) & grepl(include, z, perl = TRUE)
    if (!is.null(exclude)) ok <- ok & !grepl(exclude, z, perl = TRUE)
    ok
  })
  Reduce(`|`, ans)
}

row_any_cie <- function(dt, cols, pattern) {
  if (!length(cols)) return(rep(FALSE, nrow(dt)))
  ans <- lapply(cols, function(cc) {
    z <- norm_text(dt[[cc]])
    z <- gsub("\\s+", "", z)
    !is.na(z) & grepl(pattern, z, perl = TRUE)
  })
  Reduce(`|`, ans)
}

collapse_nonempty <- function(dt, cols) {
  if (!length(cols)) return(rep("", nrow(dt)))
  out <- rep("", nrow(dt))
  for (cc in cols) {
    z <- trimws(as.character(dt[[cc]]))
    z[is.na(z)] <- ""
    add <- z != ""
    out[add] <- ifelse(out[add] == "", z[add], paste0(out[add], " || ", z[add]))
  }
  out
}

altitude_stratum <- function(x, breaks, labels) {
  cut(x, breaks = breaks, labels = labels, right = TRUE)
}

poisson_lower <- function(n, py) ifelse(n == 0, 0, 1e6 * qchisq(0.025, 2*n) / 2 / py)
poisson_upper <- function(n, py) 1e6 * qchisq(0.975, 2*(n+1)) / 2 / py

rate_ratio_ci <- function(n1, py1, n0, py0, label) {
  rr <- (n1/py1)/(n0/py0)
  se <- sqrt(1/n1 + 1/n0)
  data.table::data.table(
    comparison = label,
    RR = rr,
    CI_lower = exp(log(rr) - 1.96*se),
    CI_upper = exp(log(rr) + 1.96*se)
  )
}

write_csv_utf8 <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(x, path, bom = TRUE)
}

md5_row <- function(path) {
  info <- file.info(path)
  data.table::data.table(
    file = basename(path),
    bytes = as.numeric(info$size),
    md5 = unname(tools::md5sum(path))
  )
}

assert_expected <- function(actual, expected, label) {
  if (!identical(as.integer(actual), as.integer(expected))) {
    stop(label, ": expected ", expected, ", obtained ", actual, call. = FALSE)
  }
  invisible(TRUE)
}

classify_lightning_cases <- function(dt, text_cols, cie_cols) {
  # This pattern reproduces the locked, manually adjudicated manuscript cohort.
  # Do not broaden it without a new adjudication round.
  P_SPECIFIC <- paste(c(
    "RAYO", "FULGURACION", "FULGURADO", "FULMINAD", "CENTELLA",
    "DESCARGA ATMOSFERICA", "RELAMPAGO",
    "FULGOROCION", "FULJURACION", "FULBURACION",
    "ELECTROFULGURACION", "ELECTRIFULGURACION",
    "FULGORACION", "RARO EN VIVIENDA"
  ), collapse = "|")

  P_FALSE <- paste(c(
    "RESPIRAYO", "RAYOS X", "RAYO X", "X RAYO", "RAYOS UV",
    "ULTRAVIOLETA", "RAYOS GAMMA", "RAYOS SOLARES", "LASER", "RADIOTERAPIA"
  ), collapse = "|")

  specific_hit <- row_any_regex(dt, text_cols, P_SPECIFIC, P_FALSE, normalize = TRUE)
  storm_hit <- row_any_regex(dt, text_cols, "TORMENTA ELECTRICA", P_FALSE, normalize = TRUE)
  cie_hit <- row_any_cie(dt, cie_cols, "^(X33|T75\\.?0)")

  # Manual adjudication found one non-meteorological use of "tormenta electrica".
  # Do not exclude every record with a cardiac consequence: true lightning deaths
  # may also contain cardiac terms in the causal chain.
  all_text <- norm_text(collapse_nonempty(dt, text_cols))
  contextual_false_positive <-
    storm_hit & !specific_hit & !cie_hit &
    !is.na(all_text) &
    grepl("SHOCK SEPTICO", all_text, perl = TRUE) &
    grepl("NEUMONIA INTRAHOSPITALARIA", all_text, perl = TRUE) &
    grepl("INFARTO DE MIOCARDIO", all_text, perl = TRUE)

  text_hit <- (specific_hit | storm_hit) & !contextual_false_positive
  candidate_before_adjudication <- specific_hit | storm_hit | cie_hit
  final_case <- text_hit | cie_hit

  data.table::data.table(
    text_case = text_hit,
    cie_case = cie_hit,
    candidate_before_adjudication = candidate_before_adjudication,
    excluded_cardiac_storm = contextual_false_positive,
    final_case = final_case,
    case_source = data.table::fcase(
      text_hit & cie_hit, "text_and_cie",
      text_hit & !cie_hit, "text_only",
      !text_hit & cie_hit, "cie_only",
      default = "not_case"
    )
  )
}
