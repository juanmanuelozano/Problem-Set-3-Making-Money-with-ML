# =============================================================================
# 08r_xgb_star_sin_texto.R - Ablación del texto en el XGB STAR (moraleja 1 de
# la presentación)
# Mismo XGB STAR que m22_xgb_star_twcv_m2 (de donde sale el encoder de texto,
# star_encoders.csv), con y sin su grupo de texto (los 1.000 términos TF-IDF).
# Las dummies del texto (tx_*, piso, antigüedad, parqueaderos) se quedan, igual
# que en la ablación de la NN STAR (08l, m52). Configuración de m22: m2, pérdida
# cuadrática, profundidad 3, mcw 5, subsample 0,9, colsample 0,9, lambda 0,5,
# alpha 0, eta 0,1; rondas por MAE TWCV en la CV por localidad. Primero
# reproduce m22.
# Registro: m56_xgb_star_sin_texto_m2
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))

W <- pesos_twcv()
base$vars <- vars_sin(osm_ganadora())
RONDAS <- seq(50, 1000, 50)
Xt <- readRDS(file.path(P$processed, "base_texto.rds"))
Xt <- Xt[, order(-colSums(Xt != 0))[1:1000]]
colnames(Xt) <- paste0("tf_", colnames(Xt))

es_loc <- function(cn) {
  cn %in% c("lat", "lon", "lat_rot1", "lat_rot2", "estrato_final") |
    grepl("^(dist|n500)_", cn) | grepl("500$", cn)
}
es_txt <- function(cn) startsWith(cn, "tf_")
# Restricciones de interacción: cada variable de estructura sola, ubicación
# junta y texto junto
grupos <- function(cn) {
  i <- seq_along(cn) - 1L
  g <- c(as.list(i[!es_loc(cn) & !es_txt(cn)]), list(i[es_loc(cn)]))
  if (any(es_txt(cn))) g <- c(g, list(i[es_txt(cn)]))
  g
}

corre <- function(con_texto) {
  mat <- function(df) {
    M <- Matrix(matriz_arboles(df), sparse = TRUE)
    if (con_texto) cbind(M, Xt[match(df$property_id, rownames(Xt)), ]) else M
  }
  o <- arma_objetivos(mat(TR), mat(TE))$m2
  pr <- list(
    objective = "reg:squarederror", max_bin = 64, nthread = 8, seed = 123,
    interaction_constraints = grupos(colnames(o$Xtr)),
    max_depth = 3, min_child_weight = 5, subsample = .9, colsample_bytree = .9,
    lambda = .5, alpha = 0, eta = .1
  )
  oof <- cv_oof(function(a, e) {
    xgb_rondas(pr, o$Xtr[a, ], o$y[a], o$Xtr[e, ], RONDAS)
  }) + o$off_tr
  j <- mejor_columna(oof, W)
  fit <- xgb.train(
    params = pr, data = xgb.DMatrix(o$Xtr, label = o$y, nthread = 8),
    nrounds = RONDAS[j], verbose = 0
  )
  list(
    oof = oof[, j],
    nrounds = RONDAS[j],
    m = evalua(oof[, j]),
    twcv = mae_w(oof[, j], W),
    pred_te = predict(fit, xgb.DMatrix(o$Xte)) + o$off_te
  )
}

con <- corre(TRUE)
sin <- corre(FALSE)
cat(sprintf(
  paste(
    "Con texto (reproduce m22, registrado 133,2 / TWCV 140,1): rondas %d |",
    "MAE %.1f / Chap %.1f / TWCV %.1f\n"
  ),
  con$nrounds, con$m$mae_total / 1e6, con$m$mae_chapinero / 1e6, con$twcv / 1e6
))
cat(sprintf(
  "Sin texto: rondas %d | MAE %.1f / Chap %.1f / TWCV %.1f\n",
  sin$nrounds, sin$m$mae_total / 1e6, sin$m$mae_chapinero / 1e6, sin$twcv / 1e6
))

registra(
  "m56_xgb_star_sin_texto_m2",
  paste(
    "XGB STAR como m22_xgb_star_twcv_m2 SIN el grupo de texto TF-IDF",
    "(las dummies del texto se quedan), 08r; ablación del texto;",
    "sobre log(precio por m2)"
  ),
  sprintf(
    paste(
      "reg:squarederror; depth=3; mcw=5; subsample=0.9; colsample=0.9;",
      "lambda=0.5; alpha=0; eta=0.1; nrounds=%d; sin grupo de texto"
    ),
    sin$nrounds
  ),
  sin$m, sin$oof, sin$pred_te
)
