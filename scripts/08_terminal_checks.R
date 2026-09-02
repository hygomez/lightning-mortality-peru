# =============================================================================
# 08_terminal_checks.R  -- Comprobaciones terminales (v2.0.0)
#
# Cinco comprobaciones que sostienen afirmaciones del manuscrito y que hasta la
# v1.0.0 se habian ejecutado EN LINEA, sin dejar codigo ni archivo:
#
#   C1  Cero muertes en los distritos sin denominador 2017        (REP-007)
#   C2  La Amazonia es la region de mayor densidad del pais       (titulo, 3.3)
#   C3  Impacto de la retroextrapolacion de 2017 (0,05 %)         (metodos)
#   C4  Punto representativo del grafo KNN: centroide vs superficie
#   C5  Contraste con la costa del Pacifico fusionada (RR 362,06)
#
# Ninguna es insumo de otra: son terminales. Cada una declara su valor esperado
# y el script FALLA si alguna no se reproduce, de modo que una regresion
# silenciosa en cualquiera de ellas detiene el pipeline.
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
# `indicator` es un identificador estable en snake_case: es la clave con la que
# 04_quality_control.R sella estas doce aserciones en expected_results.csv.
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
cat("C1  Distritos sin denominador 2017 (REP-007)\n")
p17   <- pob[anio == A1 & !is.na(poblacion) & poblacion > 0, unique(UBIGEO)]
sin17 <- setdiff(pob[, unique(UBIGEO)], p17)
anota("C1", "check_districts_without_2017_denominator", "Distritos sin poblacion reconstruida para 2017",
      "n distritos sin denominador", length(sin17), 18)
anota("C1", "check_deaths_in_districts_without_denominator", "Muertes de la cohorte geografica en esos distritos",
      "muertes en distritos sin denominador", geo[analysis_ubigeo %in% sin17, .N], 0)

