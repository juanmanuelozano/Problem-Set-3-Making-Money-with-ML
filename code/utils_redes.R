# =============================================================================
# utils_redes.R - Funciones comunes de las redes neuronales (08c NN STAR, 08d red general), D17
# Keras 3 desde R (keras3); TensorFlow vive en el entorno de Python "tf" (requirements-tf.txt; ver 01_setup.R). Uso, después de utils_modelos.R:
#   source(here::here("code", "utils_redes.R"))
# Validación igual que el resto: cv_oof() con una localidad afuera y buffer. Las épocas se eligen como las rondas
# del boosting: se entrena de a bloques y se predice la evaluación al final de cada bloque (mejor_columna()).
# PRUEBA=1 en el entorno -> 2 épocas, para probar el flujo completo en minutos.
# =============================================================================
# Entorno de TensorFlow: dir_venv("tf") de 01_setup.R (VENV_TF > ~/.venvs/ps3-tf > .venv-tf > ~/.virtualenvs/ps3-tf),
# siempre fuera de iCloud/OneDrive: si la nube saca los archivos del disco, el import de Keras se cuelga.
if (!hay_venv("tf")) stop("No existe el entorno de Python \"tf\". Corra code/00_main.R con REDES <- TRUE (lo crea) o vea el README.")
reticulate::use_virtualenv(dir_venv("tf"), required = TRUE)

PRUEBA <- nzchar(Sys.getenv("PRUEBA"))
EPOCAS <- if (PRUEBA) c(1, 2) else c(1:10, seq(12, 30, 2), seq(35, 80, 5))   # el óptimo está en 5-10 épocas
LR <- 1e-3; BATCH <- 512; L2 <- 1e-4; K_TXT <- 1000
T0 <- Sys.time(); paso <- function(msg) cat(sprintf("[%5.0f min] %s\n", as.numeric(difftime(Sys.time(), T0, units = "mins")), msg))

# ---- Bloques de variables: estructura, ubicación (mismo grupo que el XGB STAR) y texto (TF-IDF, 1.000 términos) ----
XT <- readRDS(file.path(P$processed, "base_texto.rds"))
XT <- XT[, order(-colSums(XT != 0))[1:K_TXT]]
es_loc_red <- function(cn) sub("_2$", "", cn) %in% c("lat", "lon", "lat_rot1", "lat_rot2", "estrato_final", "log_v_ref", "pisos_manzana") |
  grepl("^(dist|n500)_", cn) | grepl("500$", cn)   # 500$: area_verde500, pisos_prom500 (D15)
