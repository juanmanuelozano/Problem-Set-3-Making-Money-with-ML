# =============================================================================
# 00_main.R - Script maestro: reproduce el proyecto de principio a fin (R y Python) en Windows y macOS
#
# Uso (ver README.md):
#   - RStudio: abrir Problem-Set-3-Making-Money-with-ML.Rproj y correr source("code/00_main.R").
#   - Terminal, desde cualquier carpeta:  Rscript code/00_main.R   (opciones: --todo, --descargas, --python, --redes,
#     --lentos, --prueba, --solo=a.R,b.R; por ejemplo, Rscript code/00_main.R --todo reproduce todo desde cero).
#
# Cada script corre en un proceso de R (o de Python) NUEVO, con la raíz del proyecto como directorio de trabajo: ningún
# objeto pasa de un script a otro, solo los archivos que cada uno guarda. La salida de cada script queda en
# output/logs/<script>.log. Si un script falla, la corrida se detiene y dice cuál fue y dónde está su log.
# Al final se escriben output/session_info.txt (paquetes de R) y output/python_<entorno>.txt (paquetes de Python).
# =============================================================================
# Si se llama desde una carpeta fuera del proyecto (Rscript <ruta>/code/00_main.R), se ubica la raíz a partir de la ruta
# de este archivo; dentro del proyecto (RStudio con el .Rproj, o la terminal en cualquier subcarpeta) here() ya la encuentra.
local({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (!length(f)) f <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (length(f) && !file.exists(file.path(here::here(), "code", "00_main.R"))) {
    setwd(dirname(dirname(normalizePath(f[1])))); here::i_am("code/00_main.R")
  }
})
source(here::here("code", "01_setup.R"))

# ---- 1. Interruptores ----
# Con todo en FALSE se corre la línea principal (descriptivas, base de modelación y modelos rápidos) y se reutilizan los
# resultados guardados de lo demás. Un paso apagado igual corre si falta alguno de los archivos que produce y que otros
# pasos necesitan (por ejemplo, en un clon nuevo faltan tfidf.parquet y base_texto.rds, que no están en git).
DESCARGAS <- FALSE  # OpenStreetMap (01b) y catastro (03f, 03h): descargas de internet; si no, se usa la caché de data/
PYTHON    <- FALSE  # texto con ConTexto (03c), TF-IDF (03d) y embeddings (03g); crea los entornos de Python si faltan
REDES     <- FALSE  # redes neuronales con Keras (08c-08q, 08p): varias horas; crea el entorno de TensorFlow si falta
LENTOS    <- FALSE  # buffer (03b), random forests (05, 05c), red nnet (09), XGB ponderado (10), XGB STAR (08, 08b)
PRUEBA    <- FALSE  # TRUE: las redes y los XGB STAR corren con grillas mínimas (flujo completo en minutos, PRUEBA=1)
SOLO_PASOS <- character(0)   # p. ej. c("04_regresiones.R", "90_comparacion.R"): corre solo esos pasos, sin mirar banderas

# Opciones de la línea de comandos (sobrescriben lo anterior)
args <- commandArgs(trailingOnly = TRUE)
if ("--todo" %in% args) DESCARGAS <- PYTHON <- REDES <- LENTOS <- TRUE
if ("--descargas" %in% args) DESCARGAS <- TRUE
if ("--python" %in% args) PYTHON <- TRUE
if ("--redes" %in% args) REDES <- TRUE
if ("--lentos" %in% args) LENTOS <- TRUE
if ("--prueba" %in% args) PRUEBA <- TRUE
if (any(startsWith(args, "--solo="))) SOLO_PASOS <- strsplit(sub("^--solo=", "", grep("^--solo=", args, value = TRUE)[1]), ",")[[1]]
BANDERAS <- c(DESCARGAS = DESCARGAS, PYTHON = PYTHON, REDES = REDES, LENTOS = LENTOS)

