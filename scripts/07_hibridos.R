# =============================================================================
# 07_hibridos.R - Modelos diseñados para EXTRAPOLAR hacia Chapinero
#  (a) m05: XGBoost sobre log(precio por m2): el área entra de forma multiplicativa
#  (b) m06: híbrido elastic net + XGBoost sobre los residuos (el EN da la tendencia
#           lineal, que sí extrapola; el XGBoost corrige no linealidades)
# Validación: dejar una localidad afuera con buffer (cv_oof). El híbrido usa validación ANIDADA: en cada fold externo
# el elastic net se reajusta y su margen para las filas de entrenamiento es out-of-fold interno.
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages({library(xgboost); library(glmnet)})

Xtr <- matriz_arboles(TR); Xte <- matriz_arboles(TE)
Ltr <- matriz_lineal(TR); Lte <- matriz_lineal(TE)
la_tr <- TR$log_area; la_te <- TE$log_area
pr <- list(objective = "reg:squarederror", eta = 0.03, max_depth = 6, min_child_weight = 10,
           subsample = 0.8, colsample_bytree = 0.6, lambda = 1, nthread = 8, seed = 123)
g_xgb <- file.path(P$rep_mod, "tables", "xgb_grilla.csv")
if (file.exists(g_xgb)) {  # reutiliza la mejor profundidad encontrada en 06_xgboost.R
  b <- lee_csv(g_xgb) %>% slice_min(mae_total, n = 1); pr$max_depth <- b$max_depth; pr$min_child_weight <- b$min_child_weight
}

# ---- (a) XGBoost sobre log(precio/m2) ----
RONDAS <- seq(25, 2000, 25)
oof_a <- cv_oof(function(a, e) xgb_rondas(pr, Xtr[a, ], Y[a] - la_tr[a], Xtr[e, ], RONDAS)) + la_tr
j <- mejor_columna(oof_a); oof_a <- oof_a[, j]
fit_a <- xgb.train(params = pr, data = xgb.DMatrix(Xtr, label = Y - la_tr, nthread = 8), nrounds = RONDAS[j])
registra("m05_xgb_precio_m2", "XGBoost sobre log(precio por m2); se suma log(área) al predecir",
         sprintf("max_depth=%d; mcw=%d; nrounds=%d", pr$max_depth, pr$min_child_weight, RONDAS[j]),
         evalua(oof_a), oof_a, predict(fit_a, xgb.DMatrix(Xte)) + la_te)

# ---- (b) Híbrido elastic net + XGBoost en residuos, validación anidada ----
en_margen <- function(idx_tr, idx_pred_list) {
  # Ajusta lasso en idx_tr con CV interna por localidad; devuelve margen OOF interno para idx_tr y predicción para otras filas
  # ponytail: la CV interna no lleva buffer (cv.glmnet no lo admite); solo afecta la elección de lambda del margen
  cvi <- cv.glmnet(Ltr[idx_tr, ], Y[idx_tr], alpha = 1, foldid = as.integer(factor(GRUPO[idx_tr])), keep = TRUE, type.measure = "mae")
  j <- which(cvi$lambda == cvi$lambda.min)
  c(list(oof = cvi$fit.preval[, j]), map(idx_pred_list, ~ drop(predict(cvi, .x, s = "lambda.min"))))
}
# Evaluación anidada: en cada fold externo el lasso se reajusta solo con el conjunto de análisis.
# Las rondas se eligen con las mismas OOF, como los hiperparámetros de los demás modelos.
RONDAS_H <- seq(10, 1000, 10)
oof_b <- cv_oof(function(a, e) {
  m <- en_margen(a, list(pred = Ltr[e, ]))
  xgb_rondas(pr, Xtr[a, ], Y[a], Xtr[e, ], RONDAS_H, ma = m$oof, me = m$pred)
})
j <- mejor_columna(oof_b); oof_b <- oof_b[, j]; nr <- RONDAS_H[j]; cat("Híbrido: rondas =", nr, "\n")
m_full <- en_margen(seq_along(Y), list(test = Lte))
fit_b <- xgb.train(params = pr, data = xgb.DMatrix(Xtr, label = Y, base_margin = m_full$oof, nthread = 8), nrounds = nr)
pred_b <- predict(fit_b, xgb.DMatrix(Xte, base_margin = m_full$test))
registra("m06_hibrido_en_xgb", "Lasso (tendencia) + XGBoost sobre residuos; validación anidada",
         sprintf("lasso lambda.min; xgb max_depth=%d; mcw=%d; nrounds=%d", pr$max_depth, pr$min_child_weight, nr),
         evalua(oof_b), oof_b, pred_b)
