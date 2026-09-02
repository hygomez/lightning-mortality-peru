options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT); source("config/config.R")
ensure_packages(c("data.table", "ggplot2", "sf"))
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(sf)})

rates_file <- file.path(PATHS$tables, "11_district_rates_complete.csv")
if (!file.exists(rates_file)) stop("Run scripts/02_run_analysis.R first.", call. = FALSE)
if (!file.exists(PATHS$districts_gpkg)) {
  stop("District boundaries are unavailable; map not generated.", call. = FALSE)
}

rates <- fread(rates_file, colClasses = list(character = "UBIGEO"))
map <- st_read(PATHS$districts_gpkg, quiet = TRUE)
ubi_col <- safe_col(map, c("UBIGEO", "ubigeo", "IDDIST", "iddist", "CODIGO_DIS"), TRUE)
map$UBIGEO_JOIN <- substr(as.character(map[[ubi_col]]), 1, 6)
rates[, UBIGEO_JOIN := substr(UBIGEO, 1, 6)]
map <- merge(map, rates[, .(UBIGEO_JOIN, posterior_rate, deaths, altitud, probability_above_84)],
             by = "UBIGEO_JOIN", all.x = TRUE)

p <- ggplot(map) +
  geom_sf(aes(fill = posterior_rate), color = "grey80", linewidth = 0.05) +
  scale_fill_viridis_c(option = "inferno", direction = -1, trans = "sqrt",
                       name = "Posterior rate\n(per million)", na.value = "grey95") +
  labs(title = "Lightning mortality by district of residence",
       subtitle = "Empirical-Bayes posterior rates, Peru, 2017-2024",
       caption = "District rates are based on residence and should not be interpreted as exact strike locations.") +
  theme_void(base_size = 10) + theme(legend.position = "right")

# v2.0.0: both versions are always emitted. The 600 dpi LZW-compressed TIFF is the
# one the deposit requires; the PNG is for quick inspection.
ggsave(file.path(PATHS$figures, "Figure_5_district_posterior_rates.png"), p,
       width = 7, height = 8.6, dpi = 300)
ggsave(file.path(PATHS$figures, "Figure_5_district_posterior_rates.tiff"), p,
       width = 7, height = 8.6, dpi = 600, compression = "lzw")
cat(sprintf("Figure 5: %d districts, %d without a posterior rate.\n",
            nrow(map), sum(is.na(map$posterior_rate))))
cat("District map generated.\n")
