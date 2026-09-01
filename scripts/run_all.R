options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT)

# Orden de dependencias (v2.0.0):
#   01 cohorte -> 02 analisis principal -> 03 mapa
#   06 diagnostico espacial   (usa la cohorte y las proyecciones)
#   07 especificaciones       (produce 20_mfr_auditable_lod.csv)
#   09 figuras del manuscrito (CONSUME la tabla 20, por eso va despues de 07)
#   08 comprobaciones terminales
#   04 control de calidad     (exige que las figuras ya existan)
#   05 exportacion publica
source("scripts/01_build_validated_cohort.R")
source("scripts/02_run_analysis.R")
tryCatch(source("scripts/03_make_district_map.R"),
         error = function(e) message("Map warning: ", conditionMessage(e)))
source("scripts/06_spatial_diagnostics.R")
source("scripts/07_sensitivity_specifications.R")
source("scripts/09_figures_manuscript.R")
source("scripts/08_terminal_checks.R")
source("scripts/04_quality_control.R")
source("scripts/05_export_public_release.R")
cat("\nCOMPLETE: numerical QC passed and the public aggregate release was created.\n")
