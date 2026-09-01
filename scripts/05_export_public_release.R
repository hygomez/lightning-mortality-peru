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

# --- P1 (v2.0.0): exclusion del line list distrito-fecha ------------------------
#
# DEFECTO CORREGIDO. El filtro de la v1.0.0 miraba solo los NOMBRES DE COLUMNA
# contra unsafe_pattern. `10_multiple_victim_events.csv` tiene cabecera
# "analysis_ubigeo, analysis_date, N": ninguno de esos nombres casa con el patron,
# de modo que el archivo pasaba el filtro y entraba en el ZIP publico.
#
# El ZIP v1.0.0 publicado en Zenodo NO lo contiene, porque se construyo desde un
# clon limpio donde el archivo -- que esta en .gitignore -- no existia. Pero el
# archivo SI lo produce 02_run_analysis.R en cada corrida, asi que cualquiera que
# clonase el repositorio y ejecutase run_all.R generaba un release con el line
# list dentro. Ocurrio de hecho en release/v1.0.0/aggregate-data/ el 2026-08-25.
#
# Un par distrito-fecha con 2 o 3 muertes es cuasi-identificador: en un distrito
# rural, la fecha exacta de un evento con varias victimas basta para localizar a
# las personas en la prensa local o en el registro civil. Se excluye por NOMBRE,
# que es una regla que no depende de heuristicas, y ademas por ESTRUCTURA.
DENY_BY_NAME <- c("10_multiple_victim_events.csv")
unsafe_pattern <- "ID_PERSONA|textos_causales|codigos_cie|case_level|individual"
# Cualquier tabla con una columna de fecha esta a nivel de registro o de evento:
# el release solo publica agregados, de modo que ninguna debe llevarla.
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
  cat("Excluidas del release publico por privacidad:\n")
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
# normalizePath() sobre un archivo que AUN NO EXISTE devuelve la ruta relativa tal
# cual. Como zip::zipr() usa root = release_dir, se situa en otro directorio y esa
# ruta relativa deja de resolver: "Cannot open zip file for writing". Se construye
# la ruta absoluta a partir del directorio contenedor, que si existe.
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

# --- Post-condicion de privacidad: se comprueba lo COPIADO, no lo que se penso --
# El filtro de arriba decide; esto verifica el resultado. Si alguna vez divergen,
# el release no se crea.
copiados <- list.files(release_dir, recursive = TRUE, full.names = TRUE)
fugas <- basename(copiados)[basename(copiados) %in% DENY_BY_NAME]
con_fecha <- character(0)
for (f in copiados[grepl("\\.csv$", copiados)]) {
  h <- tryCatch(names(fread(f, nrows = 0)), error = function(e) character())
  if (any(grepl(date_pattern, h, ignore.case = TRUE))) con_fecha <- c(con_fecha, basename(f))
}
if (length(fugas) || length(con_fecha)) {
  stop("FUGA DE PRIVACIDAD: el release contiene ",
       paste(unique(c(fugas, con_fecha)), collapse = ", "),
       ". No se crea el paquete.", call. = FALSE)
}
cat(sprintf("Post-condicion de privacidad: %d archivos revisados, 0 con nombre vetado, 0 con columna de fecha.\n",
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
