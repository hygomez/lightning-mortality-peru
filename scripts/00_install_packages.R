packages <- c("data.table", "ggplot2", "sf", "terra", "jsonlite", "renv", "zip")
missing <- packages[!vapply(packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing)) install.packages(missing, dependencies = TRUE)
cat("Required R packages are available.\n")
