# Data availability and disclosure strategy

## What is public

The repository may publicly contain:

- analysis and figure-generation code;
- the case-definition rules;
- synthetic test data;
- district-level counts, denominators, rates, posterior estimates, and model summaries;
- source metadata and checksums;
- figures and quality-control reports.

## What is not redistributed

The repository must not publicly contain:

- individual SINADEF records;
- `ID_PERSONA` or other direct identifiers;
- full free-text cause-of-death chains;
- adjudication spreadsheets containing individual records;
- local paths or credentials.

The individual-level mortality input remains under `data/restricted/` and is ignored by Git.

## Recommended manuscript statement in English

> The mortality data supporting this study were derived from publicly available records of Peru's National Death Information System (SINADEF). To minimize unnecessary redistribution of potentially sensitive individual-level records, the source microdata are not included in this repository. Reproduction instructions, the prespecified case-definition code, non-identifying aggregate data, statistical analysis scripts, and figure-generation code are available at [GITHUB URL] and archived at [ZENODO DOI]. The population, administrative-boundary, elevation, and lightning-climatology sources and access dates are documented in the repository.

## Recommended software availability statement

> Source code is available at [GITHUB URL]. The exact version underlying this article is permanently archived at [ZENODO DOI].

Replace all bracketed fields before submission.
