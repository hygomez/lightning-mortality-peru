# =============================================================================
# 09_figures_manuscript.R  -- Manuscript figures as submission files
#
# Journals typically require figures as individual files with no caption inside the
# image. The figures in output/figures/ do not meet that: they carry a title and
# subtitle embedded via labs().
#
# NOTE THE NUMBERING. The manuscript numbering does NOT match that of
# output/figures/: the two are crossed.
#
#   Fig1 (manuscript) = Figure_1_altitude_mortality   mortality by altitude
#   Fig2 (manuscript) = Figure_4_density_mortality    three panels
#   Fig3 (manuscript) = Figure_3_age_sex              age and sex
#   Fig4 (manuscript) = Figure_2_seasonality          seasonality
#
# Output: output/figures/manuscript/, TIFF at 1200 dpi with LZW compression (meets
# the strictest common requirement, the one for line drawings) and vector EPS,
# whose resolution is independent of size. Width 174 mm.
#
# Figure 2 is built from the LOD columns, which are the manuscript's main
# specification, not from the raw zeros.
# =============================================================================

options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages("data.table")
suppressPackageStartupMessages(library(data.table))

OUT <- file.path(PATHS$figures, "manuscript")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

MM <- function(mm) mm/25.4
ANCHO_MAX_MM <- 174   # maximum column width in mm
AZUL <- "#1F77B4"; NARANJA <- "#FF7F0E"

render <- function(base, ancho_mm, alto_mm, dibujar) {
  w <- MM(ancho_mm); h <- MM(alto_mm)
  tiff(file.path(OUT, paste0(base, ".tif")), width = w, height = h, units = "in",
       res = 1200, compression = "lzw", type = "cairo", bg = "white")
  dibujar(); dev.off()
  setEPS()
  postscript(file.path(OUT, paste0(base, ".eps")), width = w, height = h,
             paper = "special", horizontal = FALSE, onefile = FALSE)
  dibujar(); dev.off()
  cat(sprintf("  %s.tif / %s.eps  (%.0f x %.0f mm, 1200 dpi)\n", base, base, ancho_mm, alto_mm))
}
base_par <- function(...) par(mar = c(4.2, 4.6, 0.6, 0.8), mgp = c(2.8, 0.7, 0),
                              cex.axis = 0.75, cex.lab = 0.85, tcl = -0.25,
                              las = 1, xaxs = "i", bty = "l", ...)
rejilla <- function() grid(nx = NA, ny = NULL, col = "grey88", lty = 1, lwd = 0.5)

# Short axis labels, independent of the internal stratum label.
ETIQ <- c("<500", "500-1500", "1500-2500", "2500-3500", ">3500")
ordenar <- function(d, col) d[match(ANALYSIS$altitude_labels, d[[col]])]

# --- Figure 1 -----------------------------------------------------------------
T1 <- ordenar(fread(file.path(PATHS$tables, "01_mortality_by_altitude.csv")), "estrato")
stopifnot(nrow(T1) == 5L, !any(is.na(T1$rate_per_million)))
fig1 <- function() {
  base_par()
  ymax <- max(T1$CI_upper)*1.08
  b <- barplot(T1$rate_per_million, names.arg = ETIQ, ylim = c(0, ymax), col = AZUL,
               border = "black", space = 0.55, xlab = "Mean district altitude (m)",
               ylab = "Deaths per million person-years", axes = FALSE)
  rejilla()
  barplot(T1$rate_per_million, col = AZUL, border = "black", space = 0.55,
          axes = FALSE, add = TRUE, names.arg = NA)
  axis(2, lwd = 0.7, lwd.ticks = 0.7)
  arrows(b, T1$CI_lower, b, T1$CI_upper, angle = 90, code = 3, length = 0.035, lwd = 0.9)
  text(b, T1$CI_upper, sprintf("%.2f", T1$rate_per_million), pos = 3, offset = 0.28, cex = 0.72)
}
cat("Figure 1: mortality by altitude\n"); render("Fig1", ANCHO_MAX_MM, 108, fig1)