# ---- 2. Pasos, en orden de ejecución ----
# script: archivo en code/ | bandera: NA = siempre; si no, el interruptor que lo enciende | env: variables de entorno
# (variantes del mismo script) | produce: archivos que otros pasos necesitan (si falta alguno, el paso corre igual)
# requiere: "sf", "keras" o el entorno de Python ("texto", "emb") | etapa: para el resumen.
d <- function(...) file.path("data", ...)
pasos <- tribble(
  ~etapa,                    ~script,                         ~bandera,    ~env,                        ~produce,                                                                  ~requiere,
  "1. Datos externos",       "01b_osm_descarga.R",            "DESCARGAS", "",                          d("external", "osm", c("localidades_poligonos.csv", "servicios_puntos.csv", "barrios_nombres.csv")), "",
  "2. Descriptivas y base",  "02_descriptivas.R",             NA,          "",                          d("processed", "base_enriquecida.csv"),                                    "",
  "2. Descriptivas y base",  "03c_texto.py",                  "PYTHON",    "",                          d("processed", "texto_limpio.csv"),                                        "texto",
  "2. Descriptivas y base",  "03d_tfidf.py",                  "PYTHON",    "",                          d("processed", "tfidf.parquet"),                                           "texto",
  "2. Descriptivas y base",  "03_features.R",                 NA,          "",                          d("processed", "base_modelo.rds"),                                         "",
  "2. Descriptivas y base",  "02b_extremos.R",                NA,          "",                          character(0),                                                              "",
  "2. Descriptivas y base",  "02c_composicion_test.R",        NA,          "",                          character(0),                                                              "",
  "2. Descriptivas y base",  "03b_buffer.R",                  "LENTOS",    "",                          character(0),                                                              "",
  "2. Descriptivas y base",  "03e_pca.R",                     NA,          "",                          c(d("processed", c("base_texto.rds", "pca_no_texto.csv", "pca_texto.csv")), file.path("models", "pca_no_texto.rds")), "",
  "2. Descriptivas y base",  "03f_catastro.R",                "DESCARGAS", "",                          d("processed", "catastro.csv"),                                            "sf",
  "2. Descriptivas y base",  "03h_construcciones.R",          "DESCARGAS", "",                          d("processed", "construcciones.csv"),                                      "sf",
  "2. Descriptivas y base",  "03g_embeddings.py",             "PYTHON",    "",                          character(0),                                                              "emb",
  "3. Modelos",              "04_regresiones.R",              NA,          "",                          character(0),                                                              "",
  "3. Modelos",              "04b_elastic_net.R",             NA,          "",                          character(0),                                                              "",
  "3. Modelos",              "04c_elastic_net_pca.R",         NA,          "",                          character(0),                                                              "",
  "3. Modelos",              "04d_diagnostico_ubicacion.R",   NA,          "",                          character(0),                                                              "",
  "3. Modelos",              "05_random_forest.R",            "LENTOS",    "",                          character(0),                                                              "",
  "3. Modelos",              "05b_cart.R",                    NA,          "",                          character(0),                                                              "",
  "3. Modelos",              "05c_rf_m2.R",                   "LENTOS",    "",                          character(0),                                                              "",
  "3. Modelos",              "06_xgboost.R",                  NA,          "",                          character(0),                                                              "",
  "3. Modelos",              "07_hibridos.R",                 NA,          "",                          character(0),                                                              "",
  "3. Modelos",              "09_red_neuronal.R",             "LENTOS",    "",                          character(0),                                                              "",
  "3. Modelos",              "10_xgb_ponderado.R",            "LENTOS",    "",                          character(0),                                                              "",
  # Pesos de la validación ponderada (TWCV, D16): los usan los XGB STAR y las redes para elegir hiperparámetros
  "4. Validación ponderada", "91_validacion_sintetica.R",     "LENTOS|REDES", "",                       d("processed", "pesos_validacion.csv"),                                    "",
  "5. STAR y redes",         "08c_nn_star.R",                 "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08d_nn_general.R",              "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08e_nn_star_afinacion.R",       "REDES",     "CRITERIO=total",            character(0),                                                              "keras",
  "5. STAR y redes",         "08f_nn_star_twcv.R",            "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08f2_nn_star_twcv_3sem.R",      "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08g_nn_general_twcv.R",         "REDES",     "GANADORA=twcv",             character(0),                                                              "keras",
  "5. STAR y redes",         "08_xgb_star.R",                 "LENTOS",    "CATASTRO=no",               character(0),                                                              "",
  "5. STAR y redes",         "08b_en_star.R",                 "LENTOS",    "",                          character(0),                                                              "",
  "5. STAR y redes",         "08h_nn_star_catastro.R",        "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08i_nn_star_catastro.R",        "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08g_nn_general_twcv.R",         "REDES",     "GANADORA=catastro",         character(0),                                                              "keras",
  "5. STAR y redes",         "08j_redes_peso_twcv.R",         "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08_xgb_star.R",                 "LENTOS",    "CATASTRO=valor_estrato",    character(0),                                                              "",
  "5. STAR y redes",         "08l_nn_star_ramas.R",           "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08m_criterio_twcv_edif.R",      "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08n_nn_star_dropout_ramas.R",   "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08k_nn_star_comparables.R",     "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08o_nn_star_datos_nuevos.R",    "REDES",     "",                          character(0),                                                              "keras",
  "5. STAR y redes",         "08q_nn_general_m24.R",          "REDES",     "",                          character(0),                                                              "keras",
  # 08p elige el peso de su combinación con la red de 08k (models/nn_star_comparables.rds): va con las redes
  "5. STAR y redes",         "08p_xgb_star_comparables.R",    "REDES",     "VARIANTE=",                 character(0),                                                              "",
  "5. STAR y redes",         "08p_xgb_star_comparables.R",    "REDES",     "VARIANTE=distinto",         character(0),                                                              "",
  "5. STAR y redes",         "08p_xgb_star_comparables.R",    "REDES",     "VARIANTE=area",             character(0),                                                              "",
  "5. STAR y redes",         "08p_xgb_star_comparables.R",    "REDES",     "VARIANTE=area_sq",          character(0),                                                              "",
  "5. STAR y redes",         "08p_xgb_star_comparables.R",    "REDES",     "VARIANTE=area_sq_general",  character(0),                                                              "",
  "6. Ensambles y cierre",   "94_star_nn_xgb.R",              NA,          "",                          character(0),                                                              "",
  "6. Ensambles y cierre",   "90_comparacion.R",              NA,          "",                          character(0),                                                              "",
  "6. Ensambles y cierre",   "91_validacion_sintetica.R",     NA,          "",                          character(0),                                                              ""
)
stopifnot(all(file.exists(file.path(P$code, pasos$script))))

