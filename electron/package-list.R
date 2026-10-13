args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Expected a package inventory output path.")
}

roots <- c(
  "shiny",
  "bslib",
  "markdown",
  "facereaderconverter",
  "zip",
  "callr",
  "later",
  "readr",
  "readxl"
)
installed <- installed.packages()
missing <- setdiff(roots, rownames(installed))
if (length(missing)) {
  stop("Missing R packages: ", paste(missing, collapse = ", "))
}

dependencies <- tools::package_dependencies(
  roots,
  db = installed,
  which = c("Depends", "Imports", "LinkingTo"),
  recursive = TRUE
)
names <- unique(c(roots, unlist(dependencies, use.names = FALSE)))
missing <- setdiff(names, rownames(installed))
if (length(missing)) {
  stop("Missing dependencies: ", paste(missing, collapse = ", "))
}
external <- names[is.na(installed[names, "Priority"])]
locations <- file.path(installed[external, "LibPath"], external)
writeLines(
  c(R.home(), paste(external, locations, sep = "\t")),
  con = args[[1L]]
)
