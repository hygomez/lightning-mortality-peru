options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root()
setwd(ROOT)
source("config/config.R")
ensure_packages(c("data.table", "ggplot2"))
suppressPackageStartupMessages(library(data.table))

A1 <- ANALYSIS$start_year
A2 <- ANALYSIS$end_year
NY <- A2 - A1 + 1L
for (p in c(PATHS$cohort_national, PATHS$cohort_geographic, PATHS$altitude,
            PATHS$population, PATHS$density, PATHS$mortality)) {
  if (!file.exists(p)) stop("Missing input: ", p, call. = FALSE)
}

dir.create(PATHS$tables, recursive = TRUE, showWarnings = FALSE)
dir.create(PATHS$figures, recursive = TRUE, showWarnings = FALSE)
dir.create(PATHS$logs, recursive = TRUE, showWarnings = FALSE)

nac <- as.data.table(readRDS(PATHS$cohort_national))
geo <- as.data.table(readRDS(PATHS$cohort_geographic))
alt <- fread(PATHS$altitude, colClasses = list(character = "UBIGEO"))
pob <- fread(PATHS$population, colClasses = list(character = "UBIGEO"))
den <- fread(PATHS$density, colClasses = list(character = "UBIGEO"))
sin <- as.data.table(readRDS(PATHS$mortality))

if (!"analysis_year" %in% names(nac)) nac[, analysis_year := year_of(analysis_date)]
if (!"analysis_year" %in% names(geo)) geo[, analysis_year := year_of(analysis_date)]
nac <- nac[analysis_year %between% c(A1, A2)]
geo <- geo[analysis_year %between% c(A1, A2)]
if (!"estrato" %in% names(geo)) geo[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]

