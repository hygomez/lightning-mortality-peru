# The lowland subgroup rule

## Why the rule exists

The `lowland (<500 m)` altitude stratum averages two regions that are opposites in
the quantity the study is about. The Amazon lowlands receive **more lightning than
anywhere else in Peru** (20.65 flashes km⁻² year⁻¹, area-weighted). The Pacific
coast receives **the least** (0.72). Reporting them as one stratum produces a
number that describes neither.

This matters for the central claim. That high-altitude mortality exceeds the
mortality of a region with little lightning would not be surprising. The finding is
that it exceeds the mortality of the region that receives **the most** lightning,
and that is only visible once the stratum is split.

**In version 1.0.0 this rule existed nowhere in the repository.** It had been
applied through commands typed at a console. It is reproduced here in
`scripts/07_sensitivity_specifications.R` and declared in `config/config.R`.

## The rule

A district in the `lowland (<500 m)` stratum is classified as **Pacific coast** if
the first two digits of its UBIGEO correspond to a department with a Pacific
watershed:

| Code | Department | Code | Department |
|---|---|---|---|
| 02 | Ancash | 15 | Lima |
| 04 | Arequipa | 18 | Moquegua |
| 07 | Callao | 20 | Piura |
| 11 | Ica | 23 | Tacna |
| 13 | La Libertad | 24 | Tumbes |
| 14 | Lambayeque | | |

Otherwise it is classified as **Amazon lowland**. The rule is applied **by
exclusion**: the Amazon subgroup is the complement, so no district can be left
unclassified. `scripts/07_sensitivity_specifications.R` asserts this.

## What the rule produces

309 lowland districts split into 201 Pacific coast and 108 Amazon lowland
(`18_lowland_subgroup_rule.csv`):

| Subgroup | Departments (districts) | Total |
|---|---|---|
| Pacific coast | Ancash 8, Arequipa 5, Callao 7, Ica 18, La Libertad 23, Lambayeque 33, Lima 50, Moquegua 1, Piura 41, Tacna 2, Tumbes 13 | **201** |
| Amazon lowland | Huánuco 4, Loreto 52, Madre de Dios 10, San Martín 26, Ucayali 16 | **108** |

Resulting subgroup figures (`19_lowland_subgroups_ci.csv`,
`28_subgroup_contrasts.csv`):

| Subgroup | Districts | Deaths | Rate (95 % CI) | Flash density | MFR |
|---|---|---|---|---|---|
| Amazon lowland | 108 | 15 | 0.93 (0.52-1.53) | **20.65** | 0.166 |
| Pacific coast | 201 | 4 | 0.036 (0.010-0.092) | **0.72** | 11.37 |

And the contrasts against the high-Andean stratum:

| Contrast | Rate ratio (95 % CI) | Flash-density ratio | MFR ratio |
|---|---|---|---|
| >3,500 m vs Amazon lowland | **13.99** (8.37-23.37) | **0.38×** | **199×** |
| >3,500 m vs Pacific coast | 362.06 (135.37-968.41) | 11.00× | 2.91× |

The first row is the comparison of interest: mortality 14 times higher against a
region receiving nearly three times the lightning.

## Limitations of the rule, stated plainly

**The classification is administrative, not ecological.** It uses department of
location as a proxy for watershed. It does not attempt to locate the continental
divide at district resolution, and it does not claim to.

Two consequences a reader should weigh:

1. **Departments straddling the divide are assigned whole.** Ancash, La Libertad
   and Lima have territory on both slopes; every lowland district in them is
   counted as Pacific coast. Below 500 m this is a mild assumption, because the
   sub-500 m territory of those departments is coastal, but it is an assumption.
2. **Huánuco contributes only 4 districts** to the Amazon subgroup and is the
   least clear-cut of the five. Removing it does not change the direction or the
   approximate size of the contrast.

The rule was fixed before the subgroup results were examined, and it is not tuned
to them. Anyone wanting a different boundary can change
`PACIFIC_DEPARTMENTS` in `config/config.R` and re-run
`scripts/07_sensitivity_specifications.R`; every downstream number follows.
