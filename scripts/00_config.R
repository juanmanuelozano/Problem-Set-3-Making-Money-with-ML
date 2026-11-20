# =============================================================================
# 00_config.R - Configuración común: rutas, paleta, tema gráfico y funciones
# Todos los scripts hacen source("scripts/00_config.R") y se corren desde la raíz del repo.
# =============================================================================
if (!requireNamespace("pacman", quietly = TRUE)) install.packages("pacman", repos = "https://cloud.r-project.org")
suppressMessages(pacman::p_load(tidyverse, scales))
options(width = 160, scipen = 99)
set.seed(123)

# ---- Rutas ----
P <- list(
  raw       = "data/raw",
  osm       = "data/external/osm",
  processed = "data/processed",
  models    = "models",
  subs      = "submissions",
  rep_desc  = "reports/01_descriptivas",
  rep_mod   = "reports/02_modelos"
)
walk(c(P, file.path(rep(c(P$rep_desc, P$rep_mod), each = 2), c("figures", "tables"))), dir.create, recursive = TRUE, showWarnings = FALSE)

lee_csv <- function(f) read_csv(f, show_col_types = FALSE, num_threads = 1)  # num_threads=1 evita segfault en este equipo

# ---- Constantes del problema ----
PRECIO_MIN <- 3.0e8   # el precio observado está acotado entre 300 y 1.650 millones
PRECIO_MAX <- 1.65e9

# ---- Paleta (validada con la skill dataviz) y tema ----
c_train <- "#2a78d6"; c_test <- "#eb6834"; c_aqua <- "#1baf7a"; c_ink <- "#0b0b0b"; c_ink2 <- "#52514e"
c_muted <- "#898781"; c_grid <- "#e1e0d9"
seq_blue <- c("#cde2fb", "#86b6ef", "#3987e5", "#256abf", "#184f95", "#0d366b")
cat_pal <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948")
theme_ps <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = c_grid, linewidth = .3),
        plot.title = element_text(face = "bold", color = c_ink), plot.subtitle = element_text(color = c_ink2),
        axis.text = element_text(color = c_muted), axis.title = element_text(color = c_ink2),
        plot.caption = element_text(color = c_muted, hjust = 0), legend.position = "top",
        plot.background = element_rect(fill = "#fcfcfb", color = NA))
theme_set(theme_ps)
fuente <- "Fuente: Properati (train/test), OpenStreetMap. Cálculos propios."

# ---- Funciones auxiliares ----
# Distancia haversine (metros) entre vectores lat1/lon1 y lat2/lon2 -> matriz
hav <- function(lat1, lon1, lat2, lon2) {
  r <- pi / 180; dlat <- outer(lat1, lat2, "-") * r; dlon <- outer(lon1, lon2, "-") * r
  a <- sin(dlat / 2)^2 + outer(cos(lat1 * r), cos(lat2 * r)) * sin(dlon / 2)^2
  a[] <- pmin(1, sqrt(a))
  2 * 6371000 * asin(a)
}
# Distancia (m) de cada punto del conjunto 1 a su vecino más cercano del conjunto 2 (por bloques, para no agotar la memoria)
dist_min <- function(lat1, lon1, lat2, lon2, bloque = 1000) {
  out <- numeric(length(lat1))
  for (ix in split(seq_along(lat1), ceiling(seq_along(lat1) / bloque))) out[ix] <- apply(hav(lat1[ix], lon1[ix], lat2, lon2), 1, min)
  out
}
mae <- function(y, yhat) mean(abs(y - yhat))

# ---- Extracción de números del texto (title + description en minúsculas) ----
# Los rangos válidos se aplican en cada script (02, 03, 02b). Ver docs/guia_variables.md.
PATRONES <- list(
  area    = "(\\d{2,4}(?:[\\.,]\\d+)?)\\s?(?:m2|mts2|mt2|mts|metros cuadrados|metros|mt)\\b",
  banos   = "(\\d)\\s?(?:banos|bano)\\b",
  estrato = "estrato\\s?(\\d)",
  piso    = "(?:piso|nivel)\\s?(\\d{1,2})\\b",
  antig   = "(\\d{1,2})\\s?anos? de (?:construid|antiguedad)",
  antig2  = "antiguedad (?:de )?(\\d{1,2})",
  parq    = "(\\d)\\s?(?:parqueaderos|garajes|parqueadero|garaje)")
num_txt <- function(x, pat) as.numeric(str_replace(str_match(x, pat)[, 2], ",", "."))
recorta <- function(p) pmin(pmax(p, PRECIO_MIN), PRECIO_MAX)
