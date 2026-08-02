# Output codebook

## Main result tables

| File | Unit | Main fields |
|---|---|---|
| `01_mortality_by_altitude.csv` | Altitude stratum | deaths, person-years, rate, exact Poisson CI |
| `02_rate_ratios.csv` | Contrast | rate ratio and 95% CI |
| `03_density_and_mortality_to_flashes.csv` | Altitude stratum | area-weighted flash density, mortality, deaths per million climatological flashes |
| `04_negative_control_electrocution.csv` | Altitude stratum | lightning and non-atmospheric electrocution rates |
| `05_sex.csv` | Sex | death count |
| `06_age_by_sex.csv` | Age group × sex | death count |
| `07_monthly_distribution.csv` | Month | death count |
| `08_departments.csv` | Department | death count |
| `09_national_profile.csv` | Indicator | demographic and circumstance summary |
| `10_multiple_victim_events.csv` | District-date event | number of deaths |
| `11_district_rates_complete.csv` | District | crude and empirical-Bayes posterior rates |
| `12_highest_risk_districts.csv` | District | highest posterior rates among high-altitude districts with at least three deaths |
| `13_quasipoisson_models.csv` | Model term | beta, standard error, p value, rate ratio per doubling |
| `14_sensitivity_analysis.csv` | Scenario | high-altitude rate and rate ratio |
| `results_summary.csv` | Indicator | machine-readable values checked against the manuscript |

## Key definitions

- `person_years`: sum of annual district populations for 2017-2024.
- `rate_per_million`: deaths per 1,000,000 person-years.
- `area_weighted_density`: total climatological flashes divided by total district area within an altitude stratum.
- `mortality_per_million_flashes`: annualized deaths per 1,000,000 climatological flashes. This is not clinical lethality.
- `posterior_rate`: empirical-Bayes gamma-Poisson district mortality estimate.
- `probability_above_84`: posterior probability that the district rate exceeds 84 deaths per million; this is a literature comparison, not a clinical threshold.
