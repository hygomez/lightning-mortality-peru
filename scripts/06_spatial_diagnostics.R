# =============================================================================
# 06_spatial_diagnostics.R  -- Diagnostico espacial (v2.0.0)
#
# Reune en un solo script, y sobre las rutas del repositorio, lo que en el
# trabajo de agosto vivia en tres archivos sueltos fuera del deposito:
#
#   1. Panel distrital con residuos y SMR   (antes F6_00_preparar_datos_espaciales.R)
#   2. Moran's I con pesos Queen y KNN-8    (antes F6_espacial_R.R)
#   3. SE espacialmente robustos de Conley  (antes F6_conley.R)
#
# El paso 1 no estaba persistido en ninguna parte (REP-015) y era INSUMO de los
# otros dos: la cadena estaba rota en su primer eslabon.
#
# Cambios al portar:
#   - La geometria se lee de PATHS$districts_gpkg, no de una ruta absoluta a un
#     shapefile en un disco que no existe fuera de la maquina original.
#   - El piso de densidad sale de LOD_FLASH_DENSITY, no de un literal repetido.
#   - La comparacion contra la corrida Python de referencia es OPCIONAL: si el
#     archivo no esta, el script informa y sigue, en vez de abortar.
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
# 1. Panel distrital: residuos, SMR y coordenadas
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

# n_celdas viene del diagnostico pixel-poligono (F5). Es descriptivo: no entra en
# ningun modelo. Si no esta disponible, se sigue adelante con NA.
f5_file <- file.path(PATHS$public_derived, "pixel_polygon_diagnostics.csv")
if (file.exists(f5_file)) {
  f5 <- fread(f5_file, colClasses = list(character = "UBIGEO"))
  M <- merge(M, f5[, .(UBIGEO, n_celdas)], by = "UBIGEO", all.x = TRUE)
} else {
  M[, n_celdas := NA_integer_]
  say("AVISO: sin diagnostico pixel-poligono; la columna n_celdas queda vacia (descriptiva).")
}

