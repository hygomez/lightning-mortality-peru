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

# --- Cambio 28 (v2.0.0): sellar tambien lo que no vive en results_summary.csv ---
#
# La v1.0.0 solo controlaba las 26 cifras que emite 02_run_analysis.R. Quedaban sin
# sellar la dispersion de los modelos, el ajuste de la binomial negativa, la
# autocorrelacion espacial y los contrastes por subgrupo -- es decir, justo lo que
# el cambio de especificacion mueve. Se recogen de sus tablas de origen.
recoger <- function(archivo, f) {
  ruta <- file.path(PATHS$tables, archivo)
  if (!file.exists(ruta)) { message("QC: falta ", archivo, "; sus indicadores quedaran en FAIL."); return(NULL) }
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
               value_actual = c(d[modelo %like% "Modelo 1" & familia %like% "negativa", theta],
                                d[modelo %like% "Modelo 2" & familia %like% "negativa", theta]))
  }),
  recoger("16_moran_i.csv", function(d) {
    g <- function(v, w) d[variable == v & pesos == w, I]
    data.table(
      indicator = c("moran_I_deaths_queen", "moran_I_deaths_knn8",
                    "moran_I_residuals_m2_queen", "moran_I_residuals_m2_knn8",
                    "moran_I_residuals_m1_queen"),
      value_actual = c(g("Desenlace: muertes (conteo)", "Queen"),
                       g("Desenlace: muertes (conteo)", "KNN-8"),
                       g("Residuos Pearson m2 (b) LOD", "Queen"),
                       g("Residuos Pearson m2 (b) LOD", "KNN-8"),
                       g("Residuos Pearson m1", "Queen")))
  }),
  recoger("28_subgroup_contrasts.csv", function(d) {
    a <- d[comparacion %like% "Amazon"]; p <- d[comparacion %like% "Pacific"]
    data.table(
      indicator = c("RR_high_vs_amazon_lowland", "density_ratio_high_vs_amazon",
                    "mortality_flash_ratio_high_vs_amazon", "RR_high_vs_pacific_coast"),
      value_actual = c(a$RR, a$razon_densidad, a$razon_MFR, p$RR))
  }),
  # Las doce aserciones terminales entran por su identificador estable.
  recoger("27_terminal_checks.csv", function(d) d[, .(indicator, value_actual = value)])
), use.names = TRUE, fill = TRUE)
if (!is.null(extra) && nrow(extra)) actual <- rbind(actual, extra, use.names = TRUE, fill = TRUE)
expected <- fread(expected_file)
qc <- merge(expected, actual, by = "indicator", all.x = TRUE)
qc[, absolute_difference := abs(value_actual - value_expected)]
qc[, status := fifelse(is.na(value_actual), "FAIL", fifelse(absolute_difference <= tolerance, "PASS", "FAIL"))]

mandatory_figures <- c("Figure_1_altitude_mortality.png", "Figure_2_seasonality.png",
                       "Figure_3_age_sex.png", "Figure_4_density_mortality.png",
                       # Cambio 29 (v2.0.0): el juego de envio, con la numeracion
                       # del MANUSCRITO, que no coincide con la de arriba.
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
# --- Cambio 27 (v2.0.0): ninguna tabla publicada sin script que la produzca ----
#
# En agosto se descubrio que NUEVE tablas de output/tables/ no las escribia ningun
# script: dos eran tablas del manuscrito y una era insumo de otros dos scripts, de
# modo que una cadena entera estaba rota en su primer eslabon. Esta comprobacion
# lo habria detectado en el acto.
#
# Criterio: una tabla esta cubierta solo si algun script la ESCRIBE. Mencionarla
# no basta -- una primera version que buscaba la mera mencion del nombre dio cinco
# falsos positivos, porque varios scripts LEEN tablas que no producen.
DIR_CODIGO <- c("scripts", "R")
# Tablas superadas que se conservan como historico y que ningun script regenera a
# proposito. La exencion es explicita para que sea auditable, no un silencio.
HISTORICAL_TABLES <- character(0)

archivos_codigo <- unlist(lapply(DIR_CODIGO[dir.exists(DIR_CODIGO)], list.files,
                                 pattern = "\\.(R|r|py)$", recursive = TRUE, full.names = TRUE))
codigo <- paste(unlist(lapply(archivos_codigo, readLines, warn = FALSE)), collapse = "\n")
escribe_tabla <- function(f) {
  # perl = TRUE es imprescindible: en la ERE de POSIX que usa grepl por defecto,
  # "[^\n]" excluye la LETRA n, no el salto de linea, y ninguna tabla con una n en
  # el nombre llegaba a coincidir jamas. (?s) permite que la llamada se reparta en
  # varias lineas; [^"']* admite un prefijo de ruta sin salirse de la cadena.
  patron <- paste0("(?s)(fwrite|write_csv_utf8|write\\.csv|to_csv)\\s*\\(.{0,400}?[\"'][^\"']*",
                   gsub("\\.", "\\\\.", f), "[\"']")
  grepl(patron, codigo, perl = TRUE)
}
tablas_pub <- basename(list.files(PATHS$tables, pattern = "\\.csv$"))
cubierta <- vapply(tablas_pub, escribe_tabla, logical(1))
huerfanas <- setdiff(tablas_pub[!cubierta], HISTORICAL_TABLES)
fantasmas <- setdiff(HISTORICAL_TABLES, tablas_pub)
if (length(fantasmas))
  warning("HISTORICAL_TABLES menciona tablas que ya no existen: ",
          paste(fantasmas, collapse = ", "), call. = FALSE)
orphan_qc <- data.table(
  indicator = "tables_without_producing_script",
  value_expected = 0, tolerance = 0,
  value_actual = length(huerfanas), absolute_difference = length(huerfanas),
  status = ifelse(length(huerfanas) == 0, "PASS", "FAIL"))
if (length(huerfanas))
  cat("Tablas sin script que las produzca:\n", paste0("  - ", huerfanas, collapse = "\n"), "\n")
cat(sprintf("Cobertura de tablas: %d de %d escritas por algun script (%d exentas por historicas).\n",
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
