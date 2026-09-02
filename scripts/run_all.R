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

# Nothing in the repository should go unexercised. Nine defects found on
# 2026-09-01 shared one cause: run_all.R ran 58 % of the executable files, and
# what it did not run had never been executed at all -- including the script that
# builds the public package and the one that seals the environment. See REP-017.
#
# The three steps below close that gap. They run last because they describe or
# verify the run rather than produce it: the tests are independent of the data,
# and the metadata and lockfile must reflect the repository in its final state.
source("tests/test_case_definition.R")
source("scripts/90_finalize_metadata.R")
source("scripts/99_freeze_environment.R")

cat("\nCOMPLETE: numerical QC passed and the public aggregate release was created.\n")