M <- M[!is.na(person_years) & person_years > 0 & !is.na(altitud) & !is.na(densidad) & altitud > 0]
M[, `:=`(lalt = log(altitud), off = log(person_years/1e6))]
M[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
M[, ldens_a := log(pmax(densidad, 0.01))]                 # especificacion antigua v1.0.0
M[, ldens_b := log(pmax(densidad, LOD_FLASH_DENSITY))]    # especificacion principal v2.0.0

m1  <- glm(deaths ~ lalt + offset(off),            family = quasipoisson(), data = M)
m2a <- glm(deaths ~ lalt + ldens_a + offset(off),  family = quasipoisson(), data = M)
m2b <- glm(deaths ~ lalt + ldens_b + offset(off),  family = quasipoisson(), data = M)

M[, `:=`(tasa_cruda  = 1e6*deaths/person_years,
         res_m1  = residuals(m1,  type = "pearson"),
         res_m2a = residuals(m2a, type = "pearson"),
         res_m2b = residuals(m2b, type = "pearson"),
         dev_m1  = residuals(m1,  type = "deviance"),
         dev_m2b = residuals(m2b, type = "deviance"),
         esperado_m1 = fitted(m1), esperado_m2b = fitted(m2b))]
M[, SMR_m1 := fifelse(esperado_m1 > 0, deaths/esperado_m1, NA_real_)]

PANEL <- M[, .(UBIGEO, lon, lat, altitud, densidad, area_km2, person_years, deaths,
               estrato, n_celdas, tasa_cruda, res_m1, res_m2a, res_m2b,
               dev_m1, dev_m2b, esperado_m1, SMR_m1)]
write_csv_utf8(PANEL, file.path(PATHS$tables, "15_district_spatial_panel.csv"))
say(sprintf("Panel espacial: %d distritos.", nrow(PANEL)))

# =============================================================================
# 2. Moran's I -- pesos Queen y KNN-8
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
say(sprintf("Distritos con geometria y datos: %d", nrow(g)))

sf_use_s2(FALSE)
nb_q <- poly2nb(g, queen = TRUE)
islas <- which(card(nb_q) == 0)
say(sprintf("Pesos QUEEN: islas = %d", length(islas)))
if (length(islas)) {
  cent0 <- st_coordinates(st_point_on_surface(st_geometry(g)))
  k1 <- knn2nb(knearneigh(cent0, k = 1))
  for (i in islas) {
    j <- k1[[i]]
    nb_q[[i]] <- as.integer(j)
    nb_q[[j]] <- sort(unique(c(nb_q[[j]][nb_q[[j]] > 0], i)))
  }
  say("  islas resueltas anexando el vecino mas proximo (KNN-1)")
}
W_q <- nb2listw(nb_q, style = "W", zero.policy = TRUE)

# El grafo KNN se construye sobre st_centroid, NO sobre st_point_on_surface.
# Los dos puntos distan ~2,4 km de media y reordenan el vecindario: con
# point_on_surface el I baja entre 0,8 % y 3,9 %. Se adopta st_centroid porque es
# la convencion en econometria espacial y reproduce la corrida Python de
# referencia. Que la eleccion mueva el estadistico casi un 4 % es en si mismo el
# argumento para que la especificacion PRINCIPAL sea Queen, que no depende de
# ningun punto representativo.
cent <- st_coordinates(suppressWarnings(st_centroid(st_geometry(g))))
W_k <- nb2listw(knn2nb(knearneigh(cent, k = 8)), style = "W")
say(sprintf("  vecinos medios: Queen %.3f | KNN-8 %d", mean(card(nb_q)), 8L))

vars <- list(
  c("deaths",     "Desenlace: muertes (conteo)"),
  c("tasa_cruda", "Desenlace: tasa cruda"),
  c("SMR_m1",     "Desenlace: SMR (obs/esp m1)"),
  c("res_m1",     "Residuos Pearson m1"),
  c("res_m2a",    "Residuos Pearson m2 (a) piso 0.01"),
  c("res_m2b",    "Residuos Pearson m2 (b) LOD"),
  c("dev_m1",     "Residuos deviance m1"),
  c("dev_m2b",    "Residuos deviance m2 (b)"))

set.seed(MORAN_SEED)
res <- list()
for (wl in c("Queen", "KNN-8")) {
  W <- if (wl == "Queen") W_q else W_k
  say(sprintf("=== PESOS %s ===", wl))
  for (v in vars) {
    y <- as.numeric(st_drop_geometry(g)[[v[1]]])
    mc <- moran.mc(y, W, nsim = MORAN_NSIM, zero.policy = TRUE)
    say(sprintf("  %-36s I=%8.5f  p=%.5f", v[2], as.numeric(mc$statistic), mc$p.value))
    res[[length(res)+1]] <- data.table(variable = v[2], pesos = wl,
                                       I = as.numeric(mc$statistic), p_sim = mc$p.value)
  }
  for (cv in list(c("log(altitud)", "Covariable: log(altitud)"),
                  c("densidad",     "Covariable: densidad"))) {
    y <- if (cv[1] == "log(altitud)") log(as.numeric(st_drop_geometry(g)$altitud))
         else as.numeric(st_drop_geometry(g)$densidad)
    mc <- moran.mc(y, W, nsim = MORAN_NSIM, zero.policy = TRUE)
    say(sprintf("  %-36s I=%8.5f  p=%.5f", cv[2], as.numeric(mc$statistic), mc$p.value))
    res[[length(res)+1]] <- data.table(variable = cv[2], pesos = wl,
                                       I = as.numeric(mc$statistic), p_sim = mc$p.value)
  }
}
MORAN <- rbindlist(res)
write_csv_utf8(MORAN, file.path(PATHS$tables, "16_moran_i.csv"))

# Comparacion opcional contra la corrida Python de referencia (esda/libpysal).
py_file <- file.path(PATHS$public_derived, "moran_python_reference.csv")
if (file.exists(py_file)) {
  PY <- fread(py_file)
  CMP <- merge(MORAN, PY[, .(variable, pesos, I_py = I, p_py = p_sim)],
               by = c("variable", "pesos"))
  if (nrow(CMP)) {
    CMP[, `:=`(dif_I = I - I_py, dif_rel_pct = 100*(I - I_py)/I_py)]
    say(sprintf("Comparacion R vs Python: dif. absoluta maxima en I = %.3e", max(abs(CMP$dif_I))))
    write_csv_utf8(CMP, file.path(PATHS$tables, "16b_moran_r_vs_python.csv"))
  }
} else {
  say("Sin corrida Python de referencia; se omite la comparacion cruzada.")
}

# =============================================================================
# 3. SE espacialmente robustos: Conley y agrupamientos administrativos
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
say(sprintf("Matriz de distancias %d x %d; mediana entre distritos %.0f km",
            nrow(D2), ncol(D2), median(D2[upper.tri(D2)])))

# Conley: V = bread %*% meat %*% bread, con nucleo espacial sobre la distancia.
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
  data.table(especificacion = etiqueta,
             parametro = ifelse(termino == "lalt", "Altitud", "Densidad"),
             n = n, beta = b, SE = se, IRR = exp(b*LN2),
             IC95_inf = exp((b - 1.96*se)*LN2), IC95_sup = exp((b + 1.96*se)*LN2),
             p_value = p)
}
q1  <- glm(deaths ~ lalt + offset(off),           family = quasipoisson(), data = D)
q2b <- glm(deaths ~ lalt + ldens_b + offset(off), family = quasipoisson(), data = D)

