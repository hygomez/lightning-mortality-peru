options(stringsAsFactors = FALSE)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages(c("data.table", "jsonlite"))
suppressPackageStartupMessages(library(data.table))

authors <- fread("metadata/authors.csv", na.strings = c("", "NA"))
meta <- fread("metadata/repository_metadata.csv", na.strings = c("", "NA"))
meta_value <- function(k) { x <- meta[key == k, value]; if (!length(x)) NA_character_ else as.character(x[1]) }

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
  "message: \"If you use this code, please cite the archived software release and the associated article.\"",
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
if (!is.na(meta_value("github_url")) && meta_value("github_url") != "") cff <- c(cff, paste0("repository-code: \"", meta_value("github_url"), "\""))
if (!is.na(meta_value("zenodo_doi")) && meta_value("zenodo_doi") != "") cff <- c(cff, paste0("doi: \"", meta_value("zenodo_doi"), "\""))
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
cat("Generated CITATION.cff and .zenodo.json\n")