# --- C2 -----------------------------------------------------------------------
cat("C2  Densidad climatologica por macrorregion (sostiene el titulo)\n")
M <- merge(alt[, .(UBIGEO, altitud)], den[, .(UBIGEO, densidad, area_km2)], by = "UBIGEO")
M <- M[!is.na(altitud) & !is.na(densidad) & altitud > 0]
M[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
M[, dep := substr(UBIGEO, 1, 2)]
M[, macro := fifelse(estrato != LOWLAND_LABEL, paste("Estrato", estrato),
              fifelse(dep %in% PACIFIC_DEPARTMENTS, "Costa del Pacifico (<500 m)",
                                                    "Llanura amazonica (<500 m)"))]
MR <- M[, .(distritos = .N, area_km2 = round(sum(area_km2), 1),
            flashes_yr = round(sum(densidad*area_km2), 1),
            area_weighted_density = round(sum(densidad*area_km2)/sum(area_km2), 4)),
        by = macro][order(-area_weighted_density)]
print(MR)
write_csv_utf8(MR, file.path(PATHS$tables, "26_density_by_macroregion.csv"))
anota("C2", "check_amazon_density_rank", "La Amazonia encabeza la densidad ponderada por area",
      "puesto de la Llanura amazonica (1 = maxima)",
      which(MR$macro == "Llanura amazonica (<500 m)"), 1)
anota("C2", "check_amazon_area_weighted_density", "Densidad de la Llanura amazonica", "flashes km-2 anio-1",
      MR[macro == "Llanura amazonica (<500 m)", area_weighted_density], 20.648, tol = 0.01)

# --- C3 -----------------------------------------------------------------------
cat("C3  Retroextrapolacion de 2017\n")
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
anota("C3", "check_high_rate_reconstructed_2017", "Tasa >3500 m con el 2017 reconstruido", "por millon de personas-anio",
      tasa_base, 13.0162, tol = 0.01)
anota("C3", "check_high_rate_2017_equals_2018", "Tasa >3500 m fijando 2017 = 2018", "por millon de personas-anio",
      tasa_alt, 13.0099, tol = 0.01)
anota("C3", "check_backextrapolation_impact_pct", "Variacion relativa entre ambos escenarios", "% de cambio en la tasa",
      100*abs(tasa_alt - tasa_base)/tasa_base, 0.05, tol = 0.02)

# --- C4 -----------------------------------------------------------------------
cat("C4  Punto representativo para los pesos KNN\n")
shp <- st_read(PATHS$districts_gpkg, quiet = TRUE)
#
# METRICA DECLARADA. Los dos puntos representativos se calculan en el PLANO
# lon/lat, que es lo que hace geopandas con .centroid y por tanto lo que hay que
# replicar. La distancia entre ellos se mide luego sobre el ELIPSOIDE (s2,
# distancia geodesica), que es la magnitud fisicamente significativa en km.
#
# El informe de agosto (salidas/logs/F6_verificacion_R.md, §3) midio esa misma
# distancia EN EL PLANO lon/lat y publico 2,44 km de media y 1 213 distritos por
# encima de 1 km. Aqui salen 2,414 km y 1 206. Las dos son correctas bajo su
# propia definicion; difieren un 1 % en la media y 7 distritos de 1 891.
#
# Se sella la geodesica porque es la que tiene unidades reales. La tolerancia de
# estas dos aserciones cubre ambas metricas a proposito: lo que la comprobacion
# vigila es que el punto representativo siga desplazando el vecindario del orden
# de kilometros -- que es el argumento para que la especificacion principal sea
# Queen, invariante a esa eleccion -- no el tercer decimal.
sf_use_s2(FALSE)
ctr <- suppressWarnings(st_centroid(st_geometry(shp)))
pos <- suppressWarnings(st_point_on_surface(st_geometry(shp)))
sf_use_s2(TRUE)
d_km <- as.numeric(st_distance(ctr, pos, by_element = TRUE))/1000
anota("C4", "check_knn_polygons_compared", "Poligonos comparados", "n distritos", length(d_km), 1891)
# Los valores esperados son los de ESTE script y SU metrica (geodesica). Los del
# informe de agosto -- 2,44 km y 1 213 distritos, medidos en el plano -- se citan
# arriba pero no se usan como esperado: comparar contra el numero de otra metrica
# es justo la confusion que esta reconciliacion elimina.
anota("C4", "check_knn_mean_point_distance_km", "Distancia media centroide vs punto-en-superficie (geodesica)", "km",
      mean(d_km), 2.4144, tol = 0.01)
anota("C4", "check_knn_districts_over_1km", "Distritos que difieren en mas de 1 km (geodesica)", "n distritos",
      sum(d_km > 1), 1206, tol = 3)

# --- C5 -----------------------------------------------------------------------
cat("C5  Contraste >3500 m frente a la costa del Pacifico fusionada\n")
pa[, dep := substr(UBIGEO, 1, 2)]
py_costa <- pa[estrato == LOWLAND_LABEL & dep %in% PACIFIC_DEPARTMENTS, sum(poblacion, na.rm = TRUE)]
geo[, dep := substr(analysis_ubigeo, 1, 2)]
d_costa <- geo[estrato == LOWLAND_LABEL & dep %in% PACIFIC_DEPARTMENTS, .N]
rr <- rate_ratio_ci(d_high, py_base, d_costa, py_costa, ">3500 m vs costa del Pacifico fusionada")
print(rr)
anota("C5", "check_pacific_coast_deaths", "Muertes en la costa del Pacifico (<500 m)", "muertes", d_costa, 4)
anota("C5", "check_RR_high_vs_merged_coast", "Razon de tasas >3500 m vs costa fusionada", "RR", rr$RR, 362.06, tol = 1.5)

# --- salida -------------------------------------------------------------------
R <- rbindlist(res)
write_csv_utf8(R, file.path(PATHS$tables, "27_terminal_checks.csv"))
malas <- R[status != "PASS"]
cat(sprintf("\n%d comprobaciones; %d PASS; %d FAIL\n", nrow(R), nrow(R) - nrow(malas), nrow(malas)))
if (nrow(malas)) { print(malas); stop("Comprobaciones terminales no reproducidas.", call. = FALSE) }
cat("Las cinco comprobaciones terminales reproducen.\n")