# Zona de lujo (LUJO, en utils_modelos.R): con ella, la configuración de m17 empeoraba de 146,9 a 166,5 en Chapinero.
# Las redes nunca la usan. osm = FALSE quita el contexto de OSM (OSM_CTX). area_m2 = TRUE deja log_area en la rama
# lineal con objetivo m2: su coeficiente mide la desviación de la elasticidad precio-área frente a 1 (L2 la acerca a 1).
# catastro (03f_catastro.R, D18): "valor" agrega log(valor de referencia del suelo por m2 de la manzana) a la ubicación;
# "valor_estrato" además reemplaza estrato_final por el estrato oficial de la manzana (si es 0, se deja estrato_final).
CAT <- if (file.exists(file.path(P$processed, "catastro.csv"))) lee_csv(file.path(P$processed, "catastro.csv")) else NULL
# construccion (03h_construcciones.R, D24): pisos, sótanos, semisótano, altura y huella del edificio (estructura) y pisos
# ponderados de la manzana (ubicación). emb (03g_embeddings.py, D25): 384 dimensiones del texto, estandarizadas, que se
# suman al TF-IDF en la rama de texto.
CONS <- if (file.exists(file.path(P$processed, "construcciones.csv"))) lee_csv(file.path(P$processed, "construcciones.csv")) else NULL
EMB <- NULL
lee_emb <- function() {
  e <- read_parquet(file.path(P$processed, "embeddings_texto.parquet")); ids <- e$property_id
  E <- as.matrix(e[, -1]); mu <- colMeans(E[ids %in% TR$property_id, ]); s <- apply(E[ids %in% TR$property_id, ], 2, sd)
  `rownames<-`(sweep(sweep(E, 2, mu), 2, s, "/"), ids)
}
bloques_red <- function(df, obj, area_m2 = FALSE, osm = TRUE, catastro = "no", construccion = FALSE, emb = FALSE) {
  vars <- base$vars
  if (construccion) {
    k <- match(df$property_id, CONS$property_id); stopifnot(!anyNA(k))
    v_c <- setdiff(names(CONS), "property_id"); df[v_c] <- CONS[k, v_c]
    med <- sapply(CONS[CONS$property_id %in% TR$property_id, v_c], median, na.rm = TRUE)   # sin edificio (3%): mediana del train
    df$na_edif <- as.integer(is.na(df$edif_pisos)); for (v in v_c) df[[v]][is.na(df[[v]])] <- med[[v]]
    vars <- c(vars, v_c, "na_edif")
  }
  if (catastro != "no") {
    k <- match(df$property_id, CAT$property_id); stopifnot(!anyNA(k))
    df$log_v_ref <- CAT$log_v_ref[k]; vars <- c(vars, "log_v_ref")
    if (catastro == "valor_estrato") df$estrato_final <- ifelse(CAT$estrato_oficial[k] > 0, CAT$estrato_oficial[k], df$estrato_final)
  }
  X <- matriz_lineal(df, vars = vars)
  X <- X[, !colnames(X) %in% c("log_area_x_estrato", "dist_cbd_x_apto") & !grepl(LUJO, colnames(X)) &
           (osm | !grepl(OSM_CTX, colnames(X)))]                              # cruces de grupos, zona de lujo y OSM
  if (obj == "m2" && !area_m2) X <- X[, !grepl("log_area", colnames(X))]    # como arma_objetivos()
  u <- es_loc_red(colnames(X))
  txt <- as.matrix(XT[match(df$property_id, rownames(XT)), ])
  if (emb) { if (is.null(EMB)) EMB <<- lee_emb(); txt <- cbind(txt, EMB[match(df$property_id, rownames(EMB)), ]) }
  list(est = X[, !u], ubi = X[, u], txt = txt)
}
BR  <- list(m2 = bloques_red(TR, "m2"), precio = bloques_red(TR, "precio"))
BTE <- list(m2 = bloques_red(TE, "m2"), precio = bloques_red(TE, "precio"))
YR  <- list(m2 = Y - TR$log_area, precio = Y)
OFF <- list(m2 = list(tr = TR$log_area, te = TE$log_area), precio = list(tr = 0, te = 0))
# Cambia los bloques globales (BR, BTE) a otra combinación de área en m2, OSM y catastro (08f, 08g, 08h)
usa_bloques <- function(area_m2, osm, catastro = "no", construccion = FALSE, emb = FALSE) {   # solo objetivo m2 desde 08o
  BR  <<- list(m2 = bloques_red(TR, "m2", area_m2, osm, catastro, construccion, emb))
  BTE <<- list(m2 = bloques_red(TE, "m2", area_m2, osm, catastro, construccion, emb))
}
dims <- function(B) sapply(B, ncol)
sub_b <- function(B, i) lapply(B, \(x) x[i, , drop = FALSE])

# Estandariza estructura y ubicación con las filas dadas (las de análisis del fold); el TF-IDF queda igual
ajusta_escala <- function(B) {
  ks <- intersect(c("est", "ubi", "vec"), names(B))   # vec: rama de vecinos (comparables, 08o)
  m <- lapply(B[ks], colMeans)
  s <- lapply(B[ks], \(x) { s <- apply(x, 2, sd); s[!is.finite(s) | s == 0] <- 1; s })
  function(B2) { for (k in ks) B2[[k]] <- sweep(sweep(B2[[k]], 2, m[[k]]), 2, s[[k]], "/"); B2 }
}
a_keras <- function(B, tipo) {
  f32 <- \(x) reticulate::np_array(x, dtype = "float32")
  if (tipo == "star") unname(lapply(B[intersect(c("est", "ubi", "txt", "vec"), names(B))], f32)) else f32(cbind(B$est, B$ubi, B$txt))
}

