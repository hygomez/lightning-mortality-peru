# Geospatial methods

Companion to the manuscript's Methods section. The full working document, with all
diagnostic tables, is kept in Spanish as `METHODS_GEOSPATIAL_ES.md`; this file is
the English reference for the decisions that affect published figures.

---

## 1. Pixel-to-polygon assignment of flash density

The LIS/OTD climatology is a 0.1-degree grid of annual mean total flash rate.
District flash density is the mean of the grid cells assigned to the district
polygon, using **cell centre inside polygon** semantics.

Three candidate semantics were compared on all 1,891 districts:

| Semantics | Agreement with the published values |
|---|---|
| Cell centre inside polygon | **100 %** |
| Any intersection with the polygon | 98.08 % |
| Area-weighted overlap | 98.08 % |

The published pipeline uses centre-in-polygon. This is stated because the three
give materially different values for small districts, and the choice was previously
implicit.

**Area-weighted aggregation is used whenever districts are combined into strata**:
stratum density is `sum(density x area) / sum(area)`, not the mean of district
densities. For the lowland stratum the two differ by a factor of 2.6 (18.62 against
7.08), because the stratum mixes a few enormous Amazonian districts with many small
coastal ones. All published stratum densities are area-weighted.

## 2. Districts smaller than one grid cell

A district smaller than a 0.1-degree cell (roughly 123 km² at the equator) may
contain no cell centre. These districts take the value of the cell containing their
representative point. They are concentrated in the highlands and on the coast, where
districts are small; they are a minority of area and contribute little to
area-weighted stratum figures.

## 3. The 190 districts with zero recorded density

Three explanations were considered:

- **(c) assignment failure** - **rejected**. The affected districts receive valid
  values under all three assignment semantics; they are not unassigned.
- **(a) genuinely below the detection limit** and **(b) true near-absence of
  lightning** - **both occur, and they are spatially separable.** The zeros are not
  scattered at random: they cluster on the hyper-arid Pacific coast, where near-zero
  flash activity is meteorologically expected, and they appear sporadically
  elsewhere as detection-limit censoring.

The decisive evidence is the grid's own structure: **the smallest non-zero value the
product represents for this period is 0.412787 flashes km⁻² year⁻¹**. Values do not
approach zero continuously; they stop there. That is a detection floor, and zeros
are left-censored observations rather than measured absences.

### Treatment

The main specification imputes censored districts at the detection limit,
`LOD_FLASH_DENSITY = 0.412787` (`config/config.R`).

Version 1.0.0 used an arbitrary floor of 0.01, which places 190 districts 3.7 log
units below anything the instrument could measure and inflated the quasi-Poisson
dispersion of Model 2 from 3.77 to 28.71 - worse than the model without the
covariate. See `CHANGELOG.md` for the full argument.

**Five treatments are reported** (`21_lod_five_specifications.csv`): floor 0.01,
LOD/2, LOD/sqrt(2), LOD, and exclusion of censored districts. The altitude gradient
holds in all five, with every confidence interval excluding 1. The censoring
treatment is therefore not load-bearing for any conclusion.

## 4. Territorial harmonisation

District boundaries and UBIGEO codes change during 2017-2024 as districts are
created or recategorised. Codes were harmonised to the INEI 2025 census boundary
product, which is also the geometry used for mapping and for spatial weights.

**No orphan cases remain**: every validated death with a district code matches a
polygon in the reference boundaries. One code present in the population file has no
counterpart in the boundary file and carries no deaths.

## 5. Population denominators

Source: INEI district population projections, **which begin in 2018**. The analysis
period begins in 2017, so that year is reconstructed as

    P(2017) = P(2018)^2 / P(2019)

that is, by applying each district's 2018-2019 growth ratio backwards one year. It
is the only consecutive-year ratio available at the start of the series.

**No adjustment was made for districts with negative growth.** In 1,039 of 1,892
districts (54.9 %) P(2019) < P(2018), so the procedure yields a 2017 population
*above* the 2018 value, extending a declining trend backwards. This is internally
consistent but amplifies error where the 2018-2019 fall reflects an INEI
methodological revision rather than demographic change. No reconstructed value was
negative or zero.

**Eighteen districts have no 2017 denominator** because they were first projected
after 2017. They are excluded from district-level analysis, and
`scripts/02_run_analysis.R` now announces this instead of dropping them silently
(REP-007). **They contain zero deaths**, asserted by
`scripts/08_terminal_checks.R`, so the exclusion cannot bias the numerator.

### Quantified impact

Setting 2017 population equal to 2018 - the most extreme alternative - changes the
mortality rate above 3,500 m from **13.0162 to 13.0099** per million person-years, a
change of **0.05 %**. Excluding 2017 entirely *raises* the high-altitude rate ratio
from 35.7 to 39.5. The 2017 denominator supports no conclusion in either direction,
and both figures are asserted in `scripts/08_terminal_checks.R`.

## 6. Spatial weights and inference

Two weighting schemes are reported (`16_moran_i.csv`):

- **Queen contiguity** - the main specification. It depends only on which polygons
  share a boundary, and on no representative point.
- **KNN-8** - built on `st_centroid`, matching the convention in spatial
  econometrics and reproducing the reference Python run exactly.

The choice of representative point is not innocuous: `st_centroid` and
`st_point_on_surface` differ by 2.41 km on average, and 1,206 of 1,891 districts
differ by more than 1 km, which reorders neighbourhoods. Moran's I moves by up to
3.9 % between the two. **This is precisely why the main specification is Queen**,
which is invariant to that choice. Both figures are asserted in
`scripts/08_terminal_checks.R`.

Spatially robust standard errors use a Conley Bartlett kernel
(`17_conley_robust_se.csv`), reported at 50, 100, 200 and 300 km, with sensitivity
at 100, 250 and 500 km in `23_conley_bandwidth_sensitivity.csv`. The coefficient is
identical across bandwidths - only the variance estimator changes.
