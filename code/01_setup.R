# =============================================================================
# 01_setup.R - Configuración común: paquetes, rutas, paleta, tema gráfico, funciones y entornos de Python
# Todos los scripts de R empiezan con source(here::here("code", "01_setup.R")). Las rutas salen de here::here(), que
# ubica la raíz del proyecto (la carpeta del .Rproj): los scripts funcionan igual desde RStudio, desde la terminal y
# desde cualquier directorio de trabajo, en Windows y en macOS.
# Es el ÚNICO lugar donde se cargan paquetes: si un script necesita uno nuevo, se agrega aquí.
# =============================================================================

# ---- 1. Paquetes ----
repos <- getOption("repos")
if (is.null(repos) || !"CRAN" %in% names(repos) || repos[["CRAN"]] %in% c("@CRAN@", "")) options(repos = c(CRAN = "https://cloud.r-project.org"))
if (!requireNamespace("pacman", quietly = TRUE)) install.packages("pacman")

# Orden: tidyverse primero y luego el resto, como cargaban antes los scripts (los paquetes de modelación quedan por
# encima en la ruta de búsqueda). Ninguna de las funciones que se enmascaran se usa en el código.
suppressMessages(pacman::p_load(
  tidyverse, scales,                 # manipulación de datos y gráficos
  here, sessioninfo, callr, processx, # rutas, información de la sesión y ejecución de scripts desde 00_main.R
  httr, jsonlite,                    # descargas de OpenStreetMap (Overpass) y Datos Abiertos Bogotá
  sp, stargazer, knitr,              # geometría de polígonos, tablas LaTeX
  Matrix, arrow, irlba,              # matrices dispersas, parquet (texto de Python), PCA truncado
  glmnet, ranger, xgboost, nnet,     # modelos
  RANN,                              # vecinos más cercanos (comparables)
  reticulate                         # puente con Python (entornos virtuales y Keras)
))

# Paquetes opcionales: si no se pueden cargar, los scripts que los necesitan se saltan (00_main.R avisa).
#  - sf: lo usan 03f y 03h (catastro). En algunos equipos Windows el Control de aplicaciones bloquea su DLL.
#  - keras3: lo usan las redes (08c-08q, utils_redes.R); TensorFlow vive en el entorno de Python "tf".
carga_opcional <- function(pkg) {
  if (!nzchar(system.file(package = pkg))) try(install.packages(pkg), silent = TRUE)   # se instala solo si falta
  ok <- tryCatch(suppressMessages(suppressWarnings(require(pkg, character.only = TRUE, quietly = TRUE))),
                 error = function(e) FALSE)
  if (!ok) message("Aviso: no se pudo cargar el paquete opcional '", pkg, "'; se saltan los scripts que lo usan.")
  ok
}
HAY_SF    <- carga_opcional("sf")
HAY_KERAS <- carga_opcional("keras3")

options(width = 160, scipen = 99)
set.seed(123)

# ---- 2. Rutas (todas absolutas, desde la raíz del proyecto) ----
RAIZ <- here::here()
P <- list(
  code      = here("code"),
  raw       = here("data", "raw"),
  external  = here("data", "external"),
  osm       = here("data", "external", "osm"),
  processed = here("data", "processed"),
  models    = here("models"),
  subs      = here("submissions"),
  output    = here("output"),
  fig_desc  = here("output", "figures", "01_descriptivas"),
  tab_desc  = here("output", "tables", "01_descriptivas"),
  fig_mod   = here("output", "figures", "02_modelos"),
  tab_mod   = here("output", "tables", "02_modelos"),
  logs      = here("output", "logs")
)
walk(P, dir.create, recursive = TRUE, showWarnings = FALSE)

lee_csv <- function(f) read_csv(f, show_col_types = FALSE, num_threads = 1)  # num_threads = 1 evita un segfault en Windows

# ---- 3. Constantes del problema ----
PRECIO_MIN <- 3.0e8   # el precio observado está acotado entre 300 y 1.650 millones
PRECIO_MAX <- 1.65e9

# ---- 4. Paleta (validada con la skill dataviz) y tema ----
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

# ---- 5. Funciones auxiliares ----
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

# ---- 6. Extracción de números del texto (title + description en minúsculas) ----
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

