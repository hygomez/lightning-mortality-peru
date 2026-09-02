ANALYSIS <- list(
  start_year = 2017L,
  end_year = 2024L,
  altitude_breaks = c(-Inf, 500, 1500, 2500, 3500, Inf),
  # REP-009: the lowest stratum was labelled "0-500", which read as "the coast".
  # It is dominated by the Amazon lowlands: Loreto, Ucayali and Madre de Dios
  # contribute 530,393 of its 608,166 km2 (87 %). The label "lowland (<500 m)" is
  # neutral about the region. The figures do not change; only the label.
  altitude_labels = c("lowland (<500 m)", "500-1500", "1500-2500", "2500-3500", ">3500")
)

# Label of the lowest stratum, so the literal is not repeated across the code.
LOWLAND_LABEL <- ANALYSIS$altitude_labels[1]

# Detection limit of the LIS/OTD climatological product (flashes km-2 year-1).
#
# The product does not distinguish "no flashes" from "below what the instrument can
# detect": both arrive as zero. A raw zero is -Inf on the log scale used by Model 2,
# so some value must be imputed. Version 1.0.0 used an arbitrary floor of 0.01,
# chosen for numerical convenience and with no physical basis.
#
# 0.412787 is the smallest NON-ZERO value representable in the product grid for the
# climatological period, that is, the effective limit of detection. Imputing there
# is the conservative reading of the censoring: it asserts that the cell is below
# what could be detected, not that it receives a hundredth of a flash.
#
# Effect: negligible across the five altitude strata (-0.02 % to -0.46 %), and large
# in a single subgroup, the Pacific coast (<500 m), where 52.7 % of districts are
# censored and the mortality-to-flash ratio falls by 21.63 %. Both readings are
# published side by side in Table 2 so a reader can check that the conclusion does
# not depend on how the censoring is treated.
LOD_FLASH_DENSITY <- 0.412787

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

# Departments with a Pacific watershed, by the first two digits of the UBIGEO.
# A district in the lowland stratum is classified as "Pacific coast" if its UBIGEO
# begins with one of these codes, and as "Amazon lowland" otherwise: the rule is
# applied BY EXCLUSION, so the Amazon subgroup is the complement and no district is
# left unclassified. It splits the 309 districts of the stratum into 201 coastal and
# 108 Amazon lowland. The classification is administrative rather than ecological:
# it uses department of location as a proxy for watershed and does not attempt to
# place the continental divide at district resolution.
PACIFIC_DEPARTMENTS <- c("02", "04", "07", "11", "13", "14", "15", "18", "20", "23", "24")
PACIFIC_DEPARTMENT_NAMES <- c(
  "02" = "Ancash", "04" = "Arequipa", "07" = "Callao", "11" = "Ica",
  "13" = "La Libertad", "14" = "Lambayeque", "15" = "Lima", "18" = "Moquegua",
  "20" = "Piura", "23" = "Tacna", "24" = "Tumbes")

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

REPOSITORY_VERSION <- "2.0.0"
