# Reproduction guide for editors and reviewers

The individual mortality microdata are not redistributed. Reviewers with lawful access to the standardized local inputs can reproduce all results with:

```r
source("scripts/run_all.R")
```

The expected numerical results are in `results/reference/expected_results.csv`. The script stops if the validated cohort counts or any principal published result differ beyond the stated tolerance. Public aggregate outputs and figures are generated under `release/`.

The synthetic test in `tests/test_case_definition.R` demonstrates the inclusion of textual and ICD-defined lightning cases and the exclusion of radiological and cardiac-context false positives without using real records.
