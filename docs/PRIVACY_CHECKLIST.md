# Privacy and disclosure checklist

Before changing the GitHub repository from private to public:

- [ ] `data/restricted/` is absent from `git status`.
- [ ] No real-data or release file contains `ID_PERSONA`; only the clearly labeled synthetic test file may use a fictional identifier column.
- [ ] No file contains full cause-of-death text chains.
- [ ] No adjudication spreadsheet with individual rows is present.
- [ ] No local Windows paths, usernames, tokens, or credentials are present.
- [ ] Public tables are aggregate district-, stratum-, month-, sex-, or age-group summaries.
- [ ] The release ZIP has been opened and inspected manually.
- [ ] `output/qc/qc_summary.txt` contains zero `FAIL` results.

---

## v2.0.0 privacy review (2026-09-01)

Evidence for each check is reproducible from the commands in this section.

| # | Check | Result |
|---|---|---|
| P1 | District-date line list excluded from the public release | **Fixed defect** (below) |
| P2 | Only aggregate event tables published | PASS - `24_`, `25_` carry no district and no date |
| P3 | No credentials anywhere, including git history | PASS - 0 matches in all 116 objects |
| P4 | `data/restricted/**` and `data/derived/private/**` excluded | PASS - only `.gitkeep` tracked |
| P5 | `15_district_spatial_panel.csv` adds no new disclosure | PASS - death counts identical to the already-public `11_` |
| P6 | Full scan of the release archive | PASS - only ISO date is the R release date in `session-info.txt` |
| P7 | Terminal-check outputs are aggregates | PASS - `26_`, `27_` are macroregion and assertion summaries |

### P1 - defect found and corrected

`10_multiple_victim_events.csv` is a district-date line list of the 24
multiple-victim events. A district-date pair with two or three deaths is
**quasi-identifying**: in a rural district the exact date of a multi-fatality event
is enough to locate the individuals through local press or civil registry.

The v1.0.0 export filter tested only **column names** against
`ID_PERSONA|textos_causales|codigos_cie|case_level|individual`. This file's header
is `analysis_ubigeo, analysis_date, N` - it matched nothing, so it passed the filter
and was copied into the public release.

The published v1.0.0 Zenodo archive does **not** contain it, because it was built
from a clean clone where the file - which is in `.gitignore` - did not exist. But
`02_run_analysis.R` regenerates it on every run, so **anyone cloning the repository
and running `run_all.R` produced a release containing the line list**. This happened
locally on 2026-08-25: see `release/v1.0.0/aggregate-data/`.

Corrected in `05_export_public_release.R` with three independent layers:

1. **`DENY_BY_NAME`** - explicit filename exclusion, not a heuristic.
2. **Structural rule** - any table whose header contains a date column is excluded,
   because the public release publishes aggregates only.
3. **Post-condition** - after copying, the release directory is re-inspected and the
   packaging **aborts** if any denied filename or any date column is present. The
   check verifies what was actually written, not what the filter intended.

Exclusions are announced on stdout rather than applied silently.

### Reconstruction test

No table in the release carries district and time together. The only genuine
temporal table is `07_monthly_distribution.csv`, which is **national** monthly
counts with no district. District tables (`11_`, `12_`, `15_`) give eight-year
totals with no time breakdown.

The strongest available inference is that one 3-victim event occurred above 3,500 m
(`25_events_by_altitude.csv`). It cannot be attributed: **21 districts above
3,500 m have exactly 3 deaths** and 55 have three or more, and a district total of
three is equally consistent with one triple event or three unrelated deaths. No
date information exists at district resolution anywhere in the release.

**The line list cannot be reconstructed, by any single table or combination.**
