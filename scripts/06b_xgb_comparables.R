# =============================================================================
# 06b_xgb_comparables.R - XGBoost sobre log(precio por m2) con comparables (D20)
# Mismas variables que m05 (matriz_arboles, con log_area) más el precio por m2 de los comparables: los 5 y 20
# anuncios del train más cercanos del mismo tipo, sin duplicados de descripción (funciones en utils_modelos.R).
# A diferencia del lasso, los árboles pueden combinar los comparables con las características propias
# (p. ej., vecinos caros y apartamento grande y estrato 6).
# Validación: CV aleatoria de 10 folds (FOLDS_ALEAT), la que se parece al test en la distancia a los vecinos;
# la CV por localidad con buffer quita los vecinos (D20). Rondas y profundidad por MAE TWCV (D18).
# Referencia: el mismo XGBoost sin comparables (profundidad 4, la mejor de 06_xgboost.R), en la misma CV.
# OJO: el registro guarda las OOF de la CV aleatoria (no comparables con los modelos validados por localidad).
# Salidas: tables/xgb_comparables_grilla.csv, tables/xgb_comparables_importancia.csv, registro (m22_xgb_comparables_m2)
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(xgboost, RANN))

o <- arma_objetivos(matriz_arboles(TR), matriz_arboles(TE), quita_area = FALSE)$m2   # como m05: conserva log_area
CMP <- prepara_comparables()
C_full <- comparables_train(CMP); C_te <- comparables_test(CMP)

RONDAS <- seq(50, 2500, 50)
params_base <- list(objective = "reg:squarederror", eta = 0.03, subsample = 0.8, colsample_bytree = 0.6,
                    lambda = 1, nthread = 8, seed = 123)
grilla <- tibble(comparables = c(FALSE, TRUE, TRUE), max_depth = c(4, 4, 6), min_child_weight = 10)

res <- pmap_dfr(grilla, function(comparables, max_depth, min_child_weight) {
  t0 <- Sys.time()
  pr <- c(params_base, list(max_depth = max_depth, min_child_weight = min_child_weight))
  oof <- cv_oof(function(a, e) {
    Xa <- o$Xtr[a, ]; Xe <- o$Xtr[e, ]
    if (comparables) { Xa <- cbind(Xa, comparables_fold(CMP, a, a)); Xe <- cbind(Xe, comparables_fold(CMP, a, e)) }
    xgb_rondas(pr, Xa, o$y[a], Xe, RONDAS)
  }, FOLDS_ALEAT) + o$off_tr
  j <- which.min(apply(oof, 2, \(p) evalua(p)$mae_twcv))
  if (j == length(RONDAS)) warning("Las rondas quedaron en el tope de la grilla")
  r <- tibble(comparables, max_depth, min_child_weight, nrounds = RONDAS[j], oof = list(oof[, j])) %>% bind_cols(evalua(oof[, j]))
  cat(sprintf("%-16s depth=%d rondas=%4d -> total %.1f | Chap %.1f | TWCV %.1f | IWCV %.1f (%.1f min)\n",
              if (comparables) "con comparables" else "sin comparables", max_depth, r$nrounds, r$mae_total / 1e6,
              r$mae_chapinero / 1e6, r$mae_twcv / 1e6, r$mae_iwcv / 1e6, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  r
})
write_csv(select(res, -oof), file.path(P$rep_mod, "tables", "xgb_comparables_grilla.csv"))

# ---- Modelo final: la mejor configuración con comparables (por MAE TWCV), entrenada con todo el train ----
best <- res %>% filter(comparables) %>% slice_min(mae_twcv, n = 1, with_ties = FALSE)
pr <- c(params_base, list(max_depth = best$max_depth, min_child_weight = best$min_child_weight))
fit <- xgb.train(params = pr, data = xgb.DMatrix(cbind(o$Xtr, C_full), label = o$y, nthread = 8), nrounds = best$nrounds)
registra("m22_xgb_comparables_m2",
         "XGBoost sobre log(precio/m2) + comparables (5 y 20 vecinos del mismo tipo, sin duplicados); OOF de la CV ALEATORIA de 10 folds",
         sprintf("eta=0.03; max_depth=%d; mcw=%d; nrounds=%d (por MAE TWCV); subsample=0.8; colsample=0.6",
                 best$max_depth, best$min_child_weight, best$nrounds),
         best %>% select(starts_with("ma")), best$oof[[1]],
         predict(fit, xgb.DMatrix(cbind(o$Xte, C_te), nthread = 8)) + o$off_te)
imp <- xgb.importance(model = fit) %>% as_tibble()
write_csv(imp, file.path(P$rep_mod, "tables", "xgb_comparables_importancia.csv")); print(head(imp, 12))
