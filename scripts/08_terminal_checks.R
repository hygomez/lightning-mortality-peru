# =============================================================================
# 08_terminal_checks.R  -- Terminal checks (v2.0.0)
#
# Five checks that support claims made in the manuscript and that, up to v1.0.0,
# had been run AT A CONSOLE, leaving neither code nor file:
#
#   C1  Zero deaths in districts without a 2017 denominator     (REP-007)
#   C2  The Amazon is the highest-flash-density region of Peru  (title, 3.3)
#   C3  Impact of the 2017 back-extrapolation (0.05 %)          (methods)
#   C4  Representative point of the KNN graph: centroid vs surface
#   C5  Contrast against the merged Pacific coast (RR 362.06)
#
# None is an input to another: they are terminal. Each declares its expected value
# and the script FAILS if any stops reproducing, so a silent regression in any of
# them halts the pipeline.
# =============================================================================

options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages(c("data.table", "sf"))
suppressPackageStartupMessages({library(data.table); library(sf)})

A1 <- ANALYSIS$start_year; A2 <- ANALYSIS$end_year
TOL <- 1e-3

alt <- fread(PATHS$altitude,   colClasses = list(character = "UBIGEO"))
pob <- fread(PATHS$population, colClasses = list(character = "UBIGEO"))
den <- fread(PATHS$density,    colClasses = list(character = "UBIGEO"))
geo <- as.data.table(readRDS(PATHS$cohort_geographic))
if (!"analysis_year" %in% names(geo)) geo[, analysis_year := year_of(analysis_date)]
geo <- geo[analysis_year %between% c(A1, A2)]

res <- list()
# `indicator` is a stable snake_case identifier: it is the key by which
# 04_quality_control.R seals these twelve assertions in expected_results.csv.
anota <- function(id, indicator, descripcion, magnitud, valor, esperado, tol = TOL) {
  ok <- abs(valor - esperado) <= tol
  res[[length(res) + 1L]] <<- data.table(
    check = id, indicator = indicator, description = descripcion, quantity = magnitud,
    value = valor, expected = esperado, tolerance = tol,
    status = if (ok) "PASS" else "FAIL")
  cat(sprintf("  %-3s %-46s %14.6f  (esperado %.6f)  %s\n",
              id, magnitud, valor, esperado, if (ok) "PASS" else "<-- FAIL"))
  invisible(ok)
}

# --- C1 -----------------------------------------------------------------------
cat("C1  Districts without a 2017 denominator (REP-007)\n")
p17   <- pob[anio == A1 & !is.na(poblacion) & poblacion > 0, unique(UBIGEO)]
sin17 <- setdiff(pob[, unique(UBIGEO)], p17)
anota("C1", "check_districts_without_2017_denominator", "Districts with no reconstructed 2017 population",
      "districts without denominator", length(sin17), 18)
anota("C1", "check_deaths_in_districts_without_denominator", "Deaths from the geographic cohort in those districts",
      "deaths in districts without denominator", geo[analysis_ubigeo %in% sin17, .N], 0)

