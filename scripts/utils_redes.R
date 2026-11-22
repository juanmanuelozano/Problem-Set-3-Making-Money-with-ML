# =============================================================================
# utils_redes.R - Funciones comunes de las redes neuronales (08c NN STAR, 08d red general), D16
# Keras 3 desde R (keras3); TensorFlow vive en .venv-tf (requirements-tf.txt). Uso, después de utils_modelos.R:
#   source("scripts/utils_redes.R")
# Validación igual que el resto: cv_oof() con una localidad afuera y buffer. Las épocas se eligen como las rondas
# del boosting: se entrena de a bloques y se predice la evaluación al final de cada bloque (mejor_columna()).
# PRUEBA=1 en el entorno -> 2 épocas, para probar el flujo completo en minutos.
# =============================================================================
reticulate::use_virtualenv(normalizePath(".venv-tf"), required = TRUE)
suppressMessages(pacman::p_load(keras3, Matrix))

PRUEBA <- nzchar(Sys.getenv("PRUEBA"))
EPOCAS <- if (PRUEBA) c(1, 2) else c(1:10, seq(12, 30, 2), seq(35, 80, 5))   # el óptimo está en 5-10 épocas
LR <- 1e-3; BATCH <- 512; L2 <- 1e-4; K_TXT <- 1000
T0 <- Sys.time(); paso <- function(msg) cat(sprintf("[%5.0f min] %s\n", as.numeric(difftime(Sys.time(), T0, units = "mins")), msg))

# ---- Bloques de variables: estructura, ubicación (mismo grupo que el XGB STAR) y texto (TF-IDF, 1.000 términos) ----
XT <- readRDS(file.path(P$processed, "base_texto.rds"))
XT <- XT[, order(-colSums(XT != 0))[1:K_TXT]]
es_loc_red <- function(cn) sub("_2$", "", cn) %in% c("lat", "lon", "lat_rot1", "lat_rot2", "estrato_final") |
  grepl("^(dist|n500)_", cn) | grepl("500$", cn)   # 500$: area_verde500, pisos_prom500 (D15)
# Zona de lujo (D15, experimental): embajadas, oficinas, hoteles y clubes casi funcionan como dummy de Chapinero; con
# ellas, la configuración de m17 empeoraba de 146,9 a 166,5 en Chapinero. Las redes no las usan.
LUJO <- "^(dist|n500)_(embajada|oficina|hotel|club)$"
bloques_red <- function(df, obj) {
  X <- matriz_lineal(df)
  X <- X[, !colnames(X) %in% c("log_area_x_estrato", "dist_cbd_x_apto") & !grepl(LUJO, colnames(X))]   # cruces de grupos y zona de lujo
  if (obj == "m2") X <- X[, !grepl("log_area", colnames(X))]                # como arma_objetivos()
  u <- es_loc_red(colnames(X))
  list(est = X[, !u], ubi = X[, u], txt = as.matrix(XT[match(df$property_id, rownames(XT)), ]))
}
BR  <- list(m2 = bloques_red(TR, "m2"), precio = bloques_red(TR, "precio"))
BTE <- list(m2 = bloques_red(TE, "m2"), precio = bloques_red(TE, "precio"))
YR  <- list(m2 = Y - TR$log_area, precio = Y)
OFF <- list(m2 = list(tr = TR$log_area, te = TE$log_area), precio = list(tr = 0, te = 0))
dims <- function(B) sapply(B, ncol)
sub_b <- function(B, i) lapply(B, \(x) x[i, , drop = FALSE])

# Estandariza estructura y ubicación con las filas dadas (las de análisis del fold); el TF-IDF queda igual
ajusta_escala <- function(B) {
  m <- lapply(B[c("est", "ubi")], colMeans)
  s <- lapply(B[c("est", "ubi")], \(x) { s <- apply(x, 2, sd); s[!is.finite(s) | s == 0] <- 1; s })
  function(B2) { for (k in c("est", "ubi")) B2[[k]] <- sweep(sweep(B2[[k]], 2, m[[k]]), 2, s[[k]], "/"); B2 }
}
a_keras <- function(B, tipo) {
  f32 <- \(x) reticulate::np_array(x, dtype = "float32")
  if (tipo == "star") unname(lapply(B[c("est", "ubi", "txt")], f32)) else f32(cbind(B$est, B$ubi, B$txt))
}

