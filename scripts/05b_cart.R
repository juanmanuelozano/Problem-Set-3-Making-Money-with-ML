# =============================================================================
# 05b_cart.R - Árbol de regresión único (CART) con ranger, sobre log(precio) y log(precio por m2)
# CART en ranger: num.trees = 1, mtry = todas las variables, sin remuestreo (replace = FALSE, sample.fraction = 1).
# ranger no poda por costo-complejidad (cp de rpart): la complejidad se controla con max.depth y min.bucket
# (min.node.size = 2 × min.bucket), como en Probst, Boulesteix y Bischl (2019, JMLR) para rpart.
# Pérdidas: MSE -> la hoja predice la media; MAE -> la mediana (árbol LAD, Breiman et al. 1984, cap. 8).
# Los cortes son por varianza en ambos casos (ranger no corta por desviación absoluta); las dos predicciones
# salen del mismo árbol. Precio por m2: sin log_area; precio = predicción × m2 (en log: + log_area).
# Validación: una localidad afuera con buffer (cv_oof, D9). Selección por MAE OOF total.
# Salidas: tables/cart_grilla.csv; registro m11_cart_{mse,mae} y m11_cart_m2_{mse,mae}
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(ranger))

objetivos <- arma_objetivos(matriz_arboles(TR), matriz_arboles(TE))

# Ajusta un árbol con (Xa, ya) y predice Xe con la media (mse) y la mediana (mae) de las hojas
hojas <- function(Xa, ya, Xe, prof, hoja) {
  fit <- ranger(x = Xa, y = ya, num.trees = 1, mtry = ncol(Xa), replace = FALSE, sample.fraction = 1,
                max.depth = prof, min.bucket = hoja, min.node.size = 2 * hoja, seed = 123, num.threads = 1)
  na <- predict(fit, Xa, type = "terminalNodes", num.threads = 1)$predictions[, 1]
  ne <- as.character(predict(fit, Xe, type = "terminalNodes", num.threads = 1)$predictions[, 1])
  p <- cbind(mse = tapply(ya, na, mean)[ne], mae = tapply(ya, na, median)[ne])
  stopifnot(isTRUE(all.equal(unname(p[, "mse"]), predict(fit, Xe, num.threads = 1)$predictions)))  # media = predicción de ranger
  p
}

grilla <- expand_grid(objetivo = names(objetivos), max.depth = c(3, 4, 5, 6, 8, 10, 12, 15, 0),
                      min.bucket = c(5, 20, 50, 100, 200, 500))
res <- pmap_dfr(grilla, function(objetivo, max.depth, min.bucket) {
  o <- objetivos[[objetivo]]
  oof <- cv_oof(function(a, e) hojas(o$Xtr[a, ], o$y[a], o$Xtr[e, ], max.depth, min.bucket)) + o$off_tr
  map_dfr(c("mse", "mae"), \(p) tibble(objetivo, perdida = p, max.depth, min.bucket, oof = list(oof[, p])) %>%
            bind_cols(evalua(oof[, p])))
})
tabla <- select(res, -oof)
write_csv(tabla, file.path(P$rep_mod, "tables", "cart_grilla.csv"))
print(as.data.frame(tabla %>% group_by(objetivo, perdida) %>% slice_min(mae_total, n = 5) %>% ungroup() %>%
                      mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1)), mape_chapinero = round(mape_chapinero, 3))))

# ---- Mejor árbol por objetivo y pérdida: reajuste con todo el train, registro y envío ----
for (k in seq_len(nrow(distinct(res, objetivo, perdida)))) {
  b <- res %>% group_by(objetivo, perdida) %>% slice_min(mae_total, n = 1, with_ties = FALSE) %>% ungroup() %>% slice(k)
  o <- objetivos[[b$objetivo]]
  pt <- hojas(o$Xtr, o$y, o$Xte, b$max.depth, b$min.bucket)[, b$perdida] + o$off_te
  registra(paste0("m11_cart_", if (b$objetivo == "m2") "m2_", b$perdida),
           sprintf("CART (ranger, 1 árbol) sobre %s; hoja = %s", c(precio = "log(precio)", m2 = "log(precio por m2) sin log_area; precio = predicción × m2")[[b$objetivo]],
                   c(mse = "media (MSE)", mae = "mediana (MAE)")[[b$perdida]]),
           sprintf("max.depth=%d; min.bucket=%d", b$max.depth, b$min.bucket),
           select(b, starts_with("ma")), b$oof[[1]], pt)
}
