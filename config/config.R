ANALYSIS <- list(
  start_year = 2017L,
  end_year = 2024L,
  altitude_breaks = c(-Inf, 500, 1500, 2500, 3500, Inf),
  # REP-009: el estrato mas bajo se rotulaba "0-500", que se leia como "la costa".
  # Esta dominado por la llanura amazonica: Loreto, Ucayali y Madre de Dios aportan
  # 530 393 de sus 608 166 km2 (87 %). El rotulo "lowland (<500 m)" es neutro y no
  # prejuzga la region. Las cifras no cambian; solo el rotulo.
  altitude_labels = c("lowland (<500 m)", "500-1500", "1500-2500", "2500-3500", ">3500")
)

# Rotulo del estrato mas bajo, para no repetir el literal por el codigo.
LOWLAND_LABEL <- ANALYSIS$altitude_labels[1]

# Limite de deteccion del producto climatologico LIS/OTD (flashes km-2 anio-1).
#
# El producto no distingue "sin descargas" de "por debajo de lo detectable": ambos
# llegan como cero. Un cero crudo en la escala logaritmica del Modelo 2 es -Inf, de
# modo que hay que imputar algun valor. La v1.0.0 usaba un piso arbitrario de 0,01,
# elegido por conveniencia numerica y sin base fisica.
#
# 0.412787 es el menor valor NO nulo representable en la malla del producto para el
# periodo climatologico: es decir, el limite de deteccion efectivo. Imputar ahi es
# la lectura conservadora de la censura -- se afirma que la celda esta por debajo de
# lo detectable, no que reciba una centesima de descarga.
#
# Efecto: despreciable en los cinco estratos de altitud (entre -0,02 % y -0,46 %) y
# grande en un solo subgrupo, la costa del Pacifico (<500 m), donde el 52,7 % de los
# distritos esta censurado y el MFR cae un 21,63 %. Las dos lecturas se publican lado
# a lado en la Tabla 2 para que el lector compruebe que la conclusion no depende del
# tratamiento de la censura.
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

# Departamentos con vertiente pacifica, por los dos primeros digitos del UBIGEO.
# Un distrito del estrato lowland se clasifica como "Pacific coast" si su UBIGEO
# empieza por uno de estos codigos, y como "Amazon lowland" en caso contrario: la
# regla se aplica POR EXCLUSION, de modo que el subgrupo amazonico es el complemento
# y ningun distrito queda sin clasificar. Reparte los 309 distritos del estrato en
# 201 de costa y 108 de llanura amazonica. La clasificacion es administrativa, no
# ecologica: usa el departamento como aproximacion de la vertiente y no pretende
# situar la divisoria continental a resolucion distrital.
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