# --- C2 -----------------------------------------------------------------------
cat("C2  Climatological flash density by macroregion (supports the title)\n")
M <- merge(alt[, .(UBIGEO, altitud)], den[, .(UBIGEO, densidad, area_km2)], by = "UBIGEO")
M <- M[!is.na(altitud) & !is.na(densidad) & altitud > 0]
M[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
M[, dep := substr(UBIGEO, 1, 2)]
M[, macroregion := fifelse(estrato != LOWLAND_LABEL, paste("Stratum", estrato),
              fifelse(dep %in% PACIFIC_DEPARTMENTS, "Pacific coast (<500 m)",
                                                    "Amazon lowland (<500 m)"))]
MR <- M[, .(districts = .N, area_km2 = round(sum(area_km2), 1),
            flashes_per_year = round(sum(densidad*area_km2), 1),
            area_weighted_density = round(sum(densidad*area_km2)/sum(area_km2), 4)),
        by = macroregion][order(-area_weighted_density)]
print(MR)
write_csv_utf8(MR, file.path(PATHS$tables, "26_density_by_macroregion.csv"))
anota("C2", "check_amazon_density_rank", "The Amazon leads area-weighted flash density",
      "rank of the Amazon lowland (1 = highest)",
      which(MR$macroregion == "Amazon lowland (<500 m)"), 1)
anota("C2", "check_amazon_area_weighted_density", "Amazon lowland flash density", "flashes km-2 year-1",
      MR[macroregion == "Amazon lowland (<500 m)", area_weighted_density], 20.648, tol = 0.01)

# --- C3 -----------------------------------------------------------------------
cat("C3  Back-extrapolation of 2017\n")
pa <- merge(pob[anio %between% c(A1, A2)], alt[, .(UBIGEO, altitud)], by = "UBIGEO", all.x = TRUE)
pa[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
py_base <- pa[estrato == ">3500", sum(poblacion, na.rm = TRUE)]
p18 <- pob[anio == 2018L, .(UBIGEO, p2018 = poblacion)]
pa2 <- merge(pa, p18, by = "UBIGEO", all.x = TRUE)
pa2[anio == A1 & !is.na(p2018), poblacion := p2018]
py_alt <- pa2[estrato == ">3500", sum(poblacion, na.rm = TRUE)]
d_high <- geo[estrato == ">3500", .N]
tasa_base <- 1e6*d_high/py_base
tasa_alt  <- 1e6*d_high/py_alt
anota("C3", "check_high_rate_reconstructed_2017", "Rate >3500 m with the reconstructed 2017", "per million person-years",
      tasa_base, 13.0162, tol = 0.01)
anota("C3", "check_high_rate_2017_equals_2018", "Rate >3500 m setting 2017 = 2018", "per million person-years",
      tasa_alt, 13.0099, tol = 0.01)
anota("C3", "check_backextrapolation_impact_pct", "Relative change between the two scenarios", "% change in the rate",
      100*abs(tasa_alt - tasa_base)/tasa_base, 0.05, tol = 0.02)

# --- C4 -----------------------------------------------------------------------
cat("C4  Representative point for the KNN weights\n")
shp <- st_read(PATHS$districts_gpkg, quiet = TRUE)
#
# DECLARED METRIC. The two representative points are computed in the lon/lat
# PLANE, which is what geopandas does with .centroid and therefore what has to be
# replicated. The distance between them is then measured on the ELLIPSOID (s2,
# geodesic distance), which is the physically meaningful quantity in km.
#
# The earlier verification report measured that same distance IN THE lon/lat PLANE
# and published a 2.44 km mean and 1,213 districts above 1 km. Here the values are
# 2.414 km and 1,206. Both are correct under their own definition; they differ by
# 1 % in the mean and by 7 districts out of 1,891.
#
# The geodesic value is sealed because it is the one with real units. What these
# assertions guard is that the representative point still shifts neighbourhoods by
# kilometres -- the argument for the main specification being Queen, invariant to
# that choice -- not the third decimal.
sf_use_s2(FALSE)
ctr <- suppressWarnings(st_centroid(st_geometry(shp)))
pos <- suppressWarnings(st_point_on_surface(st_geometry(shp)))
sf_use_s2(TRUE)
d_km <- as.numeric(st_distance(ctr, pos, by_element = TRUE))/1000
anota("C4", "check_knn_polygons_compared", "Polygons compared", "districts", length(d_km), 1891)
# The expected values are those of THIS script and ITS metric (geodesic). The
# report's figures -- 2.44 km and 1,213 districts, measured in the plane -- are
# cited above but not used as expectations: comparing against another metric's
# number is exactly the confusion this reconciliation removes.
anota("C4", "check_knn_mean_point_distance_km", "Mean centroid vs point-on-surface distance (geodesic)", "km",
      mean(d_km), 2.4144, tol = 0.01)
anota("C4", "check_knn_districts_over_1km", "Districts differing by more than 1 km (geodesic)", "districts",
      sum(d_km > 1), 1206, tol = 3)

# --- C5 -----------------------------------------------------------------------
cat("C5  Contrast >3500 m against the merged Pacific coast\n")
pa[, dep := substr(UBIGEO, 1, 2)]
py_costa <- pa[estrato == LOWLAND_LABEL & dep %in% PACIFIC_DEPARTMENTS, sum(poblacion, na.rm = TRUE)]
geo[, dep := substr(analysis_ubigeo, 1, 2)]
d_costa <- geo[estrato == LOWLAND_LABEL & dep %in% PACIFIC_DEPARTMENTS, .N]
rr <- rate_ratio_ci(d_high, py_base, d_costa, py_costa, ">3500 m vs merged Pacific coast")
print(rr)
anota("C5", "check_pacific_coast_deaths", "Deaths on the Pacific coast (<500 m)", "deaths", d_costa, 4)
anota("C5", "check_RR_high_vs_merged_coast", "Rate ratio >3500 m vs merged coast", "RR", rr$RR, 362.06, tol = 1.5)

# --- output -------------------------------------------------------------------
R <- rbindlist(res)
write_csv_utf8(R, file.path(PATHS$tables, "27_terminal_checks.csv"))
malas <- R[status != "PASS"]
cat(sprintf("\n%d checks; %d PASS; %d FAIL\n", nrow(R), nrow(R) - nrow(malas), nrow(malas)))
if (nrow(malas)) { print(malas); stop("Terminal checks did not reproduce.", call. = FALSE) }
cat("All five terminal checks reproduce.\n")
