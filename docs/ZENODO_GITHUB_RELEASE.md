# GitHub and Zenodo release procedure

## A. Prepare the GitHub repository

1. Create a private GitHub repository.
2. Upload the contents of this folder, not the folder containing the old exploratory scripts.
3. Confirm that `data/restricted/` and `data/derived/private/` are not tracked.
4. Complete author and repository metadata.
5. Run the complete pipeline and all QC checks.
6. Generate `CITATION.cff`, `.zenodo.json`, `renv.lock`, and `session-info.txt`.
7. Review the repository and then make it public.

## B. Connect Zenodo

1. Sign in to Zenodo and link the GitHub account.
2. Enable this repository in Zenodo's GitHub integration.
3. Create a GitHub release tagged `v1.0.0`.
4. Wait for Zenodo to archive the release and mint the version-specific DOI.
5. Add the DOI to the manuscript's code-availability statement.
6. Add the DOI to `metadata/repository_metadata.csv`, regenerate `CITATION.cff`, and create a small metadata update or subsequent release when appropriate.

## C. Version discipline

- `v1.0.0`: exact code and aggregate outputs submitted with the article.
- `v1.0.1`: minor corrections that do not change results.
- `v1.1.0`: additional analyses or figures.
- `v2.0.0`: materially changed data or methods.

A published Zenodo file set is immutable. Corrections to files require a new version, preserving the previous version for reproducibility.
