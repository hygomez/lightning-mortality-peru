# Lightning mortality at high altitude in the Peruvian Andes

[![Software DOI](https://zenodo.org/badge/1320835899.svg)](https://doi.org/10.5281/zenodo.21764485)

**Software (concept DOI, always resolves to the latest version):** https://doi.org/10.5281/zenodo.21764485
**Aggregate dataset (concept DOI, always resolves to the latest version):** https://doi.org/10.5281/zenodo.21764558

Current archived release: **v2.0.0**, https://doi.org/10.5281/zenodo.22258022 (2026-09-02).
Cite the concept DOI above unless a statement must refer to this specific version.
**GitHub:** https://github.com/hygomez/lightning-mortality-peru

**Public reproducible repository, version 1.0.0**

Associated study: *Lightning mortality at high altitude exceeds that of Peru's Amazon lowlands despite lower flash density: a nationwide study, 2017-2024*

## Scope

This repository contains the reproducible analytical code, metadata, quality-control reports, figures, and non-identifying aggregate outputs supporting a nationwide geospatial study of lightning mortality in Peru during 2017-2024.

It does **not** contain individual-level SINADEF mortality records,
personal identifiers, free-text cause-of-death chains, or adjudication line lists.

## Validated analytical results

- 593 nationally validated lightning-related deaths.
- 591 deaths with district and altitude information.
- 510 deaths above 3,500 m.
- Mortality rate above 3,500 m: 13.02 per million person-years (95% CI 11.91-14.20).
- Rate ratio above 3,500 m versus the rest of Peru: 35.7.
- Rate ratio above 3,500 m versus the lowland stratum (<500 m): 87.3.
- Rate ratio above 3,500 m versus the **Amazon lowlands**, the region of Peru
  receiving the most lightning: **13.99** (8.37-23.37), against a flash density only
  **0.38x** as high, so deaths per million flashes are **199x** greater.
- District-level quasi-Poisson models, per doubling: altitude **MRR 4.12**, flash
  density **MRR 2.01** (detection-limit specification; see `CHANGELOG.md`).
- Reproducibility QC: **65 PASS, 0 WARN, 0 FAIL**; 51 sealed indicators.

## Repository contents

- `scripts/`: short auditable analysis pipeline.
- `R/`: shared functions.
- `config/`: analysis period, paths, and expected values.
- `data/example/`: synthetic example data.
- `data/processed/`: non-identifying population, altitude, and flash-density inputs.
- `data/derived/public/`: public derived materials, when available.
- `output/tables/`: aggregate analytical tables.
- `output/figures/`: publication figures.
- `output/qc/`: quality-control report.
- `metadata/`: authorship, sources, checksums, and release metadata.
- `docs/`: reproducibility, privacy, availability, and submission documentation,
  including `SUBGROUP_RULE.md` and `METHODS_GEOSPATIAL.md`.
- `CHANGELOG.md`: what changed in v2.0.0 and why, including one documented
  known behaviour that is not a defect.

## Reproduction

Install the required packages:

```r
source("scripts/00_install_packages.R")
```

The public aggregate outputs can be inspected directly. Full reconstruction of the validated cohort requires an authorized local copy of the original administrative mortality source. Such microdata are not redistributed.

Researchers with authorized source data may set:

```r
Sys.setenv(SOURCE_PROJECT_ROOT = "D:/path/to/authorized/local/project")
source("scripts/00_import_from_existing_project.R")
source("scripts/run_all.R")
```

## Data protection

Individual-level SINADEF records are excluded because they contain sensitive mortality information. The public release contains aggregate, non-identifying results and the code needed to reproduce them when authorized source data are available.

## Authors

1. **Beatriz Flores Huanca** — ORCID: 0000-0002-7914-9662
2. **Hugo Yosef Gomez Quispe** — ORCID: 0000-0002-8627-412X — corresponding author
3. **Robert Antonio Romero Flores** — ORCID: 0000-0002-6144-9309
4. **Edgar Eloy Carpio Vargas** — ORCID: 0000-0001-6457-4597
5. **Fredy Heric Villasante Saravia** — ORCID: 0000-0002-8859-9008
6. **Teresa Paola Alvarez Rozas** — ORCID: 0000-0002-3214-4506
7. **Doris Charaja Jallo** — ORCID: 0000-0001-5221-2599
8. **Mabel Marialice Calsin Apaza** — ORCID: 0000-0002-0637-8499

**Lead author:** Beatriz Flores Huanca.

**Corresponding author:** Hugo Yosef Gomez Quispe, Professional School of Systems Engineering, National University of the Altiplano, Puno, Peru; `hygomez@unap.edu.pe`; ORCID: 0000-0002-8627-412X.

## Funding

This research received no specific grant from any funding agency in the public, commercial, or not-for-profit sectors. The costs associated with the study were covered by the authors.

## Competing interests

The authors declare no competing interests.

## Ethics

This study did not involve any new collection of data from human participants. It is a secondary analysis of anonymized administrative mortality records released by the Peruvian Ministry of Health through the National Open Data Platform and openly downloadable at the time of access. No recruitment, contact, intervention or interaction with human participants took place, and no attempt was made to re-identify any individual. The research ethics procedure of the National University of the Altiplano issues exemption determinations prospectively, for studies that have not yet begun, and therefore provides no mechanism applicable to the retrospective secondary analysis of already-public data reported here. No ethical approval was therefore required or sought.

## Availability

The analytical code is maintained on GitHub at https://github.com/hygomez/lightning-mortality-peru and permanently archived in Zenodo at https://doi.org/10.5281/zenodo.21764485. Aggregate, non-identifying data and reproducibility materials are archived in Zenodo at https://doi.org/10.5281/zenodo.21764558. Individual-level SINADEF mortality records, personal identifiers, free-text cause-of-death chains, and private adjudication files are not redistributed.

## Licenses

- Code: MIT License.
- Original documentation and derived aggregate materials: CC BY 4.0 where legally permitted.
- Original source data remain subject to provider licenses and access conditions.

## Citation

Software: Flores Huanca, B., Gomez Quispe, H. Y., Romero Flores, R. A., et al. (2026). *Reproducible analysis code for lightning mortality at high altitude in the Peruvian Andes, 2017-2024* (Version 1.0.0). Zenodo. https://doi.org/10.5281/zenodo.21764485

Dataset: Flores Huanca, B., Gomez Quispe, H. Y., Romero Flores, R. A., et al. (2026). *Aggregated data supporting the study of lightning mortality in the Peruvian Andes, 2017-2024* (Version 1.0.0). Zenodo. https://doi.org/10.5281/zenodo.21764558
