# =============================================================================
# 07_sensitivity_specifications.R  -- Especificaciones y sensibilidad (v2.0.0)
#
# Porta al deposito lo que vivia fuera de el (F9, F3b, F3_final):
#
#   1. Regla operacional de subgrupos del estrato lowland (11 departamentos)
#   2. Tabla 1b: subgrupos con IC exactos de Poisson
#   3. Tabla 2: MFR auditable, ceros crudos y LOD lado a lado
#   4. Cinco tratamientos de la censura de densidad (LODx5)
#   5. Poisson frente a binomial negativa, por AIC
#   6. Sensibilidad al ancho de banda del nucleo de Conley
#   7. Tablas agregadas de eventos (S1), sin fechas ni distritos
#
# La regla de los 11 departamentos NO estaba en ningun script: se habia ejecutado
# en linea. Es la que sostiene la comparacion del titulo, de modo que su ausencia
# era el hueco de trazabilidad mas grave del deposito.
# =============================================================================

options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages(c("data.table", "MASS"))
suppressPackageStartupMessages({library(data.table); library(MASS)})

A1 <- ANALYSIS$start_year; A2 <- ANALYSIS$end_year
NY <- A2 - A1 + 1L; LN2 <- log(2)

dir.create(PATHS$logs, recursive = TRUE, showWarnings = FALSE)
log_lines <- c()
say <- function(...) { s <- paste0(...); cat(s, "\n"); log_lines <<- c(log_lines, s) }

alt <- fread(PATHS$altitude,   colClasses = list(character = "UBIGEO"))
pob <- fread(PATHS$population, colClasses = list(character = "UBIGEO"))
den <- fread(PATHS$density,    colClasses = list(character = "UBIGEO"))
geo <- as.data.table(readRDS(PATHS$cohort_geographic))
if (!"analysis_year" %in% names(geo)) geo[, analysis_year := year_of(analysis_date)]
geo <- geo[analysis_year %between% c(A1, A2)]

