# Changelog

All notable changes to this repository are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the archived Zenodo releases.

---

## [2.0.0] - unreleased

Specification release. **The case definition, the manual adjudication, and the
validated cohort are unchanged**: still 593 national deaths, 591 with district and
altitude, 510 above 3,500 m. What changes is how censored flash density is treated,
how uncertainty is reported, and how much of the analysis is actually reproducible
from code in this repository.

### Changed - flash-density censoring, and why it is a correction rather than a preference

Version 1.0.0 fitted Model 2 with `log(pmax(densidad, 0.01))`. The 0.01 was an
arbitrary numerical floor, chosen so that the logarithm would not diverge.

The LIS/OTD climatological product does not distinguish "no flashes" from "below
what the instrument can detect": both arrive as zero. **190 of the 1,891 districts
are censored this way**, and 106 of them are in a single subgroup, the Pacific
coast, where 52.7 % of districts are censored.

The problem with 0.01 is not that it is small. It is that it is *far outside the
support of the data*. The smallest non-zero value the product can represent for the
climatological period is **0.412787 flashes km⁻² year⁻¹** — the effective limit of
detection. Imputing 0.01 asserts that those districts receive one hundredth of a
flash per km² per year, which the instrument could never have measured. On the log
scale it injects `log(0.01) = -4.605` into 190 districts, against `log(0.412787) =
-0.885` for the same districts under the detection-limit reading: a displacement of
**3.7 log units** in a tenth of the sample.

That displacement is absorbed by the variance, not by the coefficients. The effect
is visible in the quasi-Poisson dispersion parameter:

| Model | φ under floor 0.01 (v1.0.0) | φ under LOD (v2.0.0) |
|---|---|---|
| Altitude only | 18.67 | 18.67 (unchanged; no density term) |
| Altitude + flash density | **28.71** | **3.77** |

Adding a covariate that is supposed to *explain* variation made the dispersion
**worse** than the model without it (28.71 against 18.67). That is the signature of
a misspecified covariate, not of a noisy one. Under the detection limit the same
covariate behaves as expected and dispersion falls to 3.77.

Because φ scales the standard errors, this is where the inference changes:

| Quantity | v1.0.0 | v2.0.0 |
|---|---|---|
| β altitude, adjusted | 2.0216147 (SE 0.7261238) | **2.0425237** (SE 0.2560915) |
| MRR per doubling of altitude | 4.060 | **4.120** |
| β flash density | 0.9063378 (SE 0.3336838) | **1.0071224** (SE 0.1241976) |
| MRR per doubling of flash density | 1.874 | **2.010** |

The point estimates barely move — about 1 % and 11 %. What moves is the precision,
and it moves because the model stopped being asked to accommodate 190 impossible
values. This is why the change is reported as a correction: the v1.0.0 floor was
not a conservative choice, it was an artefact that inflated the very quantity used
to build the confidence intervals.

The two readings are published side by side in `20_mfr_auditable_lod.csv` so the
claim can be audited. At stratum level the difference is negligible (−0.02 % to
−0.46 %); it is material in exactly one subgroup, the Pacific coast, where the
mortality-to-flash ratio falls 21.63 %. **No conclusion in the study depends on the
choice**: the altitude gradient holds under all five treatments of the censoring
(`21_lod_five_specifications.csv`).

### Added

- `scripts/06_spatial_diagnostics.R` - district spatial panel, Moran's I with Queen
  and KNN-8 weights, and Conley spatially robust standard errors. The panel it
  writes was previously an *input* to two other analyses that no script produced.
- `scripts/07_sensitivity_specifications.R` - lowland subgroup rule, subgroup
  contrasts, auditable mortality-to-flash table, five censoring treatments,
  Poisson versus negative binomial, Conley bandwidth sensitivity, event tables.
- `scripts/08_terminal_checks.R` - twelve assertions that previously existed only as
  numbers quoted in reports. The script fails if any of them stops reproducing.
- `scripts/09_figures_manuscript.R` - the four manuscript figures as submission
  files (TIFF 1200 dpi, EPS, 174 mm wide, no caption inside the image).
- `docs/SUBGROUP_RULE.md` - the eleven-department rule, which existed nowhere in
  version 1.0.0.
- `docs/METHODS_GEOSPATIAL.md` - geospatial methods in full.
- `.gitattributes` - declares LF line endings for all text (REP-001).
- `13_quasipoisson_models.csv` now reports 95 % confidence intervals, the dispersion
  parameter φ, and residual degrees of freedom.
- `input_checksums_local_run.csv` now seals four inputs instead of two, and records
  the line ending plus an md5 computed over LF-normalised content.

### Changed

- Quality control expanded from 31 to **65 checks**, and sealed indicators from 26
  to **51**: now including φ for both models, θ for both negative-binomial fits,
  Moran's I for the outcome and for the residuals, the two subgroup contrasts, and
  the twelve terminal assertions.
- Quality control now **fails if any table in `output/tables/` is not written by any
  script**. In August, nine tables had no producing script; two of them were
  manuscript tables and one was an input to two other scripts.
