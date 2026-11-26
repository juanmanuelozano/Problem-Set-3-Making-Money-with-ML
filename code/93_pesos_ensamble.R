# =============================================================================
# 93_pesos_ensamble.R - Pesos óptimos de un ensamble usando los scores públicos de Kaggle (D22)
# Con un solo envío disponible no se pueden probar pesos en Kaggle. Pero se conoce el MAE público de cada modelo
# y sus predicciones sobre el test, así que se puede estimar cuánto se parecen sus errores SIN conocer los precios:
#   si los errores son aproximadamente normales, E|e| = sigma * sqrt(2/pi), y para dos modelos i, j:
#   E|p_i - p_j| = E|e_i - e_j| = sqrt(2/pi) * sd(e_i - e_j)  ->  Cov(e_i, e_j) = (s_i^2 + s_j^2 - D_ij) / 2.
#   Los pesos (no negativos, suman 1) minimizan la varianza del error combinado w' S w.
# Garantía: el valor absoluto es convexo, así que el MAE del promedio ponderado de PRECIOS nunca supera el promedio
# ponderado de los MAE (cota exacta en el test de Kaggle).
# Verificación del método: en las predicciones out-of-fold del train (CV por localidad, D9), donde sí se conoce el
# precio, se compara el MAE estimado del ensamble óptimo con el MAE real.
# Entradas (D28): registro OOF y envíos tal como se calificaron en Kaggle, leídos de commits fijos con desde_git().
#   main volvió a entrenar m04, m02b y m06, así que sus archivos actuales ya no son los que tienen esos scores.
# Salidas: tables/ensamble_pesos.csv, submissions/m24_ens_optimo.csv
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))

ENVIOS_MJ <- "589aff9"    # validacion-sintetica: OOF y envíos de la rama (m20, m21, m22, m04, m02b, m06...)
ENVIOS_REDES <- "f5786a2" # redes-neuronales: m17 y m18, los calificados en Kaggle

K <- sqrt(pi / 2) # sigma = K × MAE bajo normalidad

# mae: vector; P: matriz de predicciones (filas = anuncios)
pesos_optimos <- function(mae, P) {
  n <- length(mae)
  s2 <- (mae * K)^2
  D <- outer(seq_len(n), seq_len(n), Vectorize(function(i, j) (mean(abs(P[, i] - P[, j])) * K)^2))
  S <- (outer(s2, s2, "+") - D) / 2
  e <- eigen(S, symmetric = TRUE) # asegura una matriz semidefinida positiva
  S <- e$vectors %*% diag(pmax(e$values, 1e-8 * max(e$values))) %*% t(e$vectors)
  f <- function(z) {
    w <- exp(z) / sum(exp(z))
    drop(t(w) %*% S %*% w)
  }
  z <- optim(rep(0, n), f, method = "BFGS", control = list(maxit = 2000, reltol = 1e-14))$par
  w <- exp(z) / sum(exp(z))
  w[w < 1e-3] <- 0
  w <- w / sum(w)
  list(w = w, mae_est = sqrt(drop(t(w) %*% S %*% w)) / K, cota = sum(w * mae))
}

# ---- 1. Verificación en el train: OOF de la CV por localidad (todos con la misma validación) ----
oof <- lee_csv_git(ENVIOS_MJ, "models/oof_predicciones.csv")
stopifnot(identical(oof$property_id, TR$property_id))
mods_v <- c(
  "m02b_elastic_net_m2", "m04_xgboost", "m03_random_forest", "m14_en_enc_tx", "m06_hibrido_en_xgb",
  "m13_xgb_star_m2", "m11_cart_m2_mse", "m20_en_sin_pesos_m2"
)
y <- exp(oof$log_price)
Pv <- sapply(mods_v, function(m) recorta(exp(oof[[m]])))
mae_v <- colMeans(abs(Pv - y))
ov <- pesos_optimos(mae_v, Pv)
real_v <- mean(abs(drop(Pv %*% ov$w) - y))
cat(sprintf(
  "Verificación (train, OOF por localidad): mejor individual %.1f M | ensamble óptimo: estimado %.1f M, REAL %.1f M, cota %.1f M\n",
  min(mae_v) / 1e6, ov$mae_est / 1e6, real_v / 1e6, ov$cota / 1e6
))
tibble(modelo = mods_v, mae = round(mae_v / 1e6, 1), peso = round(ov$w, 3)) %>%
  filter(peso > 0) %>%
  print()

