options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages("data.table")
suppressPackageStartupMessages(library(data.table))

actual_file <- file.path(PATHS$tables, "results_summary.csv")
expected_file <- "results/reference/expected_results.csv"
if (!file.exists(actual_file)) stop("Run scripts/02_run_analysis.R first.", call. = FALSE)
actual <- fread(actual_file)
setnames(actual, "value", "value_actual")
expected <- fread(expected_file)
qc <- merge(expected, actual, by = "indicator", all.x = TRUE)
qc[, absolute_difference := abs(value_actual - value_expected)]
qc[, status := fifelse(is.na(value_actual), "FAIL", fifelse(absolute_difference <= tolerance, "PASS", "FAIL"))]

mandatory_figures <- c("Figure_1_altitude_mortality.png", "Figure_2_seasonality.png",
                       "Figure_3_age_sex.png", "Figure_4_density_mortality.png")
figure_qc <- data.table(
  indicator = paste0("figure_exists_", mandatory_figures),
  value_expected = 1,
  tolerance = 0,
  value_actual = as.integer(file.exists(file.path(PATHS$figures, mandatory_figures))),
  absolute_difference = NA_real_,
  status = ifelse(file.exists(file.path(PATHS$figures, mandatory_figures)), "PASS", "FAIL")
)
map_status <- data.table(
  indicator = "district_map_exists",
  value_expected = 1,
  tolerance = 0,
  value_actual = as.integer(file.exists(file.path(PATHS$figures, "Figure_5_district_posterior_rates.png"))),
  absolute_difference = NA_real_,
  status = ifelse(file.exists(file.path(PATHS$figures, "Figure_5_district_posterior_rates.png")), "PASS", "WARN")
)
qc_all <- rbind(qc, figure_qc, map_status, fill = TRUE)
dir.create(PATHS$qc, recursive = TRUE, showWarnings = FALSE)
write_csv_utf8(qc_all, file.path(PATHS$qc, "qc_report.csv"))

summary_lines <- c(
  "REPRODUCIBILITY QUALITY CONTROL",
  paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  paste("PASS:", qc_all[status == "PASS", .N]),
  paste("WARN:", qc_all[status == "WARN", .N]),
  paste("FAIL:", qc_all[status == "FAIL", .N]),
  "",
  paste(qc_all$status, qc_all$indicator,
        ifelse(is.na(qc_all$value_actual), "", paste0(" actual=", signif(qc_all$value_actual, 8))),
        ifelse(is.na(qc_all$value_expected), "", paste0(" expected=", signif(qc_all$value_expected, 8))))
)
writeLines(summary_lines, file.path(PATHS$qc, "qc_summary.txt"), useBytes = TRUE)
cat(paste(summary_lines, collapse = "\n"), "\n")
if (qc_all[status == "FAIL", .N] > 0) stop("Quality control failed. Do not release the repository.", call. = FALSE)