pyd <- pob[anio %between% c(A1, A2), .(py = sum(poblacion, na.rm = TRUE)), by = UBIGEO]
nd  <- geo[, .(deaths = .N), by = .(UBIGEO = analysis_ubigeo)]
alt_cols <- intersect(c("UBIGEO", "altitud", "DEPARTAMEN", "lon", "lat"), names(alt))
M <- merge(alt[, ..alt_cols], pyd, by = "UBIGEO")
M <- merge(M, nd, by = "UBIGEO", all.x = TRUE); M[is.na(deaths), deaths := 0L]
M <- merge(M, den[, .(UBIGEO, densidad, area_km2)], by = "UBIGEO")
M <- M[!is.na(altitud) & py > 0 & !is.na(densidad) & altitud > 0]
M[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
M[, dep := substr(UBIGEO, 1, 2)]
M[, `:=`(fl_raw = densidad*area_km2,
         fl_lod = pmax(densidad, LOD_FLASH_DENSITY)*area_km2)]
say(sprintf("Panel: %d distritos, %d muertes.", nrow(M), sum(M$deaths)))

# =============================================================================
# 1. Regla operacional de subgrupos del estrato lowland
# =============================================================================
M[, subgrupo := fifelse(estrato != LOWLAND_LABEL, NA_character_,
                 fifelse(dep %in% PACIFIC_DEPARTMENTS, "Pacific coast", "Amazon lowland"))]
REGLA <- M[!is.na(subgrupo), .(districts = .N), by = .(subgrupo, dep, DEPARTAMEN)][order(subgrupo, dep)]
write_csv_utf8(REGLA, file.path(PATHS$tables, "18_lowland_subgroup_rule.csv"))
say("=== REGLA DE SUBGRUPOS (aplicada por exclusion) ===")
for (g in unique(REGLA$subgrupo)) {
  x <- REGLA[subgrupo == g]
  say(sprintf("%s: %d distritos en %d departamentos", g, sum(x$districts), nrow(x)))
  say(paste0("   ", paste(sprintf("%s (%s, n=%d)", x$DEPARTAMEN, x$dep, x$districts), collapse = "; ")))
}
stopifnot(M[estrato == LOWLAND_LABEL & is.na(subgrupo), .N] == 0L)

# =============================================================================
# 2. Tabla 1b: subgrupos con IC exactos de Poisson
# =============================================================================
M[, grupo := fifelse(estrato == ">3500", "High-Andean stratum (>3,500 m)",
             fifelse(estrato != LOWLAND_LABEL, "Intermediate strata (500-3,500 m)",
             fifelse(dep %in% PACIFIC_DEPARTMENTS, "Lowland: Pacific coast (<500 m)",
                                                   "Lowland: Amazon lowland (<500 m)")))]
T1b <- M[, .(districts = .N, area_km2 = round(sum(area_km2)),
             person_years = round(sum(py)), deaths = sum(deaths),
             flashes_yr = round(sum(fl_raw)),
             density = round(sum(fl_raw)/sum(area_km2), 3),
             n_censored = sum(densidad == 0)), by = grupo]
T1b[, `:=`(rate  = round(1e6*deaths/person_years, 4),
           ci_lo = round(poisson_lower(deaths, person_years), 4),
           ci_hi = round(poisson_upper(deaths, person_years), 4),
           MFR   = round(1e6*(deaths/NY)/flashes_yr, 4))]
ord <- c("High-Andean stratum (>3,500 m)", "Intermediate strata (500-3,500 m)",
         "Lowland: Amazon lowland (<500 m)", "Lowland: Pacific coast (<500 m)")
T1b <- T1b[match(ord, grupo)]
write_csv_utf8(T1b, file.path(PATHS$tables, "19_lowland_subgroups_ci.csv"))

# =============================================================================
# 2b. Contrastes separados: el estrato alto frente a CADA subgrupo del lowland
#
# Fusionar los dos subgrupos en un solo "0-500 m" promedia dos regiones opuestas:
# la llanura amazonica, que es la de mayor densidad del pais, y la costa del
# Pacifico, que es la de menor. El contraste con la Amazonia es el que sostiene
# el titulo -- mas mortalidad donde MENOS rayos caen no seria noticia; la noticia
# es que ocurre frente a la region que MAS recibe.
# =============================================================================
contraste <- function(etiqueta, sub) {
  d1 <- M[estrato == ">3500"]
  q  <- rate_ratio_ci(sum(d1$deaths), sum(d1$py), sum(sub$deaths), sum(sub$py), etiqueta)
  data.table(comparacion = etiqueta,
             RR = q$RR, IC_inf = q$CI_lower, IC_sup = q$CI_upper,
             muertes_ref = sum(sub$deaths), py_ref = round(sum(sub$py)),
             tasa_ref = 1e6*sum(sub$deaths)/sum(sub$py),
             razon_densidad = (sum(d1$fl_lod)/sum(d1$area_km2)) / (sum(sub$fl_lod)/sum(sub$area_km2)),
             razon_MFR = ((sum(d1$deaths)/NY)/sum(d1$fl_lod)) / ((sum(sub$deaths)/NY)/sum(sub$fl_lod)))
}
CONTR <- rbind(
  contraste(">3500 m vs Amazon lowland (<500 m)",
            M[estrato == LOWLAND_LABEL & !dep %in% PACIFIC_DEPARTMENTS]),
  contraste(">3500 m vs Pacific coast (<500 m)",
            M[estrato == LOWLAND_LABEL &  dep %in% PACIFIC_DEPARTMENTS]))
write_csv_utf8(CONTR, file.path(PATHS$tables, "28_subgroup_contrasts.csv"))
say("=== CONTRASTES SEPARADOS ===")
for (i in seq_len(nrow(CONTR)))
  with(CONTR[i], say(sprintf("  %-38s RR %9.3f (%.2f-%.2f)  densidad %.4f x  MFR %.2f x",
                             comparacion, RR, IC_inf, IC_sup, razon_densidad, razon_MFR)))

# =============================================================================
# 3. Tabla 2: MFR auditable -- ceros crudos y LOD lado a lado
# =============================================================================
grp <- function(d, lab) data.table(
  fila = lab, distritos = nrow(d), censurados = sum(d$densidad == 0),
  pct_cens = round(100*mean(d$densidad == 0), 1), area = round(sum(d$area_km2)),
  area_cens_pct = round(100*sum(d$area_km2[d$densidad == 0])/sum(d$area_km2), 1),
  D_total = sum(d$deaths), D_s = round(sum(d$deaths)/NY, 3),
  dens_raw = round(sum(d$fl_raw)/sum(d$area_km2), 3), F_raw = round(sum(d$fl_raw)),
  MFR_raw  = round(1e6*(sum(d$deaths)/NY)/sum(d$fl_raw), 4),
  dens_lod = round(sum(d$fl_lod)/sum(d$area_km2), 3), F_lod = round(sum(d$fl_lod)),
  MFR_lod  = round(1e6*(sum(d$deaths)/NY)/sum(d$fl_lod), 4))
G <- rbindlist(c(
  lapply(ANALYSIS$altitude_labels, function(e) grp(M[estrato == e], e)),
  list(grp(M[estrato == LOWLAND_LABEL & !dep %in% PACIFIC_DEPARTMENTS], "  Amazon lowland (<500 m)"),
       grp(M[estrato == LOWLAND_LABEL &  dep %in% PACIFIC_DEPARTMENTS], "  Pacific coast (<500 m)"))))
G[, cambio_MFR_pct := round(100*(MFR_lod - MFR_raw)/MFR_raw, 2)]
write_csv_utf8(G, file.path(PATHS$tables, "20_mfr_auditable_lod.csv"))
say("=== TABLA 2: efecto del LOD sobre el MFR (%) ===")
for (i in seq_len(nrow(G))) with(G[i], say(sprintf("  %-28s cens %5.1f%%  MFR %9.4f -> %9.4f  (%+6.2f %%)",
                                                   fila, pct_cens, MFR_raw, MFR_lod, cambio_MFR_pct)))

# =============================================================================
# 4. Cinco tratamientos de la censura de densidad
# =============================================================================
M[, `:=`(lalt = log(altitud), off = log(py/1e6))]
especs <- list(
  list(id = "(a) piso arbitrario 0,01",    piso = 0.01,                       dat = "todos"),
  list(id = "LOD/2 = 0,2064",              piso = LOD_FLASH_DENSITY/2,        dat = "todos"),
  list(id = "LOD/raiz(2) = 0,2919",        piso = LOD_FLASH_DENSITY/sqrt(2),  dat = "todos"),
  list(id = "LOD = 0,4128  [PRINCIPAL]",   piso = LOD_FLASH_DENSITY,          dat = "todos"),
  list(id = "(c) exclusion de censurados", piso = 0.01,                       dat = "nocens"))
filas <- list()
for (e in especs) {
  d <- if (e$dat == "nocens") M[densidad > 0] else copy(M)
  d <- copy(d); d[, ldens := log(pmax(densidad, e$piso))]
  m <- glm(deaths ~ lalt + ldens + offset(off), family = quasipoisson(), data = d)
  z <- summary(m)$coefficients
  for (tm in c("lalt", "ldens")) {
    b <- z[tm, 1]; se <- z[tm, 2]
    filas[[length(filas)+1]] <- data.table(
      especificacion = e$id, n = nrow(d),
      parametro = ifelse(tm == "lalt", "Altitud", "Densidad"),
      beta = b, SE = se, IRR = exp(b*LN2),
      IC95_inf = exp((b - 1.96*se)*LN2), IC95_sup = exp((b + 1.96*se)*LN2),
      p_value = z[tm, 4], dispersion = summary(m)$dispersion, muertes = sum(d$deaths))
  }
}
LODT <- rbindlist(filas)
write_csv_utf8(LODT, file.path(PATHS$tables, "21_lod_five_specifications.csv"))
a <- LODT[parametro == "Altitud"]
say(sprintf("IRR de altitud en las cinco especificaciones: %.3f a %.3f; todos los IC excluyen 1: %s",
            min(a$IRR), max(a$IRR), all(a$IC95_inf > 1)))

# =============================================================================
# 5. Poisson frente a binomial negativa (AIC)
# =============================================================================
M[, ldens := log(pmax(densidad, LOD_FLASH_DENSITY))]
nb_rob <- function(f) {
  best <- NULL
  for (it in c(0.05, 0.1, 0.2, 0.3, 0.5, 0.8, 1, 2)) {
    r <- tryCatch(suppressWarnings(MASS::glm.nb(f, data = M, init.theta = it,
                                                control = glm.control(maxit = 500))),
                  error = function(e) NULL)
    if (!is.null(r) && isTRUE(r$converged) && (is.null(best) || logLik(r) > logLik(best))) best <- r
  }
  best
}
f1 <- deaths ~ lalt + offset(off); f2 <- deaths ~ lalt + ldens + offset(off)
po1 <- glm(f1, family = poisson(), data = M); po2 <- glm(f2, family = poisson(), data = M)
nb1 <- nb_rob(f1); nb2 <- nb_rob(f2)
AJ <- data.table(
  modelo  = rep(c("Modelo 1: altitud sola", "Modelo 2: altitud + densidad"), each = 2),
  familia = rep(c("Poisson", "Binomial negativa"), 2),
  AIC = round(c(AIC(po1), AIC(nb1), AIC(po2), AIC(nb2)), 1),
  theta = c(NA, round(nb1$theta, 4), NA, round(nb2$theta, 4)))
AJ[, ventaja_AIC_NB := c(NA, round(AIC(po1) - AIC(nb1), 0), NA, round(AIC(po2) - AIC(nb2), 0))]
write_csv_utf8(AJ, file.path(PATHS$tables, "22_poisson_vs_negbin_aic.csv"))

# =============================================================================
# 6. Sensibilidad al ancho de banda del nucleo de Conley
# =============================================================================
hav <- function(lon, lat) {
  R <- 6371; la <- lat*pi/180; lo <- lon*pi/180
  a <- sin(outer(la, la, "-")/2)^2 + outer(cos(la), cos(la), "*")*sin(outer(lo, lo, "-")/2)^2
  2*R*asin(pmin(1, sqrt(a)))
}
D2 <- hav(M$lon, M$lat)
conley <- function(m, dist, cut) {
  X <- model.matrix(m); mu <- fitted(m); u <- residuals(m, type = "response")
  K <- pmax(0, 1 - dist/cut); br <- solve(crossprod(X, X*mu))
  br %*% (t(X) %*% (outer(u, u)*K) %*% X) %*% br
}
q1 <- glm(deaths ~ lalt + offset(off),          family = quasipoisson(), data = M)
q2 <- glm(deaths ~ lalt + ldens + offset(off),  family = quasipoisson(), data = M)
fila_bw <- function(m, tm, mod, bw) {
  b <- coef(m)[tm]
  se <- if (is.na(bw)) sqrt(diag(vcov(m)))[tm] else sqrt(diag(conley(m, D2, bw)))[tm]
  data.table(modelo = mod, ancho_km = ifelse(is.na(bw), "sin correccion", as.character(bw)),
             beta = round(b, 4), SE = round(se, 4), MRR = round(exp(b*LN2), 3),
             IC95_inf = round(exp((b - 1.96*se)*LN2), 3),
             IC95_sup = round(exp((b + 1.96*se)*LN2), 3),
             p = signif(2*pnorm(-abs(b/se)), 3))
}
S <- rbindlist(c(
  lapply(list(NA, 100, 250, 500), function(bw) fila_bw(q1, "lalt",  "Modelo 1: altitud sola", bw)),
  lapply(list(NA, 100, 250, 500), function(bw) fila_bw(q2, "lalt",  "Modelo 2: altitud ajustada", bw)),
  lapply(list(NA, 100, 250, 500), function(bw) fila_bw(q2, "ldens", "Modelo 2: densidad", bw))))
write_csv_utf8(S, file.path(PATHS$tables, "23_conley_bandwidth_sensitivity.csv"))
say("El MRR es identico en los cuatro anchos: el coeficiente no depende del estimador de varianza.")

# =============================================================================
# 7. Tablas agregadas de eventos (sin fechas ni distritos)
# =============================================================================
ev <- geo[!is.na(analysis_ubigeo) & !is.na(analysis_date),
          .(victimas = .N), by = .(analysis_ubigeo, analysis_date)]
ev <- merge(ev, alt[, .(analysis_ubigeo = UBIGEO, altitud)], by = "analysis_ubigeo", all.x = TRUE)
ev[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
ev[, sobre3500 := fifelse(estrato == ">3500", "Sobre 3500 m", "Igual o debajo de 3500 m")]
S1A <- ev[, .(eventos = .N, victimas = sum(victimas)), by = .(victimas_por_evento = victimas)][order(victimas_por_evento)]
S1A[, `:=`(pct_eventos  = round(100*eventos/sum(eventos), 2),
           pct_victimas = round(100*victimas/sum(victimas), 2), panel = "A_tamano_de_evento")]
S1B <- ev[, .(eventos = .N, victimas = sum(victimas),
              eventos_multivictima = sum(victimas > 1),
              victimas_en_multivictima = sum(victimas[victimas > 1]),
              victimas_por_evento_media = round(mean(victimas), 4),
              max_victimas = max(victimas)), by = sobre3500][order(-eventos)]
S1B <- rbind(S1B, data.table(
  sobre3500 = "TOTAL", eventos = nrow(ev), victimas = sum(ev$victimas),
  eventos_multivictima = ev[victimas > 1, .N],
  victimas_en_multivictima = ev[victimas > 1, sum(victimas)],
  victimas_por_evento_media = round(mean(ev$victimas), 4), max_victimas = max(ev$victimas)))
S1B[, `:=`(pct_eventos_multiv = round(100*eventos_multivictima/eventos, 2), panel = "B_por_altitud")]
write_csv_utf8(S1A, file.path(PATHS$tables, "24_event_size_distribution.csv"))
write_csv_utf8(S1B, file.path(PATHS$tables, "25_events_by_altitude.csv"))

writeLines(log_lines, file.path(PATHS$logs, "07_sensitivity_specifications.log"), useBytes = TRUE)
cat("Especificaciones y sensibilidad completas.\n")
