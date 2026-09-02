# =============================================================================
# 06_spatial_diagnostics.R  -- Spatial diagnostics (v2.0.0)
#
# Brings together in one script, on repository paths, what previously lived in
# three loose files outside the deposit:
#
#   1. District panel with residuals and SMR   (was F6_00_preparar_datos_espaciales.R)
#   2. Moran's I with Queen and KNN-8 weights  (was F6_espacial_R.R)
#   3. Conley spatially robust standard errors (was F6_conley.R)
#
# Step 1 was persisted nowhere (REP-015) and was an INPUT to the other two: the
# chain was broken at its first link.
#
# Changes made when porting:
#   - Geometry is read from PATHS$districts_gpkg, not from an absolute path to a
#     shapefile on a disk that does not exist outside the original machine.
#   - The density floor comes from LOD_FLASH_DENSITY, not a repeated literal.
#   - The comparison against the reference Python run is OPTIONAL: if the file is
#     absent the script reports it and continues instead of aborting.
# =============================================================================

options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages(c("data.table", "sf", "spdep", "sandwich"))
suppressPackageStartupMessages({
  library(data.table); library(sf); library(spdep); library(sandwich)
})

A1 <- ANALYSIS$start_year; A2 <- ANALYSIS$end_year; LN2 <- log(2)
MORAN_NSIM <- 9999L
MORAN_SEED <- 20260825L

dir.create(PATHS$logs, recursive = TRUE, showWarnings = FALSE)
log_lines <- c()
say <- function(...) { s <- paste0(...); cat(s, "\n"); log_lines <<- c(log_lines, s) }

# =============================================================================
# 1. District panel: residuals, SMR and coordinates
# =============================================================================
alt <- fread(PATHS$altitude,   colClasses = list(character = "UBIGEO"))
pob <- fread(PATHS$population, colClasses = list(character = "UBIGEO"))
den <- fread(PATHS$density,    colClasses = list(character = "UBIGEO"))
geo <- as.data.table(readRDS(PATHS$cohort_geographic))
if (!"analysis_year" %in% names(geo)) geo[, analysis_year := year_of(analysis_date)]
geo <- geo[analysis_year %between% c(A1, A2)]

pyd <- pob[anio %between% c(A1, A2), .(person_years = sum(poblacion, na.rm = TRUE)), by = UBIGEO]
nd  <- geo[, .(deaths = .N), by = .(UBIGEO = analysis_ubigeo)]
M <- merge(alt[, .(UBIGEO, altitud, lon, lat)], pyd, by = "UBIGEO", all.x = TRUE)
M <- merge(M, nd, by = "UBIGEO", all.x = TRUE); M[is.na(deaths), deaths := 0L]
M <- merge(M, den[, .(UBIGEO, densidad, area_km2)], by = "UBIGEO", all.x = TRUE)

# n_celdas comes from the pixel-polygon diagnostic (F5). It is descriptive and
# enters no model. If unavailable, processing continues with NA.
f5_file <- file.path(PATHS$public_derived, "pixel_polygon_diagnostics.csv")
if (file.exists(f5_file)) {
  f5 <- fread(f5_file, colClasses = list(character = "UBIGEO"))
  M <- merge(M, f5[, .(UBIGEO, n_cells = n_celdas)], by = "UBIGEO", all.x = TRUE)
} else {
  M[, n_cells := NA_integer_]
  say("NOTICE: no pixel-polygon diagnostic; the n_cells column is left empty (descriptive).")
}