# ---- 3. Funciones de ejecución ----
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
min_desde <- function(t) as.numeric(difftime(Sys.time(), t, units = "mins"))
nombre_log <- function(p) file.path(P$logs, paste0(tools::file_path_sans_ext(p$script),
                                                   if (nzchar(p$env)) paste0("__", gsub("[^A-Za-z0-9]+", "_", p$env)), ".log"))
vars_de <- function(p) {
  v <- c(PRUEBA = if (PRUEBA) "1" else "", PYTHONUTF8 = "1")   # PYTHONUTF8: tildes bien impresas en Windows
  if (nzchar(p$env)) { kv <- strsplit(p$env, "=", fixed = TRUE)[[1]]; v[kv[1]] <- if (length(kv) > 1) kv[2] else "" }
  v
}

# ¿Corre el paso? Devuelve "" si corre o el motivo por el que se salta
decide <- function(p) {
  faltan <- p$produce[[1]][!file.exists(here(p$produce[[1]]))]
  if (length(SOLO_PASOS)) { if (!p$script %in% SOLO_PASOS) return("no está en SOLO_PASOS") }
  else if (!is.na(p$bandera) && !any(BANDERAS[strsplit(p$bandera, "|", fixed = TRUE)[[1]]]) && !length(faltan))
    return(paste0(p$bandera, " = FALSE (se usan los resultados guardados)"))
  if (p$requiere == "sf" && !HAY_SF) return("el paquete sf no carga en este equipo")
  if (p$requiere == "keras" && !HAY_KERAS) return("el paquete keras3 no carga en este equipo")
  ""
}

