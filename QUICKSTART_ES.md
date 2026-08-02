# Inicio rápido en español

Este repositorio sustituye los más de 50 scripts exploratorios por una canalización final y auditable.

## Paso 1. Importar los insumos del proyecto actual

Abra RStudio en la carpeta del repositorio y ejecute:

```r
source("scripts/00_import_from_existing_project.R")
```

El script buscará por defecto:

```text
D:/path/to/authorized/local/project
```

## Paso 2. Ejecutar todo el análisis

```r
source("scripts/run_all.R")
```

## Paso 3. Revisar el control final

Abra:

```text
output/qc/qc_summary.txt
```

Todos los controles numéricos deben aparecer como `PASS`.

## Paso 4. Completar autores y metadatos

Complete:

```text
metadata/authors.csv
metadata/repository_metadata.csv
metadata/data_sources.csv
```

Luego ejecute:

```r
source("scripts/90_finalize_metadata.R")
source("scripts/99_freeze_environment.R")
```

## Paso 5. Publicar

Siga `docs/ZENODO_GITHUB_RELEASE.md`. No suba a GitHub la carpeta `data/restricted/` ni archivos con registros individuales de mortalidad.
