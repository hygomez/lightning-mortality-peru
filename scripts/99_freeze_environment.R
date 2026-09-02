# =============================================================================
# 99_freeze_environment.R  -- Seal the environment (session-info.txt + renv.lock)
#
# The v1.0.0 version of this script carried a HARDCODED package list:
#
#   packages <- c("data.table", "ggplot2", "sf", "terra", "jsonlite", "renv")
#
# That list went stale as scripts were added. It omitted zip, spdep, sandwich and
# MASS, and it did not fail when renv could not seal a package: it printed a
# warning and exited 0. The result was a lockfile that looked valid and could not
# restore an environment able to run the pipeline.
#
# Dependencies are now DERIVED from the ensure_packages() declarations of every
# script in the repository, so the lockfile cannot drift from the code again, and
# the script FAILS when any declared dependency cannot be sealed.
# =============================================================================

options(stringsAsFactors = FALSE, warn = 1)
source("R/functions.R")
ROOT <- repo_root(); setwd(ROOT)

# --- 1. Derive the real dependency set ---------------------------------------
r_files <- list.files(c("scripts", "R", "tests", "config"), pattern = "\\.R$",
                      full.names = TRUE, recursive = TRUE)
lines <- unlist(lapply(r_files, readLines, warn = FALSE))
# Comment lines are stripped before scanning. Without this the scan picks up the
# ensure_packages("x") example written in this very file's own header and tries to
# seal packages named x and y -- which is how this check first failed.
lines <- lines[!grepl("^\\s*#", lines)]
lines <- sub("#.*$", "", lines)
code <- paste(lines, collapse = "\n")

# Every ensure_packages() call, whether ensure_packages("x") or ensure_packages(c("x","y")).
calls <- regmatches(code, gregexpr("ensure_packages\\s*\\((?:[^()]|\\([^()]*\\))*\\)", code, perl = TRUE))[[1]]
declared <- unique(unlist(regmatches(calls, gregexpr('"[A-Za-z0-9.]+"', calls))))
declared <- gsub('"', '', declared)

# renv itself is needed to build the lockfile, and is therefore part of the
# environment a replicator must have, even though no script declares it.
declared <- sort(unique(c(declared, "renv")))
cat("Dependencies declared across the repository:\n  ", paste(declared, collapse = ", "), "\n", sep = "")

# --- 2. Refuse to seal an environment that is not complete --------------------
if (!requireNamespace("renv", quietly = TRUE))
  stop("Install package 'renv', then rerun this script to create renv.lock.", call. = FALSE)

installed <- vapply(declared, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))
if (any(!installed)) {
  stop("Cannot seal the environment. These declared dependencies are not installed: ",
       paste(declared[!installed], collapse = ", "),
       ". Run scripts/00_install_packages.R first. A lockfile that omits a declared ",
       "dependency restores an environment that cannot run the pipeline.", call. = FALSE)
}

writeLines(capture.output(sessionInfo()), "session-info.txt", useBytes = TRUE)
renv::snapshot(packages = declared, prompt = FALSE)

# --- 3. Verify what was actually written, not what was requested --------------
if (!file.exists("renv.lock")) stop("renv.lock was not created.", call. = FALSE)
locked <- names(jsonlite::fromJSON("renv.lock")$Packages)
missing_from_lock <- setdiff(declared, locked)
if (length(missing_from_lock))
  stop("renv.lock is incomplete. Declared but not sealed: ",
       paste(missing_from_lock, collapse = ", "), call. = FALSE)

cat(sprintf("Sealed %d declared dependencies in renv.lock (%d packages including transitive), plus session-info.txt\n",
            length(declared), length(locked)))
