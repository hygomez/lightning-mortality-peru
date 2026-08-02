options(stringsAsFactors = FALSE)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT)
writeLines(capture.output(sessionInfo()), "session-info.txt", useBytes = TRUE)
if (!requireNamespace("renv", quietly = TRUE)) {
  stop("Install package 'renv', then rerun this script to create renv.lock.", call. = FALSE)
}
packages <- c("data.table", "ggplot2", "sf", "terra", "jsonlite", "renv")
renv::snapshot(packages = packages, prompt = FALSE)
cat("Created session-info.txt and renv.lock\n")