- The lowest altitude stratum is relabelled from `0-500` to **`lowland (<500 m)`**
  (REP-009). The figures are unchanged; the label was misleading. The stratum is
  dominated by the Amazon lowlands, not by the coast: Loreto, Ucayali and Madre de
  Dios contribute 530,393 of its 608,166 km² (87 %).
- Multiple-victim events are now computed on the **geographic** cohort, consistent
  with the models, instead of the national one (REP-003). No numerical effect.
- The one-death-per-district-date rule is now **declared** in the scenario label and
  in a comment (REP-005).
- Fossil columns `N`, `py`, `tasa`, `letalidad` in
  `data/processed/rayo_densidad_distrito.csv` are prefixed `legacy_` (REP-002). No
  script ever read them; they were mistakable for study figures.
- `metadata/data_sources.csv` records the SINADEF download date as **2025-12-01**
  with its evidentiary basis, and the current access status of the source (below).
- Districts discarded for lacking a denominator are now **announced**, and the
  number of deaths falling in them is counted and warned about if non-zero
  (REP-007). It is zero.

### Fixed - public export could ship the district-date line list (REP-016)

`output/tables/10_multiple_victim_events.csv` is the **district-date line list** of
the 24 multiple-victim events: one row per event, with UBIGEO, exact date and death
count.

The v1.0.0 export filter decided what entered the public package by inspecting
**column names only**:

    unsafe_pattern <- "ID_PERSONA|textos_causales|codigos_cie|case_level|individual"

That header is `analysis_ubigeo, analysis_date, N`. **None of those three names
matches the pattern**, so the filter judged the file safe and copied it into the
release.

The pattern looks for marks of *individual-level* data. The risk here is
*event-level*: a district-date pair with two or three deaths is quasi-identifying
without containing any personal field. In a rural district of a few thousand
people, the exact date of a multi-fatality event is enough to locate the individuals
through local press, municipal records or the civil registry. A filter built on
column names only catches what it already knew how to name.

**Scope.** The **published v1.0.0 Zenodo archive is not affected** - verified file
by file, it does not contain the table. The GitHub repository is not affected: the
file is in `.gitignore` and was never committed. But `02_run_analysis.R` regenerates
it on every run, so **any independent reproduction was affected**: cloning the
repository and running `run_all.R` - exactly what the repository asks a replicator
to do - produced an "aggregate public release" with the line list inside. It
happened locally on 2026-08-25.

The published deposit was protected by accident, not by design: it was built from a
clean clone where the gitignored file did not yet exist on disk. A reproducibility
deposit whose privacy guarantee depends on nobody reproducing it has no guarantee.

**Fixed** with three independent layers in `05_export_public_release.R`:

1. **`DENY_BY_NAME`** - explicit filename exclusion. A rule, not a heuristic: it
   does not depend on what the columns happen to be called.
2. **Structural exclusion** - any table whose header contains a date column is
   dropped. The public package publishes aggregates; a row-level date means the
   table is not one. This layer would have caught the file even if nobody had
   listed it.
3. **Post-condition** - after copying, the release directory is re-inspected and
   packaging **aborts** if any denied filename or date column is present. It
   verifies what was written, not what the filter intended to write. This is the
   layer that turns a silent failure into a loud one.

Exclusions are announced on stdout. The release goes from 41 to **40 files**.

**The line list cannot be reconstructed from what remains.** No table in the release
carries district and time together; the only genuinely temporal table is
`07_monthly_distribution.csv`, which is national. The only ISO date anywhere in the
archive is the R release date in `session-info.txt`. The strongest possible
inference - that one 3-victim event occurred above 3,500 m - is not attributable:
21 districts above 3,500 m have exactly 3 deaths, and a district total of three is
equally consistent with one triple event or three unrelated deaths.

### Known behaviour - not a defect

**Fifteen rows of `11_district_rates_complete.csv` differ in the last significant
digit of `credible_upper` between machines.** Example: `5.42319080316377` against
`5.42319080316378` for district 020105.

Cause: `credible_upper` is `qgamma(0.975, post_a, post_b)`, and `qgamma` is
evaluated by iterative approximation in the platform's C library. Its final ulp
depends on the compiler, the libm build, and the FPU rounding path — not on the
data. The affected rows are those where the iteration lands on a rounding boundary.

Consequences: none. The difference is of order 1e-14 relative, it is confined to a
credible-interval bound that no published figure reports, it does not alter the
ordering of `12_highest_risk_districts.csv`, and no sealed indicator depends on it.
It was documented during the August reproduction run as not constituting a
reproduction failure.

**A replicator who sees these fifteen rows change has not made a mistake and does
not need to investigate.** If a *different* set of rows changes, or if any column
other than `credible_upper` moves, that is worth reporting.

---

## [1.0.0] - 2026-08-02

Initial public reproducible release.

- Validated cohort: 593 national deaths, 591 geographic, 510 above 3,500 m.
- Mortality above 3,500 m: 13.02 per million person-years.
- Rate ratio above 3,500 m versus the rest of Peru: 35.7.
- Reproducibility QC: 31 checks, 0 WARN, 0 FAIL.
- Archived at Zenodo: software `10.5281/zenodo.21764486`, aggregate data
  `10.5281/zenodo.21764559`.
