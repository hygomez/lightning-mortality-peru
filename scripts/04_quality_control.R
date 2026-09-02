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

# --- v2.0.0: seal what does not live in results_summary.csv -------------------
#
# Version 1.0.0 checked only the 26 figures emitted by 02_run_analysis.R. Model
# dispersion, negative-binomial fit, spatial autocorrelation and the subgroup
# contrasts went unsealed -- that is, precisely what the specification change
# moves. They are collected from their source tables.
recoger <- function(archivo, f) {
  ruta <- file.path(PATHS$tables, archivo)
  if (!file.exists(ruta)) { message("QC: ", archivo, " is missing; its indicators will FAIL."); return(NULL) }
  f(fread(ruta))
}
extra <- rbindlist(list(
  recoger("13_quasipoisson_models.csv", function(d) {
    u <- unique(d[, .(model, dispersion_phi)])
    data.table(indicator = c("dispersion_phi_model1", "dispersion_phi_model2"),
               value_actual = c(u[model == "Altitude only", dispersion_phi],
                                u[model == "Altitude plus flash density", dispersion_phi]))
  }),
  recoger("22_poisson_vs_negbin_aic.csv", function(d) {
    data.table(indicator = c("negbin_theta_model1", "negbin_theta_model2"),
               value_actual = c(d[model %like% "Model 1" & family %like% "Negative", theta],
                                d[model %like% "Model 2" & family %like% "Negative", theta]))
  }),
  recoger("16_moran_i.csv", function(d) {
    g <- function(v, w) d[variable == v & weights == w, I]
    data.table(
      indicator = c("moran_I_deaths_queen", "moran_I_deaths_knn8",
                    "moran_I_residuals_m2_queen", "moran_I_residuals_m2_knn8",
                    "moran_I_residuals_m1_queen"),
      value_actual = c(g("Outcome: deaths (count)", "Queen"),
                       g("Outcome: deaths (count)", "KNN-8"),
                       g("Pearson residuals m2 (b) LOD", "Queen"),
                       g("Pearson residuals m2 (b) LOD", "KNN-8"),
                       g("Pearson residuals m1", "Queen")))
  }),
  recoger("28_subgroup_contrasts.csv", function(d) {
    a <- d[comparison %like% "Amazon"]; p <- d[comparison %like% "Pacific"]
    data.table(
      indicator = c("RR_high_vs_amazon_lowland", "density_ratio_high_vs_amazon",
                    "mortality_flash_ratio_high_vs_amazon", "RR_high_vs_pacific_coast"),
      value_actual = c(a$RR, a$density_ratio, a$MFR_ratio, p$RR))
  }),
  # The twelve terminal assertions enter by their stable identifier.
  recoger("27_terminal_checks.csv", function(d) d[, .(indicator, value_actual = value)])
), use.names = TRUE, fill = TRUE)
if (!is.null(extra) && nrow(extra)) actual <- rbind(actual, extra, use.names = TRUE, fill = TRUE)
expected <- fread(expected_file)
qc <- merge(expected, actual, by = "indicator", all.x = TRUE)
qc[, absolute_difference := abs(value_actual - value_expected)]
qc[, status := fifelse(is.na(value_actual), "FAIL", fifelse(absolute_difference <= tolerance, "PASS", "FAIL"))]

mandatory_figures <- c("Figure_1_altitude_mortality.png", "Figure_2_seasonality.png",
                       "Figure_3_age_sex.png", "Figure_4_density_mortality.png",
                       # v2.0.0: the submission set, using the MANUSCRIPT
                       # numbering, which does not match the one above.
                       file.path("manuscript", paste0("Fig", 1:4, ".tif")),
                       file.path("manuscript", paste0("Fig", 1:4, ".eps")))
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
# --- v2.0.0: no published table without a script that produces it -------------
#
# NINE tables in output/tables/ were found to be written by no script: two were
# manuscript tables and one was an input to two other scripts, so a whole chain was
# broken at its first link. This check detects that condition directly.
#
# Criterion: a table is covered only if some script WRITES it. Mentioning it is not
# enough -- an earlier version that searched for the bare filename produced five
# false positives, because several scripts READ tables they do not produce.
DIR_CODIGO <- c("scripts", "R")
# Superseded tables kept for the record, which no script regenerates on purpose.
# The exemption is explicit so that it is auditable rather than silent.
HISTORICAL_TABLES <- character(0)

archivos_codigo <- unlist(lapply(DIR_CODIGO[dir.exists(DIR_CODIGO)], list.files,
                                 pattern = "\\.(R|r|py)$", recursive = TRUE, full.names = TRUE))
codigo <- paste(unlist(lapply(archivos_codigo, readLines, warn = FALSE)), collapse = "\n")
escribe_tabla <- function(f) {
  # perl = TRUE is required: in the POSIX ERE that grepl uses by default, "[^\n]"
  # excludes the LETTER n rather than the newline, so no table with an n in its name
  # could ever match. (?s) lets the call span several lines; [^"']* allows a path
  # prefix without leaving the quoted string.
  patron <- paste0("(?s)(fwrite|write_csv_utf8|write\\.csv|to_csv)\\s*\\(.{0,400}?[\"'][^\"']*",
                   gsub("\\.", "\\\\.", f), "[\"']")
  grepl(patron, codigo, perl = TRUE)
}
tablas_pub <- basename(list.files(PATHS$tables, pattern = "\\.csv$"))
cubierta <- vapply(tablas_pub, escribe_tabla, logical(1))
huerfanas <- setdiff(tablas_pub[!cubierta], HISTORICAL_TABLES)
fantasmas <- setdiff(HISTORICAL_TABLES, tablas_pub)
if (length(fantasmas))
  warning("HISTORICAL_TABLES lists tables that no longer exist: ",
          paste(fantasmas, collapse = ", "), call. = FALSE)
orphan_qc <- data.table(
  indicator = "tables_without_producing_script",
  value_expected = 0, tolerance = 0,
  value_actual = length(huerfanas), absolute_difference = length(huerfanas),
  status = ifelse(length(huerfanas) == 0, "PASS", "FAIL"))
if (length(huerfanas))
  cat("Tables with no producing script:\n", paste0("  - ", huerfanas, collapse = "\n"), "\n")
cat(sprintf("Table coverage: %d of %d written by some script (%d exempt as historical).\n",
            sum(cubierta), length(tablas_pub), length(HISTORICAL_TABLES)))

qc_all <- rbind(qc, figure_qc, map_status, orphan_qc, fill = TRUE)
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
