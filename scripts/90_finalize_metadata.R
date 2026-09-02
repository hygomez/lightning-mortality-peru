options(stringsAsFactors = FALSE)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages(c("data.table", "jsonlite"))
suppressPackageStartupMessages(library(data.table))

authors <- fread("metadata/authors.csv", na.strings = c("", "NA"))
meta <- fread("metadata/repository_metadata.csv", na.strings = c("", "NA"))
# La columna se llama "field", no "key". Con `key` data.table resolvia el nombre a
# su propia funcion key() y la comparacion fallaba: el script no podia ejecutarse
# contra su propio archivo de metadatos.
meta_value <- function(k) { x <- meta[field == k, value]; if (!length(x)) NA_character_ else as.character(x[1]) }

authors[, include_as_author := toupper(trimws(as.character(include_as_author))) %in% c("TRUE","YES","SI","1")]
a <- authors[include_as_author == TRUE][order(order)]
required <- c("given_names", "family_names", "affiliation")
if (!nrow(a)) stop("No authors are marked include_as_author=TRUE.", call. = FALSE)
for (cc in required) if (any(is.na(a[[cc]]) | trimws(a[[cc]]) == "")) stop("Complete author field: ", cc, call. = FALSE)
if (any(!is.na(a$orcid) & a$orcid != "" & !grepl("^https://orcid.org/[0-9X-]{19}$", a$orcid))) stop("One or more ORCID values are invalid.", call. = FALSE)

title <- meta_value("title_en")
version <- meta_value("version")
description <- meta_value("description_en")
keywords <- trimws(strsplit(meta_value("keywords"), ";", fixed = TRUE)[[1]])
if (any(is.na(c(title, version, description)))) stop("Complete title_en, version and description_en in repository_metadata.csv", call. = FALSE)

cff <- c(
  "cff-version: 1.2.0",
  # Se cita el DOI de CONCEPTO: resuelve siempre a la version mas reciente, de modo
  # que la referencia no queda obsoleta al archivar una revision.
  "message: \"If you use this software, please cite the concept DOI, which always resolves to the latest version, and the associated article.\"",
  paste0("title: \"", gsub('"', '\\\\"', title), "\""),
  "type: software",
  paste0("version: \"", version, "\""),
  paste0("date-released: ", format(Sys.Date(), "%Y-%m-%d")),
  "authors:"
)
for (i in seq_len(nrow(a))) {
  cff <- c(cff,
    paste0("  - family-names: \"", gsub('"', '\\\\"', a$family_names[i]), "\""),
    paste0("    given-names: \"", gsub('"', '\\\\"', a$given_names[i]), "\""),
    paste0("    affiliation: \"", gsub('"', '\\\\"', a$affiliation[i]), "\""))
  if (!is.na(a$orcid[i]) && a$orcid[i] != "") cff <- c(cff, paste0("    orcid: \"", a$orcid[i], "\""))
}
if (!is.na(meta_value("github_url")) && meta_value("github_url") != "")
  cff <- c(cff, paste0("url: \"", meta_value("github_url"), "\""),
                paste0("repository-code: \"", meta_value("github_url"), "\""))
if (!is.na(meta_value("zenodo_doi")) && meta_value("zenodo_doi") != "")
  cff <- c(cff, paste0("doi: \"", meta_value("zenodo_doi"), "\""))
# El autor de correspondencia y la licencia tambien salen de los metadatos: antes
# se manenian a mano en CITATION.cff y el generador los borraba en cada corrida.
corr <- meta_value("corresponding_author")
if (!is.na(corr) && corr != "") {
  ca <- a[paste(given_names, family_names) == corr | family_names == sub("^\\S+\\s+", "", corr)][1]
  if (nrow(ca) && !is.na(ca$family_names)) cff <- c(cff, "contact:",
    paste0("  - family-names: \"", ca$family_names, "\""),
    paste0("    given-names: \"", ca$given_names, "\""),
    paste0("    email: \"", meta_value("corresponding_email"), "\""))
}
if (!is.na(meta_value("license")) && meta_value("license") != "")
  cff <- c(cff, paste0("license: ", meta_value("license")))
cff <- c(cff, "keywords:", paste0("  - ", keywords))
writeLines(cff, "CITATION.cff", useBytes = TRUE)

creators <- lapply(seq_len(nrow(a)), function(i) {
  x <- list(name = paste0(a$family_names[i], ", ", a$given_names[i]), affiliation = a$affiliation[i])
  if (!is.na(a$orcid[i]) && a$orcid[i] != "") x$orcid <- sub("https://orcid.org/", "", a$orcid[i], fixed = TRUE)
  x
})
zen <- list(
  title = title,
  upload_type = "software",
  description = description,
  creators = creators,
  access_right = "open",
  license = "mit",
  keywords = keywords,
  version = version
)
jsonlite::write_json(zen, ".zenodo.json", auto_unbox = TRUE, pretty = TRUE)

# repository_manifest.csv NO lo producia ningun script: se mantenia a mano y
# quedaba obsoleto en cuanto cambiaba cualquier archivo. Se regenera aqui sobre
# los archivos efectivamente versionados, que es lo que se archiva.
tracked <- system2("git", c("ls-files"), stdout = TRUE)
tracked <- tracked[file.exists(tracked)]
# A manifest cannot seal files that change after it is written. Three are excluded
# for that reason, and the exclusion is explicit so it is auditable:
#   - repository_manifest.csv: its own md5 changes as it is written.
#   - renv.lock and session-info.txt: 99_freeze_environment.R writes them AFTER
#     this script runs (see run_all.R), so any entry here would be one run stale.
# Everything else in the repository is sealed.
WRITTEN_AFTER_THIS <- c("repository_manifest.csv", "renv.lock", "session-info.txt")
tracked <- setdiff(tracked, WRITTEN_AFTER_THIS)
manifest <- data.table(
  file = tracked,
  bytes = file.size(tracked),
  md5 = unname(tools::md5sum(tracked)))
setorder(manifest, file)
write_csv_utf8(manifest, "repository_manifest.csv")

cat(sprintf("Generated CITATION.cff, .zenodo.json and repository_manifest.csv (%d files)\n",
            nrow(manifest)))