# 1. Altitude-specific rates
pob_alt <- merge(pob[anio %between% c(A1, A2)], alt[, .(UBIGEO, altitud)], by = "UBIGEO", all.x = TRUE)
pob_alt[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
py <- pob_alt[!is.na(estrato), .(person_years = sum(poblacion, na.rm = TRUE)), by = estrato]
T1 <- merge(py, geo[, .(deaths = .N), by = estrato], by = "estrato", all.x = TRUE)
T1[is.na(deaths), deaths := 0L]
T1[, `:=`(
  rate_per_million = 1e6 * deaths / person_years,
  CI_lower = poisson_lower(deaths, person_years),
  CI_upper = poisson_upper(deaths, person_years)
)]
setorder(T1, estrato)
write_csv_utf8(T1, file.path(PATHS$tables, "01_mortality_by_altitude.csv"))

high <- T1[estrato == ">3500"]
coast <- T1[estrato == "0-500"]
rest <- T1[estrato != ">3500", .(deaths = sum(deaths), person_years = sum(person_years))]
RR <- rbind(
  rate_ratio_ci(high$deaths, high$person_years, rest$deaths, rest$person_years, ">3500 m vs rest of Peru"),
  rate_ratio_ci(high$deaths, high$person_years, coast$deaths, coast$person_years, ">3500 m vs <500 m")
)
write_csv_utf8(RR, file.path(PATHS$tables, "02_rate_ratios.csv"))

# 2. Climatological density and mortality-to-flash ratio
DD <- merge(alt[, .(UBIGEO, altitud)], den[, .(UBIGEO, densidad, area_km2)], by = "UBIGEO", all.x = TRUE)
DD <- DD[!is.na(altitud) & !is.na(densidad) & !is.na(area_km2) & area_km2 > 0]
DD[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
DD[, flashes_per_year := densidad * area_km2]
T2 <- DD[, .(
  districts = .N,
  area_km2 = sum(area_km2),
  flashes_per_year = sum(flashes_per_year),
  area_weighted_density = sum(flashes_per_year)/sum(area_km2),
  simple_mean_density = mean(densidad)
), by = estrato]
T2 <- merge(T2, T1[, .(estrato, deaths, person_years, rate_per_million)], by = "estrato")
T2[, mortality_per_million_flashes := 1e6 * (deaths/NY) / flashes_per_year]
setorder(T2, estrato)
write_csv_utf8(T2, file.path(PATHS$tables, "03_density_and_mortality_to_flashes.csv"))

d_high <- T2[estrato == ">3500"]
d_rest <- T2[estrato != ">3500", .(
  area_km2 = sum(area_km2), flashes_per_year = sum(flashes_per_year), deaths = sum(deaths)
)]
density_ratio <- (d_high$flashes_per_year/d_high$area_km2)/(d_rest$flashes_per_year/d_rest$area_km2)
mortality_flash_ratio <- (d_high$deaths/d_high$flashes_per_year)/(d_rest$deaths/d_rest$flashes_per_year)

# 3. Negative control: non-atmospheric electrocution
date_col_sin <- safe_col(sin, c("fecha", "FECHA", "FECHA.FALLECIMIENTO"), TRUE)
ubi_col_sin <- safe_col(sin, c("ubigeo_inei", "UBIGEO", "ubigeo"), TRUE)
if (!"analysis_year" %in% names(sin)) sin[, analysis_year := year_of(get(date_col_sin))]
sin <- sin[analysis_year %between% c(A1, A2)]
sin[, analysis_ubigeo := trimws(as.character(get(ubi_col_sin)))]
txtc <- grep("^DEBIDO", names(sin), value = TRUE, ignore.case = TRUE)
P_RAYO <- paste(c("RAYO", "FULGURACION", "FULGURADO", "FULMINAD", "CENTELLA",
                  "DESCARGA ATMOSFERICA", "DESCARGA ELECTRICA ATMOSFERICA",
                  "RELAMPAGO", "TORMENTA ELECTRICA", "ELECTROFULGURACION",
                  "ELECTRO FULGURACION", "ELECTRIFULGURACION"), collapse = "|")
P_FALSO <- paste(c("RESPIRAYO", "RAYOS X", "RAYO X", "X RAYO", "RAYOS UV",
                   "ULTRAVIOLETA", "RAYOS GAMMA", "RAYOS SOLARES", "LASER", "RADIOTERAPIA"), collapse = "|")
P_ELEC <- "ELECTROCUCION|ELECTROCUTAD|DESCARGA ELECTRICA|CORRIENTE ELECTRICA"
sin[, lightning_text := row_any_regex(.SD, txtc, P_RAYO, P_FALSO, normalize = TRUE)]
sin[, electrocution := row_any_regex(.SD, txtc, P_ELEC, NULL, normalize = TRUE) & !lightning_text]
if ("altitud" %in% names(sin)) sin[, altitud := NULL]
sin <- merge(sin, alt[, .(analysis_ubigeo = UBIGEO, altitud)], by = "analysis_ubigeo", all.x = TRUE)
sin[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
TC <- merge(py, sin[electrocution == TRUE & !is.na(estrato), .(electrocution_deaths = .N), by = estrato], by = "estrato", all.x = TRUE)
TC[is.na(electrocution_deaths), electrocution_deaths := 0L]
TC <- merge(TC, T1[, .(estrato, lightning_deaths = deaths, lightning_rate = rate_per_million)], by = "estrato")
TC[, electrocution_rate := 1e6 * electrocution_deaths/person_years]
setorder(TC, estrato)
write_csv_utf8(TC, file.path(PATHS$tables, "04_negative_control_electrocution.csv"))
electrocution_ratio <- (TC[estrato == ">3500", electrocution_deaths/person_years]) /
                       (TC[estrato == "0-500", electrocution_deaths/person_years])

# 4. National demographic and temporal profile
sex_col <- safe_col(nac, c("SEXO", "sexo"))
age_col <- safe_col(nac, c("edad_anios", "EDAD_ANIOS", "edad"))
place_col <- safe_col(nac, c("TIPO.LUGAR", "TIPO_LUGAR", "tipo_lugar"))
nec_col <- safe_col(nac, c("NECROPSIA", "necropsia"))
dep_col <- safe_col(nac, c("DEPARTAMEN", "DEP", "departamento"))
if ("analysis_date" %in% names(nac)) nac[, month := month_of(analysis_date)]
if (!is.na(age_col)) {
  nac[, age_years := as.numeric(get(age_col))]
  nac[, age_group := cut(age_years, c(-Inf,0,4,14,44,64,74,Inf),
                         labels = c("<1","1-4","5-14","15-44","45-64","65-74","75+"))]
}
if (!is.na(sex_col)) {
  nac[, sex_std := toupper(trimws(as.character(get(sex_col))))]
  Tsex <- nac[, .(deaths = .N), by = sex_std][order(-deaths)]
  write_csv_utf8(Tsex, file.path(PATHS$tables, "05_sex.csv"))
}
if (!is.na(age_col) && !is.na(sex_col)) {
  Tage <- dcast(nac[, .N, by = .(age_group, sex_std)], age_group ~ sex_std, value.var = "N", fill = 0)
  write_csv_utf8(Tage, file.path(PATHS$tables, "06_age_by_sex.csv"))
}
if ("month" %in% names(nac)) {
  Tmonth <- nac[!is.na(month), .N, by = month][CJ(month = 1:12), on = "month"]
  Tmonth[is.na(N), N := 0L]
  Tmonth[, month_name := month.abb[month]]
  write_csv_utf8(Tmonth, file.path(PATHS$tables, "07_monthly_distribution.csv"))
}
if (!is.na(dep_col)) {
  Tdep <- nac[, .(deaths = .N), by = .(department = get(dep_col))][order(-deaths)]
  write_csv_utf8(Tdep, file.path(PATHS$tables, "08_departments.csv"))
}

profile <- data.table(indicator = character(), value = numeric())
if (!is.na(age_col)) profile <- rbind(profile,
  data.table(indicator = "mean_age", value = mean(nac$age_years, na.rm = TRUE)),
  data.table(indicator = "median_age", value = median(nac$age_years, na.rm = TRUE)),
  data.table(indicator = "percent_age_5_14", value = 100*mean(nac$age_group == "5-14", na.rm = TRUE)))
if (!is.na(sex_col)) {
  men <- nac[sex_std == "M", .N]; women <- nac[sex_std == "F", .N]
  profile <- rbind(profile,
    data.table(indicator = "men", value = men),
    data.table(indicator = "women", value = women),
    data.table(indicator = "male_female_ratio", value = men/women))
}
if ("month" %in% names(nac)) profile <- rbind(profile,
  data.table(indicator = "percent_oct_mar", value = 100*mean(nac$month %in% c(10,11,12,1,2,3), na.rm = TRUE)))
if (!is.na(place_col)) profile <- rbind(profile,
  data.table(indicator = "percent_home", value = 100*mean(toupper(as.character(nac[[place_col]])) == "DOMICILIO", na.rm = TRUE)))
if (!is.na(nec_col)) profile <- rbind(profile,
  data.table(indicator = "percent_necropsy", value = 100*mean(grepl("^SI", toupper(as.character(nac[[nec_col]]))), na.rm = TRUE)))
write_csv_utf8(profile, file.path(PATHS$tables, "09_national_profile.csv"))

# 5. Multiple-victim events
if (all(c("analysis_ubigeo", "analysis_date") %in% names(nac))) {
  events <- nac[!is.na(analysis_ubigeo) & !is.na(analysis_date), .N, by = .(analysis_ubigeo, analysis_date)][N > 1][order(-N)]
  write_csv_utf8(events, file.path(PATHS$tables, "10_multiple_victim_events.csv"))
} else events <- data.table(N = integer())

# 6. Empirical-Bayes district rates
pyd <- pob[anio %between% c(A1, A2), .(person_years = sum(poblacion, na.rm = TRUE)), by = UBIGEO]
nd <- geo[, .(deaths = .N), by = .(UBIGEO = analysis_ubigeo)]
alt_cols <- intersect(c("UBIGEO", "altitud", "DISTRITO", "PROVINCIA", "DEPARTAMEN", "lon", "lat"), names(alt))
MD <- merge(alt[, ..alt_cols], pyd, by = "UBIGEO", all.x = TRUE)
MD <- merge(MD, nd, by = "UBIGEO", all.x = TRUE)
MD[is.na(deaths), deaths := 0L]
MD <- MD[!is.na(person_years) & person_years > 0 & !is.na(altitud)]
MD[, estrato := altitude_stratum(altitud, ANALYSIS$altitude_breaks, ANALYSIS$altitude_labels)]
MD[, crude_rate := 1e6*deaths/person_years]
s <- MD[estrato == ">3500"]
mu <- sum(s$deaths)/sum(s$person_years)
v <- var(s$deaths/s$person_years)
b <- if (is.finite(v) && v > mu/mean(s$person_years)) mu/(v - mu/mean(s$person_years)) else 100
a <- mu*b
MD[, `:=`(post_a = deaths + a, post_b = person_years + b)]
MD[, `:=`(
  posterior_rate = 1e6*post_a/post_b,
  credible_lower = 1e6*qgamma(0.025, post_a, post_b),
  credible_upper = 1e6*qgamma(0.975, post_a, post_b),
  probability_above_84 = 1 - pgamma(84/1e6, post_a, post_b)
)]
TOP <- MD[estrato == ">3500" & deaths >= 3][order(-posterior_rate)]
write_csv_utf8(MD, file.path(PATHS$tables, "11_district_rates_complete.csv"))
write_csv_utf8(head(TOP, 20), file.path(PATHS$tables, "12_highest_risk_districts.csv"))

# 7. Quasi-Poisson models
M <- merge(MD[, .(UBIGEO, altitud, person_years, deaths)], den[, .(UBIGEO, densidad)], by = "UBIGEO", all.x = TRUE)
M <- M[!is.na(densidad) & altitud > 0 & person_years > 0]
m1 <- glm(deaths ~ log(altitud) + offset(log(person_years/1e6)), family = quasipoisson(), data = M)
m2 <- glm(deaths ~ log(altitud) + log(pmax(densidad, 0.01)) + offset(log(person_years/1e6)), family = quasipoisson(), data = M)
model_table <- function(m, name) {
  z <- summary(m)$coefficients
  data.table(model = name, term = rownames(z), beta = z[,1], SE = z[,2], p_value = z[,4],
             rate_ratio_per_doubling = exp(z[,1]*log(2)))
}
MOD <- rbind(model_table(m1, "Altitude only"), model_table(m2, "Altitude plus flash density"))
write_csv_utf8(MOD, file.path(PATHS$tables, "13_quasipoisson_models.csv"))

# 8. Sensitivity analyses
sensitivity_period <- function(sub, label, years) {
  pyx <- pob_alt[anio %in% years, .(person_years = sum(poblacion, na.rm = TRUE)), by = estrato]
  nx <- sub[, .(deaths = .N), by = estrato]
  x <- merge(pyx, nx, by = "estrato", all.x = TRUE); x[is.na(deaths), deaths := 0L]
  aa <- x[estrato == ">3500"]
  rr <- x[estrato != ">3500", .(deaths = sum(deaths), person_years = sum(person_years))]
  q <- rate_ratio_ci(aa$deaths, aa$person_years, rr$deaths, rr$person_years, label)
  data.table(type = "period", scenario = label, years = paste0(min(years), "-", max(years)),
             high_deaths = aa$deaths, high_person_years = aa$person_years,
             high_rate = 1e6*aa$deaths/aa$person_years,
             high_rate_CI_lower = poisson_lower(aa$deaths, aa$person_years),
             high_rate_CI_upper = poisson_upper(aa$deaths, aa$person_years),
             RR_high_vs_rest = q$RR, RR_CI_lower = q$CI_lower, RR_CI_upper = q$CI_upper)
}
sensitivity_restriction <- function(sub, label) {
  nx <- sub[, .(deaths = .N), by = estrato]
  x <- merge(py, nx, by = "estrato", all.x = TRUE); x[is.na(deaths), deaths := 0L]
  aa <- x[estrato == ">3500"]
  rr <- x[estrato != ">3500", .(deaths = sum(deaths), person_years = sum(person_years))]
  q <- rate_ratio_ci(aa$deaths, aa$person_years, rr$deaths, rr$person_years, label)
  data.table(type = "case restriction", scenario = label, years = paste0(A1, "-", A2),
             high_deaths = aa$deaths, high_person_years = aa$person_years,
             high_rate = NA_real_, high_rate_CI_lower = NA_real_, high_rate_CI_upper = NA_real_,
             RR_high_vs_rest = q$RR, RR_CI_lower = q$CI_lower, RR_CI_upper = q$CI_upper)
}
SENS <- rbind(
  sensitivity_period(geo, "Base", A1:A2),
  sensitivity_period(geo[analysis_year >= 2018], "Exclude 2017", 2018:A2),
  sensitivity_period(geo[analysis_year <= 2022], "2017-2022 only", 2017:2022)
)
if (!is.na(place_col) && place_col %in% names(geo)) SENS <- rbind(SENS,
  sensitivity_restriction(geo[is.na(get(place_col)) | toupper(as.character(get(place_col))) != "DOMICILIO"], "Exclude deaths registered at home"))
if (!is.na(nec_col) && nec_col %in% names(geo)) SENS <- rbind(SENS,
  sensitivity_restriction(geo[grepl("^SI", toupper(as.character(get(nec_col))))], "Necropsy-confirmed only"))
if (all(c("analysis_ubigeo", "analysis_date") %in% names(geo))) SENS <- rbind(SENS,
  sensitivity_restriction(unique(geo, by = c("analysis_ubigeo", "analysis_date")), "One death per district-date event"))
write_csv_utf8(SENS, file.path(PATHS$tables, "14_sensitivity_analysis.csv"))

# 9. Figures in English
suppressPackageStartupMessages(library(ggplot2))
th <- theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold"))
f1 <- ggplot(T1, aes(estrato, rate_per_million)) + geom_col(width = 0.65) +
  geom_errorbar(aes(ymin = CI_lower, ymax = CI_upper), width = 0.18) +
  geom_text(aes(label = sprintf("%.2f", rate_per_million), y = CI_upper), vjust = -0.5, size = 3.3) +
  labs(x = "Altitude stratum (m)", y = "Deaths per million person-years",
       title = "Lightning mortality by altitude", subtitle = "Peru, 2017-2024; exact Poisson 95% confidence intervals") + th
ggsave(file.path(PATHS$figures, "Figure_1_altitude_mortality.png"), f1, width = 8, height = 5, dpi = 300)
if (exists("Tmonth")) {
  Tmonth[, month_factor := factor(month_name, levels = month.abb)]
  f2 <- ggplot(Tmonth, aes(month_factor, N)) + geom_col(width = 0.68) + geom_text(aes(label = N), vjust = -0.4, size = 3.2) +
    labs(x = NULL, y = "Deaths", title = "Seasonality of lightning mortality", subtitle = "National validated cases, Peru 2017-2024") + th
  ggsave(file.path(PATHS$figures, "Figure_2_seasonality.png"), f2, width = 8, height = 5, dpi = 300)
}
if (exists("Tage")) {
  long_age <- melt(Tage, id.vars = "age_group", variable.name = "sex", value.name = "deaths")
  f3 <- ggplot(long_age, aes(age_group, deaths, fill = sex)) + geom_col(position = "dodge") +
    labs(x = "Age group (years)", y = "Deaths", title = "Lightning deaths by age and sex", subtitle = "National validated cases, Peru 2017-2024") + th
  ggsave(file.path(PATHS$figures, "Figure_3_age_sex.png"), f3, width = 8, height = 5, dpi = 300)
}
f4data <- T2[, .(estrato, `Climatological flash density` = area_weighted_density,
                  `Population mortality` = rate_per_million,
                  `Mortality per million flashes` = mortality_per_million_flashes)]
f4long <- melt(f4data, id.vars = "estrato", variable.name = "indicator", value.name = "value")
f4 <- ggplot(f4long, aes(estrato, value)) + geom_col() + facet_wrap(~indicator, scales = "free_y", ncol = 1) +
  labs(x = "Altitude stratum (m)", y = NULL, title = "Climatological hazard and lightning mortality") + th
ggsave(file.path(PATHS$figures, "Figure_4_density_mortality.png"), f4, width = 8, height = 8.5, dpi = 300)

# 10. Machine-readable summary for QC and manuscript updating
get_profile <- function(k) { x <- profile[indicator == k, value]; if (length(x)) x[1] else NA_real_ }
checca <- TOP[toupper(DISTRITO) == "CHECCA"][1]
pilpichaca <- TOP[toupper(DISTRITO) == "PILPICHACA"][1]
m1_alt <- MOD[model == "Altitude only" & term == "log(altitud)"]
m2_alt <- MOD[model == "Altitude plus flash density" & term == "log(altitud)"]
m2_den <- MOD[model == "Altitude plus flash density" & grepl("densidad", term, fixed = TRUE)]
summary_results <- data.table(
  indicator = c("national_cases","geographic_cases","missing_altitude","high_altitude_cases",
                "high_rate","coast_rate","RR_high_rest","RR_high_coast","density_ratio_high_rest",
                "mortality_flash_ratio_high_rest","electrocution_ratio_high_coast","men","women",
                "mean_age","median_age","percent_age_5_14","percent_oct_mar","percent_home",
                "percent_necropsy","multiple_events","multiple_event_victims","checca_posterior_rate",
                "pilpichaca_posterior_rate","model_altitude_beta","model_adjusted_altitude_beta","model_density_beta"),
  value = c(nrow(nac), nrow(geo), nrow(nac)-nrow(geo), high$deaths,
            high$rate_per_million, coast$rate_per_million,
            RR[comparison == ">3500 m vs rest of Peru", RR], RR[comparison == ">3500 m vs <500 m", RR],
            density_ratio, mortality_flash_ratio, electrocution_ratio,
            get_profile("men"), get_profile("women"), get_profile("mean_age"), get_profile("median_age"),
            get_profile("percent_age_5_14"), get_profile("percent_oct_mar"), get_profile("percent_home"),
            get_profile("percent_necropsy"), nrow(events), sum(events$N),
            if (nrow(checca)) checca$posterior_rate else NA_real_,
            if (nrow(pilpichaca)) pilpichaca$posterior_rate else NA_real_,
            m1_alt$beta, m2_alt$beta, m2_den$beta)
)
write_csv_utf8(summary_results, file.path(PATHS$tables, "results_summary.csv"))

# Bilingual result summaries
make_line <- function(label, value, digits = 2) paste0("- ", label, ": **", format(round(value, digits), nsmall = digits), "**.")
writeLines(c(
  "# Validated results for the manuscript",
  "",
  paste0("Study period: ", A1, "-", A2, "."),
  "",
  "## Counts",
  paste0("- Nationally validated deaths: **", nrow(nac), "**."),
  paste0("- Deaths with district and altitude: **", nrow(geo), "**."),
  paste0("- Deaths above 3,500 m: **", high$deaths, " (", sprintf("%.1f", 100*high$deaths/nrow(geo)), "% of geocoded deaths)**."),
  "",
  "## Altitudinal gradient",
  paste0("- Rate above 3,500 m: **", sprintf("%.2f", high$rate_per_million), "** per million person-years (95% CI ", sprintf("%.2f", high$CI_lower), "-", sprintf("%.2f", high$CI_upper), ")."),
  paste0("- Rate below 500 m: **", sprintf("%.2f", coast$rate_per_million), "** per million person-years."),
  paste0("- Rate ratio above 3,500 m versus the rest of Peru: **", sprintf("%.1f", RR[comparison == ">3500 m vs rest of Peru", RR]), "**."),
  paste0("- Rate ratio above 3,500 m versus below 500 m: **", sprintf("%.1f", RR[comparison == ">3500 m vs <500 m", RR]), "**."),
  "",
  "## Key interpretation",
  paste0("- Climatological flash-density ratio above 3,500 m/rest: **", sprintf("%.2f", density_ratio), "**."),
  paste0("- Mortality-to-flash ratio above 3,500 m/rest: **", sprintf("%.1f", mortality_flash_ratio), "**."),
  paste0("- Non-atmospheric electrocution high/coast ratio: **", sprintf("%.2f", electrocution_ratio), "**."),
  "",
  "The national cohort is used for demographic and temporal analyses; the geocoded cohort is used for altitude, district, mapping, and regression analyses."
), "results/RESULTS_FOR_MANUSCRIPT_EN.md", useBytes = TRUE)

writeLines(c(
  "# Resultados validados para el manuscrito",
  "",
  paste0("Periodo: ", A1, "-", A2, "."),
  "",
  paste0("- Casos nacionales validados: **", nrow(nac), "**."),
  paste0("- Casos con distrito y altitud: **", nrow(geo), "**."),
  paste0("- Casos por encima de 3 500 m: **", high$deaths, " (", sprintf("%.1f", 100*high$deaths/nrow(geo)), " %)**."),
  paste0("- Tasa >3 500 m: **", sprintf("%.2f", high$rate_per_million), "** por millón de personas-año."),
  paste0("- Razón >3 500 m/resto: **", sprintf("%.1f", RR[comparison == ">3500 m vs rest of Peru", RR]), "**."),
  paste0("- Razón >3 500 m/<500 m: **", sprintf("%.1f", RR[comparison == ">3500 m vs <500 m", RR]), "**."),
  paste0("- Razón de densidad climatológica >3 500 m/resto: **", sprintf("%.2f", density_ratio), "**."),
  paste0("- Razón mortalidad-descargas >3 500 m/resto: **", sprintf("%.1f", mortality_flash_ratio), "**."),
  paste0("- Gradiente altura/costa para electrocución no atmosférica: **", sprintf("%.2f", electrocution_ratio), "**.")
), "results/RESULTADOS_PARA_MANUSCRITO_ES.md", useBytes = TRUE)

cat("Analysis completed. Tables:", PATHS$tables, "Figures:", PATHS$figures, "\n")