# --- Figure 2 -----------------------------------------------------------------
T2 <- fread(file.path(PATHS$tables, "20_mfr_auditable_lod.csv"))
T2 <- ordenar(T2[fila %in% ANALYSIS$altitude_labels], "fila")
stopifnot(nrow(T2) == 5L)
T2[, tasa := T1$rate_per_million]
fig2 <- function() {
  par(mfrow = c(1, 3), mar = c(5.0, 4.3, 1.9, 0.6), mgp = c(2.9, 0.65, 0),
      cex.axis = 0.7, cex.lab = 0.78, tcl = -0.22, las = 1, bty = "l")
  paneles <- list(
    list(v = T2$dens_lod, ylab = expression("Flashes km"^-2~"year"^-1), tit = "(a) Climatological flash density"),
    list(v = T2$tasa,     ylab = "Deaths per million person-years",     tit = "(b) Population mortality"),
    list(v = T2$MFR_lod,  ylab = "Deaths per million flashes",          tit = "(c) Mortality-to-flash ratio"))
  for (p in paneles) {
    barplot(p$v, names.arg = NA, ylim = c(0, max(p$v)*1.06), col = AZUL,
            border = "black", space = 0.5, ylab = p$ylab, axes = FALSE)
    rejilla()
    b <- barplot(p$v, names.arg = NA, col = AZUL, border = "black", space = 0.5,
                 axes = FALSE, add = TRUE)
    axis(2, lwd = 0.7, lwd.ticks = 0.7)
    text(b, par("usr")[3] - diff(par("usr")[3:4])*0.035, ETIQ,
         srt = 40, adj = 1, xpd = TRUE, cex = 0.68)
    mtext(p$tit, side = 3, line = 0.45, cex = 0.68)
    mtext("Mean district altitude (m)", side = 1, line = 3.6, cex = 0.62)
  }
}
cat("Figure 2: climatological hazard and mortality (LOD)\n"); render("Fig2", ANCHO_MAX_MM, 74, fig2)

# --- Figure 3 -----------------------------------------------------------------
T3 <- fread(file.path(PATHS$tables, "06_age_by_sex.csv"))
setnames(T3, 1, "age_group")
MX <- rbind(T3$M, T3$`F`)
stopifnot(sum(MX) == EXPECTED$national_cases)
fig3 <- function() {
  base_par()
  b <- barplot(MX, beside = TRUE, ylim = c(0, max(MX)*1.10), col = c(AZUL, NARANJA),
               border = "black", axes = FALSE, xlab = "Age group (years)", ylab = "Deaths")
  rejilla()
  barplot(MX, beside = TRUE, col = c(AZUL, NARANJA), border = "black", axes = FALSE, add = TRUE)
  barplot(MX, beside = TRUE, col = "black", border = NA, axes = FALSE, add = TRUE,
          density = c(18, 0), angle = 45)
  barplot(MX, beside = TRUE, col = "black", border = NA, axes = FALSE, add = TRUE,
          density = c(0, 18), angle = 135)
  axis(2, lwd = 0.7, lwd.ticks = 0.7)
  legend("topright", legend = c("Men", "Women"), fill = c(AZUL, NARANJA),
         bty = "n", cex = 0.78, border = "black")
  legend("topright", legend = c("Men", "Women"), fill = "black", border = NA,
         density = c(30, 30), angle = c(45, 135), bty = "n", cex = 0.78)
  axis(1, at = colMeans(b), labels = T3$age_group, lwd = 0, lwd.ticks = 0, cex.axis = 0.75)
}
cat("Figure 3: age and sex\n"); render("Fig3", ANCHO_MAX_MM, 106, fig3)

# --- Figure 4 -----------------------------------------------------------------
T4 <- fread(file.path(PATHS$tables, "07_monthly_distribution.csv"))
setorder(T4, month)
lluvia <- T4$month %in% c(10, 11, 12, 1, 2, 3)
pct <- 100*sum(T4$N[lluvia])/sum(T4$N)
stopifnot(sum(T4$N) == EXPECTED$national_cases)
fig4 <- function() {
  base_par(mar = c(3.4, 4.6, 0.6, 0.8))
  ymax <- max(T4$N)*1.16
  b <- barplot(T4$N, names.arg = T4$month_name, ylim = c(0, ymax), col = AZUL,
               border = "black", space = 0.45, axes = FALSE, ylab = "Deaths")
  rejilla()
  barplot(T4$N, col = AZUL, border = "black", space = 0.45, axes = FALSE,
          add = TRUE, names.arg = NA)
  barplot(T4$N, col = "black", border = NA, space = 0.45, axes = FALSE, add = TRUE,
          names.arg = NA, density = ifelse(lluvia, 20, 0), angle = 45)
  axis(2, lwd = 0.7, lwd.ticks = 0.7)
  text(b, T4$N, T4$N, pos = 3, offset = 0.25, cex = 0.7)
  text(par("usr")[2]*0.985, ymax*0.965, sprintf("%.1f%% during Oct-Mar", pct), adj = 1, cex = 0.78)
}
cat("Figure 4: seasonality\n"); render("Fig4", ANCHO_MAX_MM, 104, fig4)

cat("Manuscript figures written to ", OUT, "\n", sep = "")
