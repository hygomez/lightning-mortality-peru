# Optional reconstruction of district lightning density from the NASA LIS/OTD HDF.
# This script is not needed when the validated district-density CSV has been imported.
options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages(c("data.table", "terra", "sf"))
suppressPackageStartupMessages({library(data.table); library(terra); library(sf)})

hdf <- "data/raw/lightning/COMB_OTD_TRMM_ISS_AnnualMean.hdf"
if (!file.exists(hdf)) stop("Place the NASA HDF at: ", hdf, call. = FALSE)
if (!file.exists(PATHS$districts_gpkg)) stop("District boundaries missing: ", PATHS$districts_gpkg, call. = FALSE)

fr <- rast(hdf)["flashrate"]
ext(fr) <- c(-180, 180, -90, 90); crs(fr) <- "EPSG:4326"
fr_flip <- flip(fr, direction = "vertical")
v1 <- terra::extract(fr, data.frame(x = -71.5, y = 9.8))[1,2]
v2 <- terra::extract(fr_flip, data.frame(x = -71.5, y = 9.8))[1,2]
if (is.na(v1)) v1 <- -1; if (is.na(v2)) v2 <- -1
if (v2 > v1) fr <- fr_flip
if (max(v1, v2) < 50) stop("Lightning raster orientation validation failed at Lake Maracaibo.", call. = FALSE)

dis <- st_transform(st_read(PATHS$districts_gpkg, quiet = TRUE), 4326)
ubi_col <- safe_col(dis, c("UBIGEO", "ubigeo", "IDDIST", "iddist", "CODIGO_DIS"), TRUE)
dis$UBIGEO <- substr(as.character(dis[[ubi_col]]), 1, 6)
pe <- crop(fr, ext(-82, -68, -19, 0))
dens <- terra::extract(pe, vect(dis), fun = mean, na.rm = TRUE, ID = FALSE)
areas <- as.numeric(st_area(st_transform(dis, "EPSG:32718"))) / 1e6
out <- data.table(UBIGEO = dis$UBIGEO, area_km2 = areas, densidad = dens[[1]])
out[, descargas_anio := densidad * area_km2]
write_csv_utf8(out, "data/processed/rayo_densidad_distrito_regenerated.csv")
cat("Regenerated district lightning density. Compare it with the validated reference before replacing it.\n")
