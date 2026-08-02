# Reproducibility protocol

## Computational boundary

The public pipeline starts from four standardized local inputs:

1. `data/restricted/sinadef_limpio.rds`
2. `data/processed/poblacion_distrital.csv`
3. `data/processed/distritos_altitud.csv`
4. `data/processed/rayo_densidad_distrito.csv`

The first file contains individual-level mortality records and is never publicly released. The other three are district-level inputs. Their exact source files, access dates, transformations, and checksums must be recorded in `metadata/data_sources.csv`.

## One-command reproduction

```r
source("scripts/run_all.R")
```

The process intentionally stops if the principal validated counts differ from 593 national cases, 591 geocoded cases, or 510 deaths above 3,500 m.

## Case definition

Cases are identified through normalized searches in six cause-of-death text fields and ICD-10 codes X33/T75.0. The code excludes radiological uses of the word “ray” and a contextual false positive in which “electrical storm” denotes a cardiac arrhythmia rather than atmospheric lightning.

## Numerical verification

`04_quality_control.R` compares the generated summary with `results/reference/expected_results.csv`. The public release is not created when any numerical test fails.

## Environment

Before public release, run:

```r
source("scripts/99_freeze_environment.R")
```

Commit `renv.lock` and `session-info.txt`.
