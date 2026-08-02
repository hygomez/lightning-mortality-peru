# Optional reconstruction of mean district elevation once the exact DEM is documented.
options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages(c("data.table", "terra", "sf"))
suppressPackageStartupMessages({library(data.table); library(terra); library(sf)})

dem_file <- "data/raw/elevation/dem.tif"
if (!file.exists(dem_file)) stop("Place the exact documented DEM at: ", dem_file, call. = FALSE)
if (!file.exists(PATHS$districts_gpkg)) stop("District boundaries missing: ", PATHS$districts_gpkg, call. = FALSE)

dem <- rast(dem_file)
dis <- st_read(PATHS$districts_gpkg, quiet = TRUE)
ubi_col <- safe_col(dis, c("UBIGEO", "ubigeo", "IDDIST", "iddist", "CODIGO_DIS"), TRUE)
name_col <- safe_col(dis, c("DISTRITO", "NOMBDIST", "nombdist"))
prov_col <- safe_col(dis, c("PROVINCIA", "NOMBPROV", "nombprov"))
dep_col <- safe_col(dis, c("DEPARTAMEN", "NOMBDEP", "nombdep"))
dis <- st_transform(dis, crs(dem))
elev <- terra::extract(dem, vect(dis), fun = mean, na.rm = TRUE, ID = FALSE)[[1]]
cent <- st_coordinates(st_transform(st_centroid(dis), 4326))
out <- data.table(
  UBIGEO = substr(as.character(dis[[ubi_col]]), 1, 6),
  DISTRITO = if (!is.na(name_col)) as.character(dis[[name_col]]) else NA_character_,
  PROVINCIA = if (!is.na(prov_col)) as.character(dis[[prov_col]]) else NA_character_,
  DEPARTAMEN = if (!is.na(dep_col)) as.character(dis[[dep_col]]) else NA_character_,
  altitud = elev, lon = cent[,1], lat = cent[,2]
)
write_csv_utf8(out, "data/processed/distritos_altitud_regenerated.csv")
cat("Regenerated mean district elevation. Compare it with the validated reference before replacing it.\n")