# ---- Arquitecturas ----
# Las capas de salida (Dense(1) final, atajos y estructura) empiezan en cero: con pesos aleatorios, cada rama arranca
# con ruido grande (de ~1,4 en log en la de estructura) y las ramas se compensan entre sí; el NN STAR tardaba más de 150
# épocas en converger y generalizaba mal (MAE 200 frente a ~130 con ceros en la prueba con 3 folds).
profunda <- function(x, p, reg) x |>   # 64-32-16 ReLU con dropout después de 64 y de 32
  layer_dense(64, activation = "relu", kernel_regularizer = reg) |> layer_dropout(p) |>
  layer_dense(32, activation = "relu", kernel_regularizer = reg) |> layer_dropout(p) |>
  layer_dense(16, activation = "relu", kernel_regularizer = reg) |>
  layer_dense(1, kernel_initializer = "zeros", kernel_regularizer = reg)
# NN STAR: estructura lineal + ubicación (profunda + atajo lineal) + texto (profunda + atajo); solo se suman
red_star <- function(d, p_u, p_t, l2 = L2) {
  reg <- regularizer_l2(l2)
  lineal <- \(x) x |> layer_dense(1, use_bias = FALSE, kernel_initializer = "zeros", kernel_regularizer = reg)
  i <- list(layer_input(d[["est"]]), layer_input(d[["ubi"]]), layer_input(d[["txt"]]))
  f <- list(est = lineal(i[[1]]), ubi = layer_add(list(profunda(i[[2]], p_u, reg), lineal(i[[2]]))),
            txt = layer_add(list(profunda(i[[3]], p_t, reg), lineal(i[[3]]))))
  list(tipo = "star", modelo = keras_model(i, layer_add(unname(f))), ramas = keras_model(i, unname(f)))
}
# Red general: todas las variables mezcladas desde la primera capa (mismo tamaño que el NN STAR)
red_general <- function(d, p, l2 = L2) {
  i <- layer_input(sum(d))
  list(tipo = "general", modelo = keras_model(i, profunda(i, p, regularizer_l2(l2))))
}

# ---- Entrenamiento por bloques de épocas -> matriz de predicciones (columna = épocas), como xgb_rondas() ----
# Calibración (Remark 6 de Mayer et al., 2022): se corrige el nivel para que la predicción media del análisis
# sea igual a la media observada. attr(, "corr") guarda la corrección del último bloque.
entrena <- function(red, xa, ya, xe, epocas = EPOCAS, lr = LR, perdida = "mse") {
  m <- red$modelo; m |> compile(optimizer = optimizer_adam(lr), loss = perdida)
  mu <- mean(ya); yk <- reticulate::np_array(matrix(ya - mu), dtype = "float32"); ant <- 0; corr <- NA
  out <- sapply(epocas, function(ep) {
    m |> fit(xa, yk, epochs = ep, initial_epoch = ant, batch_size = BATCH, verbose = 0); ant <<- ep
    corr <<- mu + mean(ya - mu - drop(predict(m, xa, batch_size = 8192, verbose = 0)))
    drop(predict(m, xe, batch_size = 8192, verbose = 0)) + corr
  })
  structure(`colnames<-`(matrix(out, ncol = length(epocas)), epocas), corr = corr)
}

# Validación cruzada de una red (construye(d) devuelve un modelo nuevo); elige las épocas con mejor_columna()
cv_red <- function(construye, obj, epocas = EPOCAS, lr = LR, perdida = "mse") {
  B <- BR[[obj]]; y <- YR[[obj]]
  oof <- cv_oof(function(a, e) {
    esc <- ajusta_escala(sub_b(B, a)); set_random_seed(123); red <- construye(dims(B))
    entrena(red, a_keras(esc(sub_b(B, a)), red$tipo), y[a], a_keras(esc(sub_b(B, e)), red$tipo), epocas, lr, perdida)
  }) + OFF[[obj]]$tr
  j <- mejor_columna(oof); list(epocas = epocas[j], oof = oof[, j], borde = j == length(epocas))
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
ajusta_final <- function(b, construye_de, lr = LR, perdida = "mse") {
  obj <- b$objetivo; esc <- ajusta_escala(BR[[obj]]); set_random_seed(123); red <- construye_de(b, dims(BR[[obj]]))
  xtr <- a_keras(esc(BR[[obj]]), red$tipo); xte <- a_keras(esc(BTE[[obj]]), red$tipo)
  p <- entrena(red, xtr, YR[[obj]], xte, b$epocas, lr, perdida)
  list(red = red, xtr = xtr, xte = xte, corr = attr(p, "corr"), pred_te = drop(p) + OFF[[obj]]$te)
}
