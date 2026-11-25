# =============================================================================
# 05c_rf_m2.R - Random forest (ranger) sobre log(precio por m2), versión rápida
# Igual que 05_random_forest.R, pero con el objetivo de precio por m2 (el que mejor viajó en los lineales) y
# una variante sin coordenadas crudas (lat, lon y sus rotaciones), para ver si las distancias generalizan
# mejor hacia Chapinero. Validación: una localidad afuera con buffer (cv_oof). ~10 min.
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R"))

Xtr <- matriz_arboles(TR); Xte <- matriz_arboles(TE)
obj <- arma_objetivos(Xtr, Xte)$m2   # quita log_area; el precio se recupera sumando log(área)
coords <- c("lat", "lon", "lat_rot1", "lat_rot2")

# Grilla corta: con y sin coordenadas, 200 árboles (rápido). mtry = 12: en una primera corrida (con
# coordenadas) dio MAE 142,4 M total y 177,3 M en Chapinero; mtry = 25 no alcanzó a terminar.
oof_rf <- function(cols, mtry, nodo = 5, arboles = 200) cv_oof(function(a, e) {
  m <- ranger(x = obj$Xtr[a, cols], y = obj$y[a], num.trees = arboles, mtry = mtry, min.node.size = nodo,
              num.threads = 8, seed = 123, verbose = FALSE)
  predict(m, obj$Xtr[e, cols], num.threads = 8)$predictions + obj$off_tr[e]
})
variantes <- list(m2 = colnames(obj$Xtr), m2_sin_coord = setdiff(colnames(obj$Xtr), coords))
grilla <- expand_grid(variante = names(variantes), mtry = 12)
res <- pmap_dfr(grilla, function(variante, mtry) {
  t0 <- Sys.time(); p <- oof_rf(variantes[[variante]], mtry)
  r <- tibble(variante = variante, mtry = mtry, oof = list(p)) %>% bind_cols(evalua(p))
  cat(sprintf("%s mtry=%d -> MAE %.1f | Chap %.1f (%.0fs)\n", variante, mtry, r$mae_total / 1e6, r$mae_chapinero / 1e6,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  r
})
write_csv(select(res, -oof), file.path(P$tab_mod, "rf_m2_grilla.csv"))

# Un modelo registrado por variante (mejor mtry según MAE total), reentrenado en todo el train con 500 árboles
for (v in names(variantes)) {
  best <- res %>% filter(variante == v) %>% slice_min(mae_total, n = 1, with_ties = FALSE)
  cols <- variantes[[v]]
  fit <- ranger(x = obj$Xtr[, cols], y = obj$y, num.trees = 500, mtry = best$mtry, min.node.size = 5,
                importance = "impurity", num.threads = 8, seed = 123, verbose = FALSE)
  registra(paste0("m15_rf_", v), paste("Random forest (ranger) sobre log(precio/m2)",
                                       if (v == "m2_sin_coord") "sin lat/lon ni rotaciones" else "con todas las variables"),
           sprintf("mtry=%d; min.node.size=5; trees=500 (grilla con 200)", best$mtry),
           best %>% select(starts_with("ma")), best$oof[[1]],
           predict(fit, obj$Xte[, cols], num.threads = 8)$predictions + obj$off_te)
  imp <- tibble(var = names(fit$variable.importance), importancia = fit$variable.importance) %>% arrange(desc(importancia))
  write_csv(imp, file.path(P$tab_mod, paste0("rf_importancia_", v, ".csv"))); print(head(imp, 10))
}