# ---- 2. Test: pesos con los scores públicos de Kaggle ----
cand <- tribble(
  ~modelo,                     ~archivo,                      ~commit,      ~kaggle,
  "NN STAR (Samuel)",          "m17_nn_star_m2.csv",          ENVIOS_REDES, 158281022.13,
  "XGB + comparables",         "m22_xgb_comparables_m2.csv",  ENVIOS_MJ,    162936278.45,
  "Lasso + comparables",       "m21_en_comparables_m2.csv",   ENVIOS_MJ,    167128697.87,
  "NN 64 (Samuel)",            "m18_nn_64_m2.csv",            ENVIOS_REDES, 167453111.01,
  "EN + encoder texto (m14)",  "en_enc_tx.csv",               ENVIOS_MJ,    168831256.43,
  "Random forest m2",          "m15_rf_m2.csv",               ENVIOS_MJ,    170070460.29,
  "Lasso m2 base nueva (m20)", "m20_en_sin_pesos_m2.csv",     ENVIOS_MJ,    171595651.75,
  "XGBoost (m04)",             "m04_xgboost.csv",             ENVIOS_MJ,    172650639.71,
  "EN m2 (m02b)",              "m02b_elastic_net_m2.csv",     ENVIOS_MJ,    172741166.40,
  "Híbrido EN+XGB (m06)",      "m06_hibrido_en_xgb.csv",      ENVIOS_MJ,    178606472.86
)
subs <- map2(cand$commit, cand$archivo, ~ lee_csv_git(.x, file.path("submissions", .y)))
ids <- subs[[1]]$property_id
Pt <- sapply(subs, function(s) {
  stopifnot(setequal(s$property_id, ids))
  s$price[match(ids, s$property_id)]
})
colnames(Pt) <- cand$modelo
ot <- pesos_optimos(cand$kaggle, Pt)
tab <- cand %>%
  mutate(kaggle_M = round(kaggle / 1e6, 1), peso = round(ot$w, 3)) %>%
  select(modelo, kaggle_M, peso)
print(tab, n = Inf)
cat(sprintf(
  "Test: ensamble óptimo -> MAE estimado %.1f M | cota garantizada %.1f M | mejor individual %.1f M\n",
  ot$mae_est / 1e6, ot$cota / 1e6, min(cand$kaggle) / 1e6
))
w70 <- c(.7, .3, rep(0, nrow(cand) - 2))
s2 <- pesos_optimos(cand$kaggle[1:2], Pt[, 1:2]) # referencia: solo los dos primeros
cat(sprintf(
  "Referencia 70%% NN + 30%% XGB: cota %.1f M | óptimo con solo esos dos: pesos %s, estimado %.1f M\n",
  sum(w70 * cand$kaggle) / 1e6, paste(round(s2$w, 2), collapse = "/"), s2$mae_est / 1e6
))
write_csv(
  tab %>% mutate(mae_estimado_M = round(ot$mae_est / 1e6, 1), cota_M = round(ot$cota / 1e6, 1)),
  file.path(P$tab_mod, "ensamble_pesos.csv")
)
write_csv(
  tibble(property_id = ids, price = round(recorta(drop(Pt %*% ot$w)))),
  file.path(P$subs, "m24_ens_optimo.csv")
)
cat("Escrito: submissions/m24_ens_optimo.csv\n")
