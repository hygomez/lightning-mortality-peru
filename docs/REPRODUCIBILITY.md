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

---

## Line endings (v2.0.0)

All text in this repository is **LF**, declared in `.gitattributes`. This matters
because the checksums in `data/derived/public/input_checksums_local_run.csv` are
md5 sums of files: a clone that converts CSVs to CRLF changes every one of those
sums while leaving the content identical.

If a checksum does not match, compare the **`md5_normalized_lf`** column instead.
It is computed over the content with carriage returns stripped, so it is invariant
to how the file travelled. If the normalised sum matches and the raw one does not,
the difference is line endings and nothing else.

The manifest also records the `line_ending` actually observed for each text input.

## Environment for the spatial analyses

`scripts/06_spatial_diagnostics.R` needs `sf` and `spdep` in addition to the core
packages, and `scripts/07_sensitivity_specifications.R` needs `MASS`. If they are
missing the pipeline stops with an explicit message rather than skipping steps.

The spatial chain is **entirely in R**. The August work used Python
(`libpysal` 4.15.0, `esda` 2.10.0, `geopandas` 1.1.4) for Moran's I; that route was
reimplemented in R so the deposit has a single toolchain. When a Python reference
run is present at `data/derived/public/moran_python_reference.csv`, script 06 writes
a cross-check to `16b_moran_r_vs_python.csv`; when it is absent, the comparison is
skipped and the script continues.

Moran's I uses 9,999 permutations with `set.seed(20260825)`, so p values are
reproducible run to run on the same platform.

## Known cross-platform behaviour

Fifteen rows of `11_district_rates_complete.csv` may differ in the **last
significant digit** of `credible_upper` between machines, because `qgamma` is
evaluated iteratively by the platform's C library. This is documented in
`CHANGELOG.md` under "Known behaviour - not a defect". It affects no published
figure, no sealed indicator, and no table ordering.

A replicator who observes exactly this has reproduced the analysis correctly.