corre <- function(p) {
  log <- nombre_log(p); ext <- tools::file_ext(p$script)
  if (p$requiere %in% c("texto", "emb")) asegura_venv(p$requiere)
  if (p$requiere == "keras") asegura_venv("tf")
  prog <- if (ext == "py") python_de(dir_venv(p$requiere)) else rscript
  args <- file.path(P$code, p$script)
  r <- processx::run(prog, args, wd = RAIZ, env = c("current", vars_de(p)), echo = TRUE, stderr_to_stdout = TRUE,
                     error_on_status = FALSE, encoding = "UTF-8")
  writeLines(r$stdout, log, useBytes = TRUE)
  if (r$status != 0) stop(sprintf("Falló %s%s (código %d). Revise el log: %s", p$script,
                                  if (nzchar(p$env)) paste0(" [", p$env, "]") else "", r$status, log), call. = FALSE)
}

# ---- 4. Corrida ----
T0 <- Sys.time()
cat(sprintf("\n=== Problem Set 3 · corrida completa (%s) ===\nRaíz: %s\nBanderas: %s | PRUEBA = %s\n\n", format(T0, "%Y-%m-%d %H:%M"),
            RAIZ, paste(names(BANDERAS), BANDERAS, sep = " = ", collapse = ", "), PRUEBA))
resumen <- vector("list", nrow(pasos))
for (i in seq_len(nrow(pasos))) {
  p <- pasos[i, ]; motivo <- decide(p); etiqueta <- paste0(p$script, if (nzchar(p$env)) paste0(" [", p$env, "]"))
  if (nzchar(motivo)) {
    if (motivo == "no está en SOLO_PASOS") next
    cat(sprintf("[%5.1f min] (%2d/%d) se salta  %-55s %s\n", min_desde(T0), i, nrow(pasos), etiqueta, motivo))
    resumen[[i]] <- tibble(etapa = p$etapa, paso = etiqueta, estado = "saltado", minutos = NA_real_, motivo = motivo)
    next
  }
  cat(sprintf("\n[%5.1f min] (%2d/%d) corre    %-55s %s\n", min_desde(T0), i, nrow(pasos), etiqueta, p$etapa))
  t <- Sys.time(); corre(p)
  resumen[[i]] <- tibble(etapa = p$etapa, paso = etiqueta, estado = "corrió", minutos = round(min_desde(t), 1), motivo = "")
}
resumen <- bind_rows(resumen)   # (los pasos fuera de SOLO_PASOS no aparecen)
write_csv(resumen, file.path(P$logs, "resumen_corrida.csv"))
cat(sprintf("\n=== Resumen (%.1f min en total) ===\n", min_desde(T0)))
print(as.data.frame(resumen), right = FALSE, row.names = FALSE)

# ---- 5. Información de la sesión ----
# R: los paquetes cargados por 01_setup.R son los mismos que usan todos los scripts.
si <- sessioninfo::session_info(to_file = file.path(P$output, "session_info.txt"))
print(si)
# Python: versiones exactas de cada entorno que exista
for (n in names(VENVS)) if (hay_venv(n)) {
  r <- processx::run(python_de(dir_venv(n)), c("-m", "pip", "freeze"), error_on_status = FALSE)
  v <- processx::run(python_de(dir_venv(n)), "--version", error_on_status = FALSE)
  writeLines(c(paste0("# Entorno de Python \"", n, "\" (", dir_venv(n), "): ", trimws(v$stdout)), r$stdout),
             file.path(P$output, paste0("python_", n, ".txt")), useBytes = TRUE)
}
cat("\nListo. Figuras y tablas en output/, información de la sesión en output/session_info.txt.\n")