# ---- Arquitecturas ----
# Las capas de salida (Dense(1) final, atajos y estructura) empiezan en cero: con pesos aleatorios, cada rama arranca
# con ruido grande (de ~1,4 en log en la de estructura) y las ramas se compensan entre sí; el NN STAR tardaba más de 150
# épocas en converger y generalizaba mal (MAE 200 frente a ~130 con ceros en la prueba con 3 folds).
profunda <- function(x, p, reg, capas = c(64, 32, 16), act = "relu") {   # dropout después de cada capa salvo la última
  for (k in seq_along(capas)) {
    x <- layer_dense(x, capas[k], activation = act, kernel_regularizer = reg)
    if (k < length(capas)) x <- layer_dropout(x, p)
  }
  layer_dense(x, 1, kernel_initializer = "zeros", kernel_regularizer = reg)
}
# NN STAR: estructura lineal + ubicación (profunda + atajo lineal) + texto (profunda + atajo); solo se suman
red_star <- function(d, p_u, p_t, l2 = L2, capas_t = c(64, 32, 16), act_u = "relu") {   # capas_t: rama profunda de texto; act_u: activación de la rama profunda de ubicación (08n)
  reg <- regularizer_l2(l2)
  lineal <- \(x) x |> layer_dense(1, use_bias = FALSE, kernel_initializer = "zeros", kernel_regularizer = reg)
  i <- list(layer_input(d[["est"]]), layer_input(d[["ubi"]]), layer_input(d[["txt"]]))
  f <- list(est = lineal(i[[1]]), ubi = layer_add(list(profunda(i[[2]], p_u, reg, act = act_u), lineal(i[[2]]))),
            txt = layer_add(list(profunda(i[[3]], p_t, reg, capas_t), lineal(i[[3]]))))
  if ("vec" %in% names(d)) {   # 4.a rama aditiva: vecinos (comparables), pequeña y sin dropout (08o)
    i[[4]] <- layer_input(d[["vec"]]); f$vec <- layer_add(list(profunda(i[[4]], 0, reg, c(16, 8)), lineal(i[[4]])))
  }
  list(tipo = "star", modelo = keras_model(i, layer_add(unname(f))), ramas = keras_model(i, unname(f)))
}
# Red general: todas las variables mezcladas desde la primera capa (mismo tamaño que el NN STAR)
red_general <- function(d, p, l2 = L2, capas = c(64, 32, 16)) {
  i <- layer_input(sum(d))
  list(tipo = "general", modelo = keras_model(i, profunda(i, p, regularizer_l2(l2), capas)))
}

# ---- Entrenamiento por bloques de épocas -> matriz de predicciones (columna = épocas), como xgb_rondas() ----
# Calibración (Remark 6 de Mayer et al., 2022): se corrige el nivel para que la predicción media del análisis
# sea igual a la media observada. Con w_cal (pesos TWCV de las filas de análisis), la media es ponderada hacia el
# test: el nivel se ajusta al segmento parecido a Chapinero (D17). attr(, "corr") guarda la corrección del último bloque.
# w_fit (pesos de las filas de análisis): pondera la pérdida (08j); se normalizan a media 1 para no cambiar la tasa.
entrena <- function(red, xa, ya, xe, epocas = EPOCAS, lr = LR, perdida = "mse", w_cal = NULL, w_fit = NULL) {
  if (is.null(w_cal)) w_cal <- rep(1, length(ya))
  sw <- if (is.null(w_fit)) NULL else reticulate::np_array(w_fit / mean(w_fit), dtype = "float32")
  m <- red$modelo; m |> compile(optimizer = optimizer_adam(lr), loss = perdida)
  mu <- mean(ya); yk <- reticulate::np_array(matrix(ya - mu), dtype = "float32"); ant <- 0; corr <- NA
  out <- sapply(epocas, function(ep) {
    m |> fit(xa, yk, epochs = ep, initial_epoch = ant, batch_size = BATCH, sample_weight = sw, verbose = 0); ant <<- ep
    corr <<- mu + weighted.mean(ya - mu - drop(predict(m, xa, batch_size = 8192, verbose = 0)), w_cal)
    drop(predict(m, xe, batch_size = 8192, verbose = 0)) + corr
  })
  structure(`colnames<-`(matrix(out, ncol = length(epocas)), epocas), corr = corr)
}