bloque <- function(m, termino) {
  r <- list(
    fila(m, vcov(m),                      "quasi-Poisson (base)",           termino, nrow(D)),
    fila(m, vcovCL(m, cluster = D$dep),   "agrupado por departamento (25)", termino, nrow(D)),
    fila(m, vcovCL(m, cluster = D$prov),  "agrupado por provincia (196)",   termino, nrow(D)))
  for (co in c(50, 100, 200, 300))
    r[[length(r)+1]] <- fila(m, conley_vcov(m, D2, co), sprintf("Conley Bartlett %d km", co), termino, nrow(D))
  rbindlist(r)
}
R1  <- bloque(q1,  "lalt");    R1[,  modelo := "Modelo 1: altitud sola"]
R2a <- bloque(q2b, "lalt");    R2a[, modelo := "Modelo 2: altitud"]
R2b <- bloque(q2b, "ldens_b"); R2b[, modelo := "Modelo 2: densidad"]
CONLEY <- rbind(R1, R2a, R2b)
write_csv_utf8(CONLEY, file.path(PATHS$tables, "17_conley_robust_se.csv"))

for (nm in unique(CONLEY$modelo)) {
  say(sprintf("--- %s ---", nm))
  b <- CONLEY[modelo == nm]
  for (i in seq_len(nrow(b)))
    with(b[i], say(sprintf("  %-34s beta=%8.5f SE=%8.5f IRR=%7.3f  IC95 %6.3f - %-8.3f p=%.3g",
                           especificacion, beta, SE, IRR, IC95_inf, IC95_sup, p_value)))
}
say(sprintf("Altitud, Modelo 1: IC95 inferior de %.3f a %.3f; todos excluyen 1? %s",
            min(R1$IC95_inf), max(R1$IC95_inf), all(R1$IC95_inf > 1)))
say(sprintf("Altitud, Modelo 2: IC95 inferior de %.3f a %.3f; todos excluyen 1? %s",
            min(R2a$IC95_inf), max(R2a$IC95_inf), all(R2a$IC95_inf > 1)))

writeLines(log_lines, file.path(PATHS$logs, "06_spatial_diagnostics.log"), useBytes = TRUE)
cat("Diagnostico espacial completo.\n")
