# =============================================================================
# 05_random_forest.R - Random forest (ranger) sobre log(precio)
# Grilla pequeña de mtry y min.node.size, validada dejando una localidad afuera con buffer (cv_oof).
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(ranger))

Xtr <- matriz_arboles(TR); Xte <- matriz_arboles(TE)
cat("Dimensión X:", dim(Xtr), "\n")

oof_rf <- function(mtry, nodo, arboles = 300) cv_oof(function(a, e) {
  m <- ranger(x = Xtr[a, ], y = Y[a], num.trees = arboles, mtry = mtry, min.node.size = nodo, num.threads = 8, seed = 123)
  predict(m, Xtr[e, ], num.threads = 8)$predictions
})
grilla <- expand_grid(mtry = c(10, 20, 35), nodo = c(3, 10))
res <- pmap_dfr(grilla, function(mtry, nodo) {
  t0 <- Sys.time(); p <- oof_rf(mtry, nodo)
  r <- tibble(mtry = mtry, nodo = nodo, oof = list(p)) %>% bind_cols(evalua(p))
  cat(sprintf("mtry=%d nodo=%d -> MAE %.1f | Chap %.1f (%.0fs)\n", mtry, nodo, r$mae_total / 1e6, r$mae_chapinero / 1e6,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  r
})
write_csv(select(res, -oof), file.path(P$rep_mod, "tables", "rf_grilla.csv"))
best <- res %>% slice_min(mae_total, n = 1, with_ties = FALSE)

fit <- ranger(x = Xtr, y = Y, num.trees = 800, mtry = best$mtry, min.node.size = best$nodo,
              importance = "impurity", num.threads = 8, seed = 123)
registra("m03_random_forest", "Random forest (ranger), variables con NA -> -1 e indicadores",
         sprintf("mtry=%d; min.node.size=%d; trees=800 (grilla con 300)", best$mtry, best$nodo),
         best %>% select(starts_with("ma")), best$oof[[1]], predict(fit, Xte, num.threads = 8)$predictions)
imp <- tibble(var = names(fit$variable.importance), importancia = fit$variable.importance) %>% arrange(desc(importancia))
write_csv(imp, file.path(P$rep_mod, "tables", "rf_importancia.csv")); print(head(imp, 15))
saveRDS(fit, file.path(P$models, "m03_random_forest.rds"))
