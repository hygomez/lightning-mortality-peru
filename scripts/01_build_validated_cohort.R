options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root()
setwd(ROOT)
source("config/config.R")
ensure_packages("data.table")
suppressPackageStartupMessages(library(data.table))

for (p in c(PATHS$mortality, PATHS$altitude)) {
  if (!file.exists(p)) stop("Missing input: ", p, ". Run scripts/00_import_from_existing_project.R", call. = FALSE)
}

dir.create(PATHS$public_derived, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(PATHS$cohort_national), recursive = TRUE, showWarnings = FALSE)
dir.create(PATHS$logs, recursive = TRUE, showWarnings = FALSE)

sin <- as.data.table(readRDS(PATHS$mortality))
alt <- fread(PATHS$altitude, colClasses = list(character = "UBIGEO"))

fecha_col <- safe_col(sin, c("fecha", "FECHA", "FECHA.FALLECIMIENTO"), TRUE)
ubigeo_col <- safe_col(sin, c("ubigeo_inei", "UBIGEO", "ubigeo"), TRUE)
text_cols <- grep("^DEBIDO", names(sin), value = TRUE, ignore.case = TRUE)
cie_cols <- grep("CAUSA.*CIE|CIE.*CAUSA", names(sin), value = TRUE, ignore.case = TRUE)
if (!length(text_cols) || !length(cie_cols)) stop("Cause-text or ICD columns were not found.", call. = FALSE)

sin[, analysis_year := year_of(get(fecha_col))]
sin <- sin[analysis_year %between% c(ANALYSIS$start_year, ANALYSIS$end_year)]
sin[, analysis_date := as_date_safe(get(fecha_col))]
sin[, analysis_ubigeo := trimws(as.character(get(ubigeo_col)))]
sin[analysis_ubigeo == "", analysis_ubigeo := NA_character_]

cls <- classify_lightning_cases(sin, text_cols, cie_cols)
sin <- cbind(sin, cls)

alt_keep <- intersect(c("UBIGEO", "altitud", "DISTRITO", "PROVINCIA", "DEPARTAMEN", "lon", "lat"), names(alt))
alt_min <- unique(alt[, ..alt_keep], by = "UBIGEO")
overlap <- intersect(setdiff(alt_keep, "UBIGEO"), names(sin))
if (length(overlap)) sin[, (overlap) := NULL]
sin <- merge(sin, alt_min, by.x = "analysis_ubigeo", by.y = "UBIGEO", all.x = TRUE, sort = FALSE)

national <- sin[final_case == TRUE]
geographic <- national[!is.na(altitud)]
# REP-007 (parte 1): el paso de la cohorte nacional a la geografica descarta los
# casos sin altitud. Se avisa de forma explicita en lugar de perderlos en silencio.
if (nrow(national) > nrow(geographic)) {
  perdidos <- national[is.na(altitud)]
  message(sprintf(
    "AVISO REP-007: %d de %d casos validados no tienen altitud y quedan fuera de la cohorte geografica (UBIGEO: %s). Se conservan en los analisis nacionales demograficos, temporales y de circunstancia.",
    nrow(perdidos), nrow(national),
    paste(ifelse(is.na(perdidos$analysis_ubigeo) | perdidos$analysis_ubigeo == "",
                 "<sin ubigeo>", perdidos$analysis_ubigeo), collapse = ", ")))
}
geographic[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
national[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]

summary <- data.table(
  indicator = c(
    "source_records_2017_2024", "candidates_before_context_adjudication",
    "excluded_cardiac_storm", "national_cases", "geographic_cases",
    "missing_altitude", "high_altitude_cases", "text_only_cases",
    "cie_only_cases", "text_and_cie_cases"
  ),
  value = c(
    nrow(sin), sin[candidate_before_adjudication == TRUE, .N],
    sin[excluded_cardiac_storm == TRUE, .N], nrow(national), nrow(geographic),
    nrow(national) - nrow(geographic), geographic[estrato == ">3500", .N],
    national[case_source == "text_only", .N],
    national[case_source == "cie_only", .N],
    national[case_source == "text_and_cie", .N]
  )
)
print(summary)

assert_expected(summary[indicator == "candidates_before_context_adjudication", value], EXPECTED$candidates_before_context_adjudication, "Candidates")
assert_expected(summary[indicator == "excluded_cardiac_storm", value], EXPECTED$excluded_cardiac_storm, "Cardiac storm exclusions")
assert_expected(nrow(national), EXPECTED$national_cases, "National cases")
assert_expected(nrow(geographic), EXPECTED$geographic_cases, "Geographic cases")
assert_expected(geographic[estrato == ">3500", .N], EXPECTED$high_altitude_cases, "High-altitude cases")
assert_expected(national[case_source == "text_only", .N], EXPECTED$text_only_cases, "Text-only cases")
assert_expected(national[case_source == "cie_only", .N], EXPECTED$cie_only_cases, "ICD-only cases")
assert_expected(national[case_source == "text_and_cie", .N], EXPECTED$text_and_cie_cases, "Text-and-ICD cases")

saveRDS(national, PATHS$cohort_national)
saveRDS(geographic, PATHS$cohort_geographic)
write_csv_utf8(summary, file.path(PATHS$public_derived, "case_definition_summary.csv"))

# Public audit trail contains counts only, never identifiers or free-text chains.
#
# REP-001: la v1.0.0 sellaba solo dos archivos y no declaraba el terminador de
# linea. Un md5 de un CSV cambia por completo si el archivo viaja con CRLF en vez
# de LF, de modo que un replicador en Windows veia "checksum no coincide" sobre un
# archivo cuyo CONTENIDO era identico. Ahora se sellan los cuatro insumos, se
# declara el terminador de cada uno, y para los de texto se anade un md5 calculado
# sobre el contenido NORMALIZADO a LF: ese segundo valor es invariante frente al
# transporte y es el que un replicador debe comparar.
is_text <- function(path) grepl("\\.(csv|txt|md|R|r|py|json|cff|ya?ml)$", path)
line_ending_of <- function(path) {
  # Solo tiene sentido en archivos de texto: un RDS comprimido contiene bytes 0x0D
  # por azar y se reportaria como CRLF sin serlo.
  if (!is_text(path)) return(NA_character_)
  raw <- readBin(path, "raw", n = min(file.size(path), 1e6))
  if (any(raw == as.raw(13))) "CRLF" else "LF"
}
md5_lf <- function(path) {
  if (!is_text(path)) return(NA_character_)
  raw <- readBin(path, "raw", n = file.size(path))
  tmp <- tempfile(); on.exit(unlink(tmp), add = TRUE)
  writeBin(raw[raw != as.raw(13)], tmp)          # elimina CR, deja LF
  unname(tools::md5sum(tmp))
}
source_manifest <- rbindlist(lapply(
  c(PATHS$mortality, PATHS$altitude, PATHS$population, PATHS$density), md5_row))
source_manifest[, path := c(PATHS$mortality, PATHS$altitude, PATHS$population, PATHS$density)]
source_manifest[, line_ending := vapply(path, line_ending_of, character(1))]
source_manifest[, md5_normalized_lf := vapply(path, md5_lf, character(1))]
source_manifest[, path := NULL]
write_csv_utf8(source_manifest, file.path(PATHS$public_derived, "input_checksums_local_run.csv"))

cat("Validated national cohort:", nrow(national), "\n")
cat("Validated geographic cohort:", nrow(geographic), "\n")
cat("No row-level CSV was exported.\n")
