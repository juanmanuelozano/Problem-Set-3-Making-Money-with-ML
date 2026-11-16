# =============================================================================
# 07_hibridos.R - Modelos diseñados para EXTRAPOLAR hacia Chapinero
#  (a) m05: XGBoost sobre log(precio por m2): el área entra de forma multiplicativa
#  (b) m06: híbrido elastic net + XGBoost sobre los residuos (el EN da la tendencia
#           lineal, que sí extrapola; el XGBoost corrige no linealidades)
# Validación: folds espaciales. El híbrido usa validación ANIDADA: en cada fold externo
# el elastic net se reajusta y su margen para las filas de entrenamiento es out-of-fold interno.
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages({library(xgboost); library(glmnet)})

Xtr <- matriz_arboles(TR); Xte <- matriz_arboles(TE)
Ltr <- matriz_lineal(TR); Lte <- matriz_lineal(TE)
folds <- map(sort(unique(FOLD)), ~ which(FOLD == .x))
la_tr <- TR$log_area; la_te <- TE$log_area
pr <- list(objective = "reg:squarederror", eta = 0.03, max_depth = 6, min_child_weight = 10,
           subsample = 0.8, colsample_bytree = 0.6, lambda = 1, nthread = 8, eval_metric = "mae")
g_xgb <- file.path(P$rep_mod, "tables", "xgb_grilla.csv")
if (file.exists(g_xgb)) {  # reutiliza la mejor profundidad encontrada en 06_xgboost.R
  b <- lee_csv(g_xgb) %>% slice_min(mae_total, n = 1); pr$max_depth <- b$max_depth; pr$min_child_weight <- b$min_child_weight
}

# ---- (a) XGBoost sobre log(precio/m2) ----
d_m2 <- xgb.DMatrix(Xtr, label = Y - la_tr, nthread = 8)
cv <- xgb.cv(params = pr, data = d_m2, nrounds = 4000, folds = folds, early_stopping_rounds = 100, prediction = TRUE, verbose = FALSE)
oof_a <- drop(cv$cv_predict$pred) + la_tr
fit_a <- xgb.train(params = pr, data = d_m2, nrounds = cv$early_stop$best_iteration)
registra("m05_xgb_precio_m2", "XGBoost sobre log(precio por m2); se suma log(área) al predecir",
         sprintf("max_depth=%d; mcw=%d; nrounds=%d", pr$max_depth, pr$min_child_weight, cv$early_stop$best_iteration),
         evalua(oof_a), oof_a, predict(fit_a, xgb.DMatrix(Xte)) + la_te)

# ---- (b) Híbrido elastic net + XGBoost en residuos, validación anidada ----
en_margen <- function(idx_tr, idx_pred_list) {
  # Ajusta lasso con CV espacial interna en idx_tr; devuelve margen OOF interno para idx_tr y predicción para otras filas
  cvi <- cv.glmnet(Ltr[idx_tr, ], Y[idx_tr], alpha = 1, foldid = as.integer(factor(FOLD[idx_tr])), keep = TRUE, type.measure = "mae")
  j <- which(cvi$lambda == cvi$lambda.min)
  c(list(oof = cvi$fit.preval[, j]), map(idx_pred_list, ~ drop(predict(cvi, .x, s = "lambda.min"))))
}
# 1. Número de rondas: xgb.cv con márgenes OOF del EN sobre todo el train (solo para elegir rondas)
m_full <- en_margen(seq_along(Y), list(test = Lte))
d_h <- xgb.DMatrix(Xtr, label = Y, base_margin = m_full$oof, nthread = 8)
cvh <- xgb.cv(params = pr, data = d_h, nrounds = 3000, folds = folds, early_stopping_rounds = 100, verbose = FALSE)
nr <- cvh$early_stop$best_iteration; cat("Híbrido: rondas =", nr, "\n")
# 2. Evaluación anidada limpia
oof_b <- numeric(length(Y))
for (k in seq_along(folds)) {
  te_k <- folds[[k]]; tr_k <- setdiff(seq_along(Y), te_k)
  m <- en_margen(tr_k, list(pred = Ltr[te_k, ]))
  fit <- xgb.train(params = pr, data = xgb.DMatrix(Xtr[tr_k, ], label = Y[tr_k], base_margin = m$oof, nthread = 8), nrounds = nr)
  oof_b[te_k] <- predict(fit, xgb.DMatrix(Xtr[te_k, ], base_margin = m$pred))
  cat(sprintf("  fold %d listo\n", k))
}
fit_b <- xgb.train(params = pr, data = d_h, nrounds = nr)
pred_b <- predict(fit_b, xgb.DMatrix(Xte, base_margin = m_full$test))
registra("m06_hibrido_en_xgb", "Lasso (tendencia) + XGBoost sobre residuos; validación anidada",
         sprintf("lasso lambda.min; xgb max_depth=%d; mcw=%d; nrounds=%d", pr$max_depth, pr$min_child_weight, nr),
         evalua(oof_b), oof_b, pred_b)