M <- M[!is.na(person_years) & person_years > 0 & !is.na(altitud) & !is.na(densidad) & altitud > 0]
M[, `:=`(lalt = log(altitud), off = log(person_years/1e6))]
M[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
M[, ldens_a := log(pmax(densidad, 0.01))]                 # former v1.0.0 specification
M[, ldens_b := log(pmax(densidad, LOD_FLASH_DENSITY))]    # main v2.0.0 specification

m1  <- glm(deaths ~ lalt + offset(off),            family = quasipoisson(), data = M)
m2a <- glm(deaths ~ lalt + ldens_a + offset(off),  family = quasipoisson(), data = M)
m2b <- glm(deaths ~ lalt + ldens_b + offset(off),  family = quasipoisson(), data = M)

M[, `:=`(crude_rate  = 1e6*deaths/person_years,
         res_m1  = residuals(m1,  type = "pearson"),
         res_m2a = residuals(m2a, type = "pearson"),
         res_m2b = residuals(m2b, type = "pearson"),
         dev_m1  = residuals(m1,  type = "deviance"),
         dev_m2b = residuals(m2b, type = "deviance"),
         expected_m1 = fitted(m1), expected_m2b = fitted(m2b))]
M[, SMR_m1 := fifelse(expected_m1 > 0, deaths/expected_m1, NA_real_)]

PANEL <- M[, .(UBIGEO, lon, lat, altitud, densidad, area_km2, person_years, deaths,
               estrato, n_cells, crude_rate, res_m1, res_m2a, res_m2b,
               dev_m1, dev_m2b, expected_m1, SMR_m1)]
write_csv_utf8(PANEL, file.path(PATHS$tables, "15_district_spatial_panel.csv"))
say(sprintf("Spatial panel: %d districts.", nrow(PANEL)))

# =============================================================================
# 2. Moran's I -- Queen and KNN-8 weights
# =============================================================================
map <- st_read(PATHS$districts_gpkg, quiet = TRUE)
ubi_col <- safe_col(map, c("UBIGEO", "ubigeo", "IDDIST", "iddist", "CODIGO_DIS"), TRUE)
map$UBIGEO <- substr(as.character(map[[ubi_col]]), 1, 6)
g <- merge(map[, c("UBIGEO", attr(map, "sf_column"))], PANEL, by = "UBIGEO")
g <- g[order(match(g$UBIGEO, PANEL$UBIGEO)), ]

say(sprintf("sf %s | spdep %s | GDAL %s | GEOS %s | PROJ %s",
            packageVersion("sf"), packageVersion("spdep"),
            sf_extSoftVersion()[["GDAL"]], sf_extSoftVersion()[["GEOS"]],
            sf_extSoftVersion()[["PROJ"]]))
say(sprintf("Districts with geometry and data: %d", nrow(g)))

sf_use_s2(FALSE)
nb_q <- poly2nb(g, queen = TRUE)
islas <- which(card(nb_q) == 0)
say(sprintf("QUEEN weights: islands = %d", length(islas)))
if (length(islas)) {
  cent0 <- st_coordinates(st_point_on_surface(st_geometry(g)))
  k1 <- knn2nb(knearneigh(cent0, k = 1))
  for (i in islas) {
    j <- k1[[i]]
    nb_q[[i]] <- as.integer(j)
    nb_q[[j]] <- sort(unique(c(nb_q[[j]][nb_q[[j]] > 0], i)))
  }
  say("  islands resolved by attaching the nearest neighbour (KNN-1)")
}
W_q <- nb2listw(nb_q, style = "W", zero.policy = TRUE)

# The KNN graph is built on st_centroid, NOT on st_point_on_surface. The two
# points are ~2.4 km apart on average and reorder the neighbourhood: under
# point_on_surface, I falls by between 0.8 % and 3.9 %. st_centroid is adopted
# because it is the convention in spatial econometrics and reproduces the
# reference Python run. That the choice moves the statistic by nearly 4 % is
# itself the argument for the MAIN specification being Queen, which depends on no
# representative point.
cent <- st_coordinates(suppressWarnings(st_centroid(st_geometry(g))))
W_k <- nb2listw(knn2nb(knearneigh(cent, k = 8)), style = "W")
say(sprintf("  mean neighbours: Queen %.3f | KNN-8 %d", mean(card(nb_q)), 8L))

vars <- list(
  c("deaths",     "Outcome: deaths (count)"),
  c("crude_rate", "Outcome: crude rate"),
  c("SMR_m1",     "Outcome: SMR (obs/exp m1)"),
  c("res_m1",     "Pearson residuals m1"),
  c("res_m2a",    "Pearson residuals m2 (a) floor 0.01"),
  c("res_m2b",    "Pearson residuals m2 (b) LOD"),
  c("dev_m1",     "Deviance residuals m1"),
  c("dev_m2b",    "Deviance residuals m2 (b)"))

set.seed(MORAN_SEED)
res <- list()
for (wl in c("Queen", "KNN-8")) {
  W <- if (wl == "Queen") W_q else W_k
  say(sprintf("=== %s WEIGHTS ===", wl))
  for (v in vars) {
    y <- as.numeric(st_drop_geometry(g)[[v[1]]])
    mc <- moran.mc(y, W, nsim = MORAN_NSIM, zero.policy = TRUE)
    say(sprintf("  %-36s I=%8.5f  p=%.5f", v[2], as.numeric(mc$statistic), mc$p.value))
    res[[length(res)+1]] <- data.table(variable = v[2], weights = wl,
                                       I = as.numeric(mc$statistic), p_sim = mc$p.value)
  }
  for (cv in list(c("log(altitud)", "Covariate: log(altitude)"),
                  c("densidad",     "Covariate: flash density"))) {
    y <- if (cv[1] == "log(altitud)") log(as.numeric(st_drop_geometry(g)$altitud))
         else as.numeric(st_drop_geometry(g)$densidad)
    mc <- moran.mc(y, W, nsim = MORAN_NSIM, zero.policy = TRUE)
    say(sprintf("  %-36s I=%8.5f  p=%.5f", cv[2], as.numeric(mc$statistic), mc$p.value))
    res[[length(res)+1]] <- data.table(variable = cv[2], weights = wl,
                                       I = as.numeric(mc$statistic), p_sim = mc$p.value)
  }
}
MORAN <- rbindlist(res)
write_csv_utf8(MORAN, file.path(PATHS$tables, "16_moran_i.csv"))

# Optional comparison against the reference Python run (esda/libpysal).
py_file <- file.path(PATHS$public_derived, "moran_python_reference.csv")
if (file.exists(py_file)) {
  PY <- fread(py_file)
  CMP <- merge(MORAN, PY[, .(variable, weights, I_py = I, p_py = p_sim)],
               by = c("variable", "weights"))
  if (nrow(CMP)) {
    CMP[, `:=`(diff_I = I - I_py, diff_rel_pct = 100*(I - I_py)/I_py)]
    say(sprintf("R vs Python: maximum absolute difference in I = %.3e", max(abs(CMP$diff_I))))
    write_csv_utf8(CMP, file.path(PATHS$tables, "16b_moran_r_vs_python.csv"))
  }
} else {
  say("No reference Python run available; the cross-check is skipped.")
}

# =============================================================================
# 3. Spatially robust standard errors: Conley and administrative clustering
# =============================================================================
D <- copy(PANEL)
D[, `:=`(lalt = log(altitud), off = log(person_years/1e6),
         ldens_b = log(pmax(densidad, LOD_FLASH_DENSITY)),
         dep = substr(UBIGEO, 1, 2), prov = substr(UBIGEO, 1, 4))]

haversine <- function(lon, lat) {
  R <- 6371; la <- lat*pi/180; lo <- lon*pi/180
  dla <- outer(la, la, "-"); dlo <- outer(lo, lo, "-")
  a <- sin(dla/2)^2 + outer(cos(la), cos(la), "*")*sin(dlo/2)^2
  2*R*asin(pmin(1, sqrt(a)))
}
D2 <- haversine(D$lon, D$lat)
say(sprintf("Distance matrix %d x %d; median between districts %.0f km",
            nrow(D2), ncol(D2), median(D2[upper.tri(D2)])))

# Conley: V = bread %*% meat %*% bread, with a spatial kernel over distance.
conley_vcov <- function(m, dist, cutoff, kernel = c("bartlett", "uniform")) {
  kernel <- match.arg(kernel)
  X <- model.matrix(m); mu <- fitted(m); u <- residuals(m, type = "response")
  K <- if (kernel == "bartlett") pmax(0, 1 - dist/cutoff) else (dist <= cutoff)*1
  bread <- solve(crossprod(X, X*mu))
  meat <- t(X) %*% (outer(u, u) * K) %*% X
  bread %*% meat %*% bread
}
fila <- function(m, V, etiqueta, termino, n) {
  b <- coef(m)[termino]; se <- sqrt(diag(V))[termino]
  z <- b/se; p <- 2*pnorm(-abs(z))
  data.table(specification = etiqueta,
             parameter = ifelse(termino == "lalt", "Altitude", "Flash density"),
             n = n, beta = b, SE = se, IRR = exp(b*LN2),
             CI95_lower = exp((b - 1.96*se)*LN2), CI95_upper = exp((b + 1.96*se)*LN2),
             p_value = p)
}
q1  <- glm(deaths ~ lalt + offset(off),           family = quasipoisson(), data = D)
q2b <- glm(deaths ~ lalt + ldens_b + offset(off), family = quasipoisson(), data = D)

bloque <- function(m, termino) {
  r <- list(
    fila(m, vcov(m),                      "quasi-Poisson (base)",            termino, nrow(D)),
    fila(m, vcovCL(m, cluster = D$dep),   "clustered by department (25)",    termino, nrow(D)),
    fila(m, vcovCL(m, cluster = D$prov),  "clustered by province (196)",     termino, nrow(D)))
  for (co in c(50, 100, 200, 300))
    r[[length(r)+1]] <- fila(m, conley_vcov(m, D2, co), sprintf("Conley Bartlett %d km", co), termino, nrow(D))
  rbindlist(r)
}
R1  <- bloque(q1,  "lalt");    R1[,  model := "Model 1: altitude only"]
R2a <- bloque(q2b, "lalt");    R2a[, model := "Model 2: altitude"]
R2b <- bloque(q2b, "ldens_b"); R2b[, model := "Model 2: flash density"]
CONLEY <- rbind(R1, R2a, R2b)
write_csv_utf8(CONLEY, file.path(PATHS$tables, "17_conley_robust_se.csv"))

for (nm in unique(CONLEY$model)) {
  say(sprintf("--- %s ---", nm))
  b <- CONLEY[model == nm]
  for (i in seq_len(nrow(b)))
    with(b[i], say(sprintf("  %-34s beta=%8.5f SE=%8.5f IRR=%7.3f  CI95 %6.3f - %-8.3f p=%.3g",
                           specification, beta, SE, IRR, CI95_lower, CI95_upper, p_value)))
}
say(sprintf("Altitude, Model 1: lower 95%% CI from %.3f to %.3f; all exclude 1? %s",
            min(R1$CI95_lower), max(R1$CI95_lower), all(R1$CI95_lower > 1)))
say(sprintf("Altitude, Model 2: lower 95%% CI from %.3f to %.3f; all exclude 1? %s",
            min(R2a$CI95_lower), max(R2a$CI95_lower), all(R2a$CI95_lower > 1)))

writeLines(log_lines, file.path(PATHS$logs, "06_spatial_diagnostics.log"), useBytes = TRUE)
cat("Spatial diagnostics complete.\n")
