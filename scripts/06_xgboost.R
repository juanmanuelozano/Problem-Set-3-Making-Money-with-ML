# =============================================================================
# 06_xgboost.R - Gradient boosting (xgboost 3.x) sobre log(precio)
# Grilla de profundidad y min_child_weight; número de rondas por early stopping con folds espaciales.
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(library(xgboost))

Xtr <- matriz_arboles(TR); Xte <- matriz_arboles(TE)
dtr <- xgb.DMatrix(Xtr, label = Y, nthread = 8); dte <- xgb.DMatrix(Xte, nthread = 8)
folds <- map(sort(unique(FOLD)), ~ which(FOLD == .x))

params_base <- list(objective = "reg:squarederror", eta = 0.03, subsample = 0.8, colsample_bytree = 0.6,
                    lambda = 1, nthread = 8, eval_metric = "mae")
grilla <- expand_grid(max_depth = c(4, 6, 8), min_child_weight = c(3, 10))
res <- pmap_dfr(grilla, function(max_depth, min_child_weight) {
  t0 <- Sys.time()
  pr <- c(params_base, list(max_depth = max_depth, min_child_weight = min_child_weight))
  cv <- xgb.cv(params = pr, data = dtr, nrounds = 4000, folds = folds, early_stopping_rounds = 100,
               prediction = TRUE, verbose = FALSE)
  p <- drop(cv$cv_predict$pred)
  r <- tibble(max_depth = max_depth, min_child_weight = min_child_weight, nrounds = cv$early_stop$best_iteration,
              oof = list(p)) %>% bind_cols(evalua(p))
  cat(sprintf("depth=%d mcw=%d rondas=%d -> MAE %.1f | Chap %.1f (%.0fs)\n", max_depth, min_child_weight, r$nrounds,
              r$mae_total / 1e6, r$mae_chapinero / 1e6, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  r
})
write_csv(select(res, -oof), file.path(P$rep_mod, "tables", "xgb_grilla.csv"))
best <- res %>% slice_min(mae_total, n = 1, with_ties = FALSE)

pr <- c(params_base, list(max_depth = best$max_depth, min_child_weight = best$min_child_weight))
fit <- xgb.train(params = pr, data = dtr, nrounds = best$nrounds)
registra("m04_xgboost", "XGBoost, objetivo cuadrático sobre log(precio), early stopping espacial",
         sprintf("eta=0.03; max_depth=%d; min_child_weight=%d; nrounds=%d; subsample=0.8; colsample=0.6",
                 best$max_depth, best$min_child_weight, best$nrounds),
         best %>% select(starts_with("ma")), best$oof[[1]], predict(fit, dte))
imp <- xgb.importance(model = fit) %>% as_tibble()
write_csv(imp, file.path(P$rep_mod, "tables", "xgb_importancia.csv")); print(head(imp, 15))
xgb.save(fit, file.path(P$models, "m04_xgboost.ubj"))