# Validación cruzada de una red (construye(d) devuelve un modelo nuevo); elige las épocas con mejor_columna()
# w: elegir épocas por MAE ponderado; w_cal: calibración ponderada (vector del train completo); semillas: se promedian
# las predicciones (en log) de una red por semilla. folds: otra partición (FOLDS_EDIF, 08k); extra(a, e): columnas de
# ubicación que dependen del fold (comparables), list(a = matriz de las filas a, e = matriz de las filas e).
cv_red <- function(construye, obj, epocas = EPOCAS, lr = LR, perdida = "mse", w = NULL, w_cal = NULL, semillas = 123, w_fit = NULL,
                   folds = FOLDS, extra = NULL, bloque_extra = "ubi") {
  B <- BR[[obj]]; y <- YR[[obj]]
  oof <- cv_oof(function(a, e) {
    Ba <- sub_b(B, a); Be <- sub_b(B, e)
    if (!is.null(extra)) { x <- extra(a, e); Ba[[bloque_extra]] <- cbind(Ba[[bloque_extra]], x$a); Be[[bloque_extra]] <- cbind(Be[[bloque_extra]], x$e) }
    esc <- ajusta_escala(Ba); xa <- xe <- NULL   # se convierten una vez por fold
    Reduce(`+`, map(semillas, function(s) {
      set_random_seed(s); red <- construye(dims(Ba))
      if (is.null(xa)) { xa <<- a_keras(esc(Ba), red$tipo); xe <<- a_keras(esc(Be), red$tipo) }
      entrena(red, xa, y[a], xe, epocas, lr, perdida, if (is.null(w_cal)) NULL else w_cal[a], if (is.null(w_fit)) NULL else w_fit[a])
    })) / length(semillas)
  }, folds) + OFF[[obj]]$tr
  j <- mejor_columna(oof, w); list(epocas = epocas[j], oof = oof[, j], borde = j == length(epocas))
}

# Búsqueda: cada fila de `grilla` con objetivo m2; con la mejor, también el objetivo precio. Guarda a medida que avanza.
busca_red <- function(grilla, construye_de, archivo) {
  res <- list()
  corre <- function(g, obj) {
    r <- cv_red(\(d) construye_de(g, d), obj)
    res[[length(res) + 1]] <<- g %>% mutate(objetivo = obj, epocas = r$epocas, borde = r$borde) %>%
      bind_cols(evalua(r$oof)) %>% mutate(oof = list(r$oof))
    write_csv(select(bind_rows(res), -oof), archivo)
    paso(sprintf("%s | %s | épocas %d%s | MAE %.1f | Chap %.1f", obj, paste(names(g), g, sep = "=", collapse = ", "),
                 r$epocas, if (r$borde) " (borde)" else "", evalua(r$oof)$mae_total / 1e6, evalua(r$oof)$mae_chapinero / 1e6))
  }
  for (k in seq_len(nrow(grilla))) corre(grilla[k, ], "m2")
  corre(bind_rows(res) %>% slice_min(mae_total, n = 1, with_ties = FALSE) %>% select(all_of(names(grilla))), "precio")
  bind_rows(res)
}

# Ajuste final con todo el train y las épocas elegidas; devuelve la red y la predicción de test (en log)
ajusta_final <- function(b, construye_de, lr = LR, perdida = "mse", w_cal = NULL, semillas = 123, w_fit = NULL) {
  obj <- b$objetivo; esc <- ajusta_escala(BR[[obj]])
  ps <- map(semillas, function(s) {
    set_random_seed(s); red <- construye_de(b, dims(BR[[obj]]))
    xtr <- a_keras(esc(BR[[obj]]), red$tipo); xte <- a_keras(esc(BTE[[obj]]), red$tipo)
    list(red = red, xtr = xtr, xte = xte, p = entrena(red, xtr, YR[[obj]], xte, b$epocas, lr, perdida, w_cal, w_fit))
  })
  u <- ps[[length(ps)]]   # la red de la última semilla (para inspeccionar ramas)
  list(red = u$red, xtr = u$xtr, xte = u$xte, corr = mean(map_dbl(ps, ~ attr(.x$p, "corr"))),
       pred_te = Reduce(`+`, map(ps, ~ drop(.x$p))) / length(ps) + OFF[[obj]]$te)
}
