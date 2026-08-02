ANALYSIS <- list(
  start_year = 2017L,
  end_year = 2024L,
  altitude_breaks = c(-Inf, 500, 1500, 2500, 3500, Inf),
  altitude_labels = c("0-500", "500-1500", "1500-2500", "2500-3500", ">3500")
)

PATHS <- list(
  mortality = "data/restricted/sinadef_limpio.rds",
  population = "data/processed/poblacion_distrital.csv",
  altitude = "data/processed/distritos_altitud.csv",
  density = "data/processed/rayo_densidad_distrito.csv",
  districts_gpkg = "data/spatial/districts.gpkg",
  cohort_national = "data/derived/private/rayo_validado_nacional.rds",
  cohort_geographic = "data/derived/private/rayo_validado_geografico.rds",
  public_derived = "data/derived/public",
  tables = "output/tables",
  figures = "output/figures",
  logs = "output/logs",
  qc = "output/qc"
)

EXPECTED <- list(
  candidates_before_context_adjudication = 594L,
  excluded_cardiac_storm = 1L,
  national_cases = 593L,
  geographic_cases = 591L,
  missing_altitude = 2L,
  high_altitude_cases = 510L,
  text_only_cases = 158L,
  cie_only_cases = 15L,
  text_and_cie_cases = 420L
)

REPOSITORY_VERSION <- "1.0.0"
