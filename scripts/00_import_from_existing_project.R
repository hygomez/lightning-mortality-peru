options(stringsAsFactors = FALSE)
source("R/functions.R")
ROOT <- repo_root()
setwd(ROOT)
source("config/config.R")

SRC <- Sys.getenv("SOURCE_PROJECT_ROOT", unset = "")
if (!nzchar(SRC)) {
  stop(
    "Set SOURCE_PROJECT_ROOT to the local project containing authorized source data.",
    call. = FALSE
  )
}
SRC <- normalizePath(SRC, winslash = "/", mustWork = TRUE)
cat("Source project:", SRC, "\n")
cat("Repository:", ROOT, "\n")

copy_required <- function(from, to) {
  src <- file.path(SRC, from)
  if (!file.exists(src)) stop("Required source file not found: ", src, call. = FALSE)
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(src, to, overwrite = TRUE)
  if (!ok) stop("Could not copy: ", src, call. = FALSE)
  cat("Copied:", from, "->", to, "\n")
}

copy_required("data/processed/sinadef_limpio.rds", PATHS$mortality)
copy_required("data/processed/poblacion_distrital.csv", PATHS$population)
copy_required("data/processed/distritos_altitud.csv", PATHS$altitude)
copy_required("output/tables/rayo_densidad_distrito.csv", PATHS$density)

# Optional spatial boundary conversion for the publication map.
shp <- list.files(file.path(SRC, "data", "raw", "shp"), "\\.shp$",
                  recursive = TRUE, full.names = TRUE)
if (length(shp) && requireNamespace("sf", quietly = TRUE)) {
  selected <- NULL
  for (candidate in shp) {
    x_try <- try(sf::st_read(candidate, quiet = TRUE), silent = TRUE)
    if (inherits(x_try, "try-error")) next
    has_ubigeo <- any(c("UBIGEO", "ubigeo", "IDDIST", "iddist", "CODIGO_DIS") %in% names(x_try))
    if (has_ubigeo && nrow(x_try) > 1000) { selected <- x_try; break }
  }
  if (!is.null(selected)) {
    if (file.exists(PATHS$districts_gpkg)) file.remove(PATHS$districts_gpkg)
    sf::st_write(selected, PATHS$districts_gpkg, quiet = TRUE)
    cat("District boundaries converted to:", PATHS$districts_gpkg, "\n")
  } else {
    cat("WARNING: no national district boundary layer could be identified.\n")
  }
} else if (!length(shp)) {
  cat("WARNING: no district shapefile found; the map script will be skipped.\n")
} else {
  cat("WARNING: install package 'sf' to convert the district shapefile.\n")
}

manifest <- data.table::rbindlist(lapply(c(PATHS$mortality, PATHS$population,
                                           PATHS$altitude, PATHS$density), md5_row))
dir.create("data/restricted", recursive = TRUE, showWarnings = FALSE)
data.table::fwrite(manifest, "data/restricted/import_manifest.csv")

cat("\nImport completed. Restricted mortality data remain excluded by .gitignore.\n")
cat("Next command: source(\"scripts/run_all.R\")\n")
