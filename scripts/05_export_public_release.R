options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages("data.table")
suppressPackageStartupMessages(library(data.table))

qc_file <- file.path(PATHS$qc, "qc_report.csv")
if (!file.exists(qc_file)) stop("Run scripts/04_quality_control.R first.", call. = FALSE)
qc <- fread(qc_file)
if (qc[status == "FAIL", .N]) stop("QC contains failures; release not created.", call. = FALSE)

release_dir <- file.path("release", paste0("v", REPOSITORY_VERSION))
if (dir.exists(release_dir)) unlink(release_dir, recursive = TRUE)
dir.create(file.path(release_dir, "aggregate-data"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(release_dir, "figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(release_dir, "results"), recursive = TRUE, showWarnings = FALSE)

# --- P1 (v2.0.0): exclusion of the district-date line list ---------------------
#
# DEFECT FIXED (REP-016). The v1.0.0 filter inspected only COLUMN NAMES against
# unsafe_pattern. `10_multiple_victim_events.csv` has the header
# "analysis_ubigeo, analysis_date, N": none of those names matches the pattern, so
# the file passed the filter and entered the public ZIP.
#
# The v1.0.0 ZIP published on Zenodo does NOT contain it, because it was built from
# a clean clone where the file -- which is in .gitignore -- did not exist. But
# 02_run_analysis.R does produce the file on every run, so a reproduction that
# cloned the repository and ran run_all.R generated a release with the line list
# inside.
#
# A district-date pair with 2 or 3 deaths is quasi-identifying: in a rural district,
# the exact date of a multi-victim event is enough to locate the individuals through
# local press or the civil registry. It is excluded BY NAME, which is a rule that
# does not depend on heuristics, and also BY STRUCTURE.
DENY_BY_NAME <- c("10_multiple_victim_events.csv")
unsafe_pattern <- "ID_PERSONA|textos_causales|codigos_cie|case_level|individual"
# Any table with a date column is at record or event level: the release publishes
# aggregates only, so none should carry one.
date_pattern <- "date|fecha"

safe_tables <- list.files(PATHS$tables, "\\.csv$", full.names = TRUE)
excluidas <- character(0)
for (f in safe_tables) {
  nombre <- basename(f)
  header <- tryCatch(names(fread(f, nrows = 0)), error = function(e) character())
  motivo <- if (nombre %in% DENY_BY_NAME) "lista de exclusion por nombre"
            else if (any(grepl(unsafe_pattern, header, ignore.case = TRUE))) "columna de nivel individual"
            else if (any(grepl(date_pattern, header, ignore.case = TRUE))) "columna de fecha (nivel evento)"
            else NA_character_
  if (!is.na(motivo)) {
    excluidas <- c(excluidas, sprintf("%s (%s)", nombre, motivo))
    next
  }
  file.copy(f, file.path(release_dir, "aggregate-data", basename(f)), overwrite = TRUE)
}
if (length(excluidas)) {
  cat("Excluded from the public release on privacy grounds:\n")
  cat(paste0("  - ", excluidas, collapse = "\n"), "\n")
}

figs <- list.files(PATHS$figures, "\\.(png|tiff)$", full.names = TRUE, ignore.case = TRUE)
file.copy(figs, file.path(release_dir, "figures", basename(figs)), overwrite = TRUE)
res <- list.files("results", "\\.(md|csv)$", full.names = TRUE)
file.copy(res, file.path(release_dir, "results", basename(res)), overwrite = TRUE)
file.copy(qc_file, file.path(release_dir, "qc_report.csv"), overwrite = TRUE)

writeLines(capture.output(sessionInfo()), file.path(release_dir, "session-info.txt"))
all_files <- list.files(release_dir, recursive = TRUE, full.names = TRUE)
checksums <- rbindlist(lapply(all_files, function(f) {
  rel <- substring(f, nchar(release_dir) + 2L)
  data.table(file = rel, bytes = file.info(f)$size, md5 = unname(tools::md5sum(f)))
}))
write_csv_utf8(checksums, file.path(release_dir, "checksums.csv"))

writeLines(c(
  "This release contains non-identifying aggregate data, figures, QC results, and environment information.",
  "It intentionally excludes individual-level mortality records, personal identifiers, and free-text cause-of-death chains.",
  paste("Repository version:", REPOSITORY_VERSION)
), file.path(release_dir, "README.txt"))

zipfile <- file.path("release", paste0(
  "lightning-mortality-peru-public-aggregates-v",
  REPOSITORY_VERSION, ".zip"
))
# normalizePath() on a file that DOES NOT YET EXIST returns the relative path
# unchanged. Because zip::zipr() uses root = release_dir it moves to another
# directory and that relative path stops resolving: "Cannot open zip file for
# writing". The absolute path is built from the containing directory, which exists.
zip_abs <- file.path(normalizePath(dirname(zipfile), winslash = "/", mustWork = TRUE),
                     basename(zipfile))

if (file.exists(zip_abs)) unlink(zip_abs)

files_rel <- list.files(
  release_dir,
  recursive = TRUE,
  full.names = FALSE,
  all.files = FALSE,
  include.dirs = FALSE
)

if (!length(files_rel)) {
  stop("The public release directory is empty.", call. = FALSE)
}

# --- Privacy post-condition: check what was COPIED, not what was intended ------
# The filter above decides; this verifies the outcome. If the two ever diverge, the
# release is not created.
copiados <- list.files(release_dir, recursive = TRUE, full.names = TRUE)
fugas <- basename(copiados)[basename(copiados) %in% DENY_BY_NAME]
con_fecha <- character(0)
for (f in copiados[grepl("\\.csv$", copiados)]) {
  h <- tryCatch(names(fread(f, nrows = 0)), error = function(e) character())
  if (any(grepl(date_pattern, h, ignore.case = TRUE))) con_fecha <- c(con_fecha, basename(f))
}
if (length(fugas) || length(con_fecha)) {
  stop("PRIVACY LEAK: the release contains ",
       paste(unique(c(fugas, con_fecha)), collapse = ", "),
       ". The package is not created.", call. = FALSE)
}
cat(sprintf("Privacy post-condition: %d files checked, 0 denied by name, 0 with a date column.\n",
            length(copiados)))

zip::zipr(
  zipfile = zip_abs,
  files = files_rel,
  root = release_dir,
  include_directories = FALSE
)

if (!file.exists(zip_abs) || is.na(file.info(zip_abs)$size) ||
    file.info(zip_abs)$size <= 0) {
  stop("The public ZIP archive was not created correctly.", call. = FALSE)
}

zip_listing <- utils::unzip(zip_abs, list = TRUE)
if (!nrow(zip_listing)) {
  stop("The public ZIP archive has no entries.", call. = FALSE)
}

cat("Public aggregate release created:", zipfile, "\n")
cat("Archive size (bytes):", file.info(zip_abs)$size, "\n")
cat("Files in archive:", nrow(zip_listing), "\n")
