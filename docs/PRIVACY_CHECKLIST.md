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