# Descarga y descomprime un .zip (Datos Abiertos Bogotá: 03f, 03h) si la carpeta de destino está vacía
descarga_zip <- function(url, destino) {
  if (length(list.files(destino, recursive = TRUE))) return(invisible(destino))
  dir.create(destino, recursive = TRUE, showWarnings = FALSE)
  zip <- tempfile(fileext = ".zip"); on.exit(unlink(zip))
  old <- options(timeout = max(3600, getOption("timeout"))); on.exit(options(old), add = TRUE)
  message("Descargando ", basename(url), " en ", destino, " ...")
  utils::download.file(url, zip, mode = "wb", quiet = TRUE)
  utils::unzip(zip, exdir = destino)
  invisible(destino)
}
# Primer archivo de `carpeta` (en cualquier subcarpeta) cuyo nombre cumple `patron`
busca_archivo <- function(carpeta, patron) {
  f <- list.files(carpeta, pattern = patron, recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  if (!length(f)) stop("No se encontró ", patron, " en ", carpeta)
  f[1]
}

# ---- 7. Entornos de Python ----
# Hay tres entornos separados porque sus dependencias chocan entre sí:
#  - texto: ConTexto + spaCy (03c, 03d). ConTexto (2021) se instala sin sus dependencias fijadas, que no compilan hoy.
#  - emb:   sentence-transformers + PyTorch (03g, embeddings de oraciones).
#  - tf:    TensorFlow, el backend de keras3 para las redes (08c-08q); R lo usa a través de reticulate.
# Por defecto viven en ~/.virtualenvs/ps3-<nombre>, FUERA de la carpeta del proyecto: OneDrive e iCloud sincronizan miles
# de archivos pequeños y pueden sacarlos del disco, y entonces Python se cuelga al importar. Se respetan las ubicaciones
# que ya usaba el equipo (.venv y .venv-tf en el proyecto, ~/.venvs/ps3-*) y una variable de entorno por entorno.
VENVS <- list(
  texto = list(req = here("requirements.txt"),     var = "PS3_VENV_TEXTO", previos = c(here(".venv"))),
  emb   = list(req = here("requirements-emb.txt"), var = "PS3_VENV_EMB",   previos = c("~/.venvs/ps3-emb")),
  tf    = list(req = here("requirements-tf.txt"),  var = "VENV_TF",        previos = c("~/.venvs/ps3-tf", here(".venv-tf")))
)
PYTHON_VERSION <- "3.11"

# Ejecutable de Python dentro de un entorno virtual (la estructura cambia entre Windows y macOS/Linux)
python_de <- function(dir) {
  if (.Platform$OS.type == "windows") file.path(dir, "Scripts", "python.exe") else file.path(dir, "bin", "python")
}
# Carpeta del entorno: variable de entorno > ubicación previa que ya exista > ~/.virtualenvs/ps3-<nombre>
dir_venv <- function(nombre) {
  v <- VENVS[[nombre]]; stopifnot(!is.null(v))
  if (nzchar(Sys.getenv(v$var))) return(normalizePath(Sys.getenv(v$var), winslash = "/", mustWork = FALSE))
  for (d in normalizePath(v$previos, winslash = "/", mustWork = FALSE)) if (file.exists(python_de(d))) return(d)
  normalizePath(file.path(Sys.getenv("PS3_VENVS", file.path(path.expand("~"), ".virtualenvs")), paste0("ps3-", nombre)),
                winslash = "/", mustWork = FALSE)
}
hay_venv <- function(nombre) file.exists(python_de(dir_venv(nombre)))

# Corre python del entorno con argumentos; se detiene si falla
py_corre <- function(nombre, args, ...) {
  r <- processx::run(python_de(dir_venv(nombre)), args, wd = RAIZ, echo = TRUE, error_on_status = FALSE, ...)
  if (r$status != 0) stop("Falló: python (", nombre, ") ", paste(args, collapse = " "))
  invisible(r)
}

# Crea el entorno si no existe e instala sus requirements. Solo hace falta la primera vez; tarda varios minutos
# (TensorFlow y PyTorch pesan cerca de 1 GB). Dos caminos, el mismo resultado:
#  - con uv (https://docs.astral.sh/uv/, si está instalado): descarga Python 3.11 si hace falta; es el más rápido.
#  - sin uv: reticulate busca un Python 3.11 en el equipo o lo instala (install_python) y crea el entorno con pip.
asegura_venv <- function(nombre) {
  if (hay_venv(nombre)) return(invisible(python_de(dir_venv(nombre))))
  d <- dir_venv(nombre); v <- VENVS[[nombre]]; py <- python_de(d)
  message("Creando el entorno de Python '", nombre, "' en ", d, " (solo la primera vez)...")
  dir.create(dirname(d), recursive = TRUE, showWarnings = FALSE)
  uv <- Sys.which("uv")
  instala <- if (nzchar(uv)) {
    corre_uv <- function(...) {
      r <- processx::run(uv, c(...), echo = TRUE, stderr_to_stdout = TRUE, error_on_status = FALSE)
      if (r$status != 0) stop("Falló: uv ", paste(c(...), collapse = " "))
    }
    corre_uv("venv", d, "--python", PYTHON_VERSION, "--seed")   # --seed: con pip, que usa `spacy download`
    function(...) corre_uv("pip", "install", "--python", py, ...)
  } else {
    base <- reticulate::virtualenv_starter(PYTHON_VERSION)
    if (is.null(base)) {
      message("No se encontró Python ", PYTHON_VERSION, " en el equipo: se instala con reticulate::install_python().")
      base <- reticulate::install_python(paste0(PYTHON_VERSION, ":latest"))
    }
    reticulate::virtualenv_create(d, python = base, packages = NULL)
    py_corre(nombre, c("-m", "pip", "install", "--upgrade", "pip"))
    function(...) py_corre(nombre, c("-m", "pip", "install", ...))
  }
  instala("-r", v$req)
  if (nombre == "texto") {
    instala("--no-deps", "contexto==0.2.0")                              # sin sus dependencias fijadas de 2021
    py_corre(nombre, c("-m", "spacy", "download", "es_core_news_md"))    # modelo de lematización de spaCy
  }
  invisible(py)
}
