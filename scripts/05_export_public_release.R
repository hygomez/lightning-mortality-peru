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

safe_tables <- list.files(PATHS$tables, "\\.csv$", full.names = TRUE)
unsafe_pattern <- "ID_PERSONA|textos_causales|codigos_cie|case_level|individual"
for (f in safe_tables) {
  header <- tryCatch(names(fread(f, nrows = 0)), error = function(e) character())
  if (any(grepl(unsafe_pattern, header, ignore.case = TRUE))) next
  file.copy(f, file.path(release_dir, "aggregate-data", basename(f)), overwrite = TRUE)
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
zip_abs <- normalizePath(zipfile, winslash = "/", mustWork = FALSE)

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
